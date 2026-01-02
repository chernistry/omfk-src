import Foundation
import AppKit
import CoreGraphics
import Carbon
import os.log

@MainActor
final class EventMonitor {
    private let engine: CorrectionEngine
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer: String = ""
    private var lastEventTime: Date = .distantPast
    private var lastCorrectedLength: Int = 0
    private var lastCorrectedText: String = ""
    private var lastCorrectionTime: Date = .distantPast
    private var cyclingActive: Bool = false  // Flag to freeze buffers during cycling
    private var cyclingStartTime: Date = .distantPast  // When cycling started
    private var cyclingMinDuration: TimeInterval { ThresholdsConfig.shared.timing.cyclingMinDuration }
    private var lastActiveApp: String = ""
    private let logger = Logger.events
    private let settings: SettingsManager
    
    private let syntheticEventSource: CGEventSource?
    private let timeProvider: TimeProvider
    private let charEncoder: CharacterEncoder
    
    // Internal flag for testing
    internal var skipPIDCheck = false
    
    init(engine: CorrectionEngine, timeProvider: TimeProvider = RealTimeProvider(), charEncoder: CharacterEncoder = DefaultCharacterEncoder()) {
        self.engine = engine
        self.settings = SettingsManager.shared
        self.timeProvider = timeProvider
        self.charEncoder = charEncoder
        self.syntheticEventSource = CGEventSource(stateID: .privateState)
        logger.info("EventMonitor initialized")
        setupAppChangeObserver()
    }
    
    private func setupAppChangeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetOnAppChange()
            }
        }
    }
    
    private func resetOnAppChange() {
        let newApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if newApp != lastActiveApp && !lastActiveApp.isEmpty {
            logger.info("App changed: \(self.lastActiveApp) → \(newApp), resetting cycling")
            lastCorrectedLength = 0
            lastCorrectedText = ""
            phraseBuffer = ""
            buffer = ""
            Task { await engine.resetCycling() }
        }
        lastActiveApp = newApp
    }
    
    func start() async {
        logger.info("=== EventMonitor start() called ===")
        logger.info("Settings - enabled: \(self.settings.isEnabled), autoSwitch: \(self.settings.autoSwitchLayout), hotkeyEnabled: \(self.settings.hotkeyEnabled), hotkeyKeyCode: \(self.settings.hotkeyKeyCode)")
        
        guard checkAccessibility() else {
            logger.error("❌ Accessibility permission denied - cannot create event tap")
            requestAccessibility()
            return
        }
        logger.info("✅ Accessibility permission granted")
        
        // Listen for keyDown and flagsChanged (for modifier keys like Option)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        logger.info("Creating event tap with mask: \(eventMask)")
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("❌ CRITICAL: Failed to create event tap - check permissions")
            return
        }
        
        logger.info("✅ Event tap created successfully")
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        logger.info("✅ Event monitor started and enabled - waiting for keyboard events...")
        logger.info("=== EventMonitor is now active ===")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        buffer = ""
        logger.info("Event monitor stopped")
    }
    
    private var optionKeyWasPressed = false  // Track Option key state for tap detection
    private var phraseBuffer: String = ""  // Buffer for entire phrase (cleared on app switch/click)
    private var lastHotkeyTime: Date = .distantPast  // Debounce hotkey
    private var lastSelectAllTime: Date = .distantPast  // Cmd+A tracking for full-clear detection
    private var currentProxy: CGEventTapProxy?  // Store proxy for posting events "after" our tap
    
    private enum DeferredInput {
        case text(String)
        case keyEvent(keyCode: CGKeyCode, flags: CGEventFlags)
        case backspace(Int)
    }
    
    private var deferredInputs: [DeferredInput] = []
    private var layoutBeforeCycling: String?  // Store layout ID before cycling starts
    private var languageBeforeCycling: Language?  // Fallback when layout ID is unavailable
    private var keyboardLayoutDataCache: [String: Data] = [:]

    private func deferText(_ text: String) {
        guard !text.isEmpty else { return }
        if case .text(let existing) = deferredInputs.last {
            deferredInputs[deferredInputs.count - 1] = .text(existing + text)
        } else {
            deferredInputs.append(.text(text))
        }
    }

    private func deferKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        deferredInputs.append(.keyEvent(keyCode: keyCode, flags: flags))
    }
    
    private func deferBackspace(count: Int = 1) {
        guard count > 0 else { return }
        if case .backspace(let existing) = deferredInputs.last {
            deferredInputs[deferredInputs.count - 1] = .backspace(existing + count)
        } else {
            deferredInputs.append(.backspace(count))
        }
    }
    
    private func keyboardLayoutData(forAppleId appleId: String) -> Data? {
        if let cached = keyboardLayoutDataCache[appleId] {
            return cached
        }
        
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceType: kTISTypeKeyboardLayout as Any
        ]
        
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return nil
        }
        
        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let src = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = unsafeBitCast(src, to: TISInputSource.self)
            
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceId = unsafeBitCast(idPtr, to: CFString.self) as String
            guard sourceId == appleId else { continue }
            
            guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                return nil
            }
            
            let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
            keyboardLayoutDataCache[appleId] = data
            return data
        }
        
        return nil
    }
    
    private func translateKeyCode(_ keyCode: CGKeyCode, flags: CGEventFlags, layoutData: Data, deadKeyState: inout UInt32) -> String? {
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey >> 8) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey >> 8) }
        
        let status = layoutData.withUnsafeBytes { ptr -> OSStatus in
            guard let layoutPtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
    
    private func flushDeferredInputs(proxy: CGEventTapProxy, usingLayoutId layoutId: String?) {
        guard !deferredInputs.isEmpty else { return }
        
        let layoutData = layoutId.flatMap(keyboardLayoutData(forAppleId:))
        var deadKeyState: UInt32 = 0
        var bufferedText = ""
        bufferedText.reserveCapacity(min(ThresholdsConfig.shared.correction.bufferReserveCapacity, deferredInputs.count))
        
        func flushBufferedText() {
            guard !bufferedText.isEmpty else { return }
            typeUnicodeString(bufferedText, proxy: proxy)
            bufferedText.removeAll(keepingCapacity: true)
        }
        
        for item in deferredInputs {
            switch item {
            case .text(let text):
                // Already translated text - just append
                bufferedText.append(text)
            case .keyEvent(let keyCode, let flags):
                // Never turn command/control chords into Unicode typing.
                if flags.contains(.maskCommand) || flags.contains(.maskControl) {
                    flushBufferedText()
                    postKeyEvent(keyCode: keyCode, flags: flags, proxy: proxy)
                    continue
                }
                
                if let layoutData,
                   let translated = translateKeyCode(keyCode, flags: flags, layoutData: layoutData, deadKeyState: &deadKeyState) {
                    bufferedText.append(translated)
                } else {
                    flushBufferedText()
                    postKeyEvent(keyCode: keyCode, flags: flags, proxy: proxy)
                }
            case .backspace(let count):
                flushBufferedText()
                for _ in 0..<count {
                    postKeyEvent(keyCode: 0x33, flags: [], proxy: proxy)
                }
            }
        }
        
        flushBufferedText()
        deferredInputs.removeAll(keepingCapacity: true)
    }

    private func waitForLayoutId(_ appleId: String, timeout: TimeInterval) async -> Bool {
        let deadline = timeProvider.now.addingTimeInterval(timeout)
        while timeProvider.now < deadline {
            if InputSourceManager.shared.currentLayoutId() == appleId {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        return InputSourceManager.shared.currentLayoutId() == appleId
    }

    private func waitForLanguage(_ language: Language, timeout: TimeInterval) async -> Bool {
        let deadline = timeProvider.now.addingTimeInterval(timeout)
        while timeProvider.now < deadline {
            if InputSourceManager.shared.currentLanguage() == language {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        return InputSourceManager.shared.currentLanguage() == language
    }

    private func flushDeferredInputsAfterRestoringLayout(proxy: CGEventTapProxy, savedLayoutId: String?, savedLanguage: Language?) async {
        if !deferredInputs.isEmpty {
            if let savedLayoutId {
                InputSourceManager.shared.switchToLayoutId(savedLayoutId)
                let ok = await waitForLayoutId(savedLayoutId, timeout: ThresholdsConfig.shared.timing.layoutSwitchTimeout)
                if !ok {
                    logger.warning("⚠️ Layout restore timeout (expected: \(savedLayoutId, privacy: .public), actual: \(InputSourceManager.shared.currentLayoutId() ?? "nil", privacy: .public))")
                }
            } else if let savedLanguage {
                InputSourceManager.shared.switchTo(language: savedLanguage)
                _ = await waitForLanguage(savedLanguage, timeout: ThresholdsConfig.shared.timing.layoutSwitchTimeout)
            }
        }
        let layoutIdForTranslation = savedLayoutId ?? InputSourceManager.shared.currentLayoutId()
        flushDeferredInputs(proxy: proxy, usingLayoutId: layoutIdForTranslation)
        cyclingActive = false
        // Don't reset layoutBeforeCycling here - let the time-based window handle it
        // so fast typing after Alt can still be captured
    }

    private static var wordBoundaryPunctuation: Set<Character> { PunctuationConfig.shared.wordBoundary }
    
    private static var sentenceEndingPunctuation: Set<Character> { PunctuationConfig.shared.sentenceEnding }
    
    private static var leadingDelimiters: Set<Character> { PunctuationConfig.shared.leadingDelimiters }
    
    private static var trailingDelimiters: Set<Character> { PunctuationConfig.shared.trailingDelimiters }
    
    private func isDelimiterLikeCharacter(_ ch: Character) -> Bool {
        ch.isWhitespace || ch.isNewline || Self.wordBoundaryPunctuation.contains(ch) || Self.trailingDelimiters.contains(ch) || ch == "-" || ch == "—" || ch == "–"
    }
    
    private func isWordBoundaryTrigger(_ text: String) -> Bool {
        for ch in text {
            if ch.isWhitespace || ch.isNewline {
                return true
            }
        }
        return false
    }
    
    private func shouldExtendLastCorrectedSuffix(with text: String, bufferWasEmpty: Bool) -> Bool {
        guard bufferWasEmpty, lastCorrectedLength > 0 else { return false }
        
        guard bufferWasEmpty, lastCorrectedLength > 0 else { return false }
        
        let timeSinceLastCorrection = timeProvider.now.timeIntervalSince(lastCorrectionTime)
        guard timeSinceLastCorrection < ThresholdsConfig.shared.timing.lastCorrectionTimeout else { return false }
        
        return text.allSatisfy(isDelimiterLikeCharacter)
    }
    
    private struct BufferParts {
        let leading: String
        let token: String
        let trailing: String
    }
    
    private func splitBufferContent(_ bufferContent: String) -> BufferParts {
        guard !bufferContent.isEmpty else {
            return BufferParts(leading: "", token: "", trailing: "")
        }
        
        let chars = Array(bufferContent)
        var start = 0
        var end = chars.count
        
        while start < end, Self.leadingDelimiters.contains(chars[start]) {
            start += 1
        }
        
        while end > start, isDelimiterLikeCharacter(chars[end - 1]) {
            // Don't strip '.' or ',' if:
            // 1. It's at the end and preceded by a letter (could be mapped RU letters like 'ю'/'б')
            // 2. It's between two letters (could be part of word like "hf,jnftn" → "работает")
            if (chars[end - 1] == "." || chars[end - 1] == ",") {
                // Check if preceded by letter
                let hasPrecedingLetter = end > 1 && chars[end - 2].isLetter
                // Check if followed by letter (not at actual end)
                let hasFollowingLetter = end < chars.count && chars[end].isLetter
                
                if hasPrecedingLetter {
                    break
                }
            }
            end -= 1
        }
        
        let leading = String(chars[0..<start])
        let token = String(chars[start..<end])
        let trailing = String(chars[end..<chars.count])
        return BufferParts(leading: leading, token: token, trailing: trailing)
    }
    
    // Made internal for testing
    internal func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Store proxy for use in replacement methods
        currentProxy = proxy
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("⚠️ Event tap was disabled (timeout/user input), re-enabling...")
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Filter by PID - ignore events from our own process (backup)
        // In tests, we might want to process our own events
        if !skipPIDCheck {
            let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
            let myPID = Int64(getpid())
            if sourcePID == myPID && sourcePID != 0 {
                return Unmanaged.passUnretained(event)
            }
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Handle flagsChanged for Option key (modifier keys don't generate keyDown)
        if type == .flagsChanged {
            let isOptionPressed = flags.contains(.maskAlternate)
            
            // Detect Option key tap (press and release without other keys)
            if settings.hotkeyEnabled && settings.hotkeyKeyCode == 58 {
                if isOptionPressed && !optionKeyWasPressed {
                    // Option just pressed
                    optionKeyWasPressed = true
                } else if !isOptionPressed && optionKeyWasPressed {
                    // Option just released - this is a tap!
                    optionKeyWasPressed = false
                    
                    // Debounce: ignore if hotkey was triggered recently
                    let now = timeProvider.now
                    if now.timeIntervalSince(lastHotkeyTime) < 0.5 {
                        logger.debug("⏭️ Hotkey debounced (too soon after last)")
                        return Unmanaged.passUnretained(event)
                    }
                    lastHotkeyTime = now
                    
                    // Freeze buffers BEFORE starting async task
                    deferredInputs.removeAll(keepingCapacity: true)
                    layoutBeforeCycling = InputSourceManager.shared.currentLayoutId()
                    languageBeforeCycling = InputSourceManager.shared.currentLanguage()
                    cyclingActive = true
                    cyclingStartTime = timeProvider.now  // Track when cycling started
                    
                    // Single hotkey - context-aware behavior
                    logger.info("🔥 OPTION TAP - context-aware correction")
                    let capturedProxy = proxy
                    Task { @MainActor in
                        await handleHotkeyPress(proxy: capturedProxy)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Reset option tracking if any other key is pressed while Option is held
        if optionKeyWasPressed {
            optionKeyWasPressed = false
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        // Ignore key events with Command or Control modifiers (shortcuts like Cmd+C, Cmd+A),
        // but track Cmd+A so a following Delete can be treated as full-clear.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            if flags.contains(.maskCommand), keyCode == 0 {
                lastSelectAllTime = timeProvider.now
            }
            return Unmanaged.passUnretained(event)
        }

        logger.debug("🔵 KEY EVENT: keyCode=\(keyCode), flags=\(flags.rawValue)")

        // While cycling/replacing, swallow user keystrokes to prevent interleaving with backspaces/typing.
        // We translate keycodes to characters using the layout that was active BEFORE cycling started,
        // so the characters are correct regardless of what layout is active now.
        // While cycling/replacing, swallow user keystrokes to prevent interleaving with backspaces/typing.
        // Keep cycling active for at least cyclingMinDuration to capture fast typing after Alt.
        let timeSinceCyclingStart = timeProvider.now.timeIntervalSince(cyclingStartTime)
        let inCyclingWindow = cyclingActive || (timeSinceCyclingStart < cyclingMinDuration && layoutBeforeCycling != nil)
        
        logger.debug("⏱️ keyCode=\(keyCode) cyclingActive=\(self.cyclingActive) timeSince=\(timeSinceCyclingStart) layoutBefore=\(self.layoutBeforeCycling ?? "nil") inWindow=\(inCyclingWindow)")
        
        // If cycling window just ended, flush any accumulated deferred inputs
        if !inCyclingWindow && !deferredInputs.isEmpty && layoutBeforeCycling != nil {
            if let proxy = currentProxy {
                flushDeferredInputs(proxy: proxy, usingLayoutId: layoutBeforeCycling)
            }
            layoutBeforeCycling = nil
            languageBeforeCycling = nil
        }
        
        if inCyclingWindow {
            logger.debug("🔄 inCyclingWindow: keyCode=\(keyCode), layoutBeforeCycling=\(self.layoutBeforeCycling ?? "nil")")
            if keyCode == 51 {
                deferBackspace()
                return nil
            }
            // Translate keycode using layoutBeforeCycling - the layout user was typing in
            if let savedLayoutId = layoutBeforeCycling,
               let layoutData = keyboardLayoutData(forAppleId: savedLayoutId) {
                var deadKeyState: UInt32 = 0
                if let char = translateKeyCode(CGKeyCode(keyCode), flags: flags, layoutData: layoutData, deadKeyState: &deadKeyState) {
                    logger.debug("🔄 Translated keyCode \(keyCode) -> '\(char)' using \(savedLayoutId)")
                    deferText(char)
                    return nil
                }
            }
            // Fallback: store keycode if translation failed
            logger.debug("🔄 Translation failed, deferring keyEvent")
            deferKeyEvent(keyCode: CGKeyCode(keyCode), flags: flags)
            return nil
        }

        // Handle backspace/delete so internal buffers match the real text
        if keyCode == 51 {
            let now = timeProvider.now
            // Detect Cmd+A -> Delete full clear (common in tests and real usage).
            if now.timeIntervalSince(lastSelectAllTime) < 0.35 {
                lastSelectAllTime = .distantPast
                buffer = ""
                phraseBuffer = ""
                lastCorrectedLength = 0
                lastCorrectedText = ""
                lastCorrectionTime = .distantPast
                Task {
                    await engine.resetSentence()
                    await engine.resetCycling()
                }
                return Unmanaged.passUnretained(event)
            }
            if !buffer.isEmpty { buffer.removeLast() }
            if !phraseBuffer.isEmpty { phraseBuffer.removeLast() }
            return Unmanaged.passUnretained(event)
        }
        
        let now = timeProvider.now
        let timeSinceLastEvent = now.timeIntervalSince(lastEventTime)
        if timeSinceLastEvent > ThresholdsConfig.shared.timing.bufferTimeout {
            if !buffer.isEmpty {
                logger.info("⏱️ Buffer timeout (\(String(format: "%.1f", timeSinceLastEvent))s) - clearing buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            }
            buffer = ""
            phraseBuffer = ""  // Also clear phrase on timeout
            Task {
                await engine.resetSentence()
                await engine.resetCycling()
            }
        }
        lastEventTime = now
        
        // Filter by PID checked earlier
        
        // Debug prints removed
        
        let encoded = charEncoder.encode(event: event)
        
        if let chars = encoded {
             // Filter out control characters (keep only printable + space/newline)
             let filtered = chars.filter { char in
                 char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char == " " || char == "\n" || char == "\r" || char == "\t"
             }
             guard !filtered.isEmpty else {
                 return Unmanaged.passUnretained(event)
             }
            
            let bufferWasEmpty = buffer.isEmpty
            if shouldExtendLastCorrectedSuffix(with: filtered, bufferWasEmpty: bufferWasEmpty) {
                lastCorrectedText.append(filtered)
                lastCorrectedLength += filtered.count
            }
            
            buffer.append(filtered)
            phraseBuffer.append(filtered)
            logger.info("⌨️ Typed: \(DecisionLogger.tokenSummary(filtered), privacy: .public) | Buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            
            // Process on word boundaries (space/newline/punctuation triggers auto-correction)
            if isWordBoundaryTrigger(filtered) {
                logger.info("📍 Word boundary detected - processing buffer")
                // Capture buffer content AND proxy before clearing to avoid race condition
                let textToProcess = buffer
                let capturedProxy = proxy
                buffer = ""  // Clear immediately to prevent next char from being added
                Task { @MainActor in
                    await self.processBufferContent(textToProcess, proxy: capturedProxy)
                }
            } else {
                // Reset cycling state only on non-whitespace input (new word being typed)
                Task { @MainActor in
                    await engine.resetCycling()
                    lastCorrectedLength = 0
                    lastCorrectedText = ""
                }
            }
        } else {
            logger.debug("⚠️ No characters extracted from keyCode \(keyCode)")
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func processBufferContent(_ bufferContent: String, proxy: CGEventTapProxy) async {
        let parts = splitBufferContent(bufferContent)
        let text = parts.token
        let letterCount = text.filter { $0.isLetter }.count
        let totalTypedLength = bufferContent.count

        DecisionLogger.shared.log("PROCESS_BUFFER: raw=\(DecisionLogger.tokenSummary(bufferContent)) token=\(DecisionLogger.tokenSummary(text)) lead=\(DecisionLogger.tokenSummary(parts.leading)) trail=\(DecisionLogger.tokenSummary(parts.trailing))")
        
        // Special case: single Latin letters that are likely Russian prepositions/conjunctions
        // d→в, c→с, r→к, j→о, e→у, b→и, z→я (typed on EN keyboard instead of RU)
        // These are handled by CorrectionEngine's pending word mechanism now
        
        guard letterCount >= 1 else {
            logger.debug("⏭️ Buffer has no letters, skipping: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return
        }
        
        // For single-letter tokens, still send to CorrectionEngine so they can be stored as pending
        // The engine will decide whether to correct immediately or wait for context
        
        logger.info("🔍 Processing buffer: \(DecisionLogger.tokenSummary(text), privacy: .public) (segment len: \(totalTypedLength), word len: \(text.count))")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        logger.info("📱 Frontmost app: \(bundleId ?? "unknown", privacy: .public)")
        
        guard await engine.shouldCorrect(for: bundleId) else {
            logger.info("🚫 Correction disabled for app: \(bundleId ?? "unknown", privacy: .public)")
            return
        }
        
        logger.info("✅ Correction enabled for this app - proceeding...")

        let expectedLayout: Language? = settings.autoSwitchLayout ? settings.preferredLanguage : nil
        if let expected = expectedLayout {
            logger.info("🎯 Auto-switch enabled, expected layout: \(expected.rawValue, privacy: .public)")
        }

        let result = await engine.correctText(text, expectedLayout: expectedLayout)
        
        // Handle pending word correction first (previous word that was boosted by context)
        if let pendingCorrected = result.pendingCorrection, let pendingOriginal = result.pendingOriginal {
            DecisionLogger.shared.log("REPLACE_PENDING: pendingOrig=\(DecisionLogger.tokenSummary(pendingOriginal)) pendingCorr=\(DecisionLogger.tokenSummary(pendingCorrected)) currTok=\(DecisionLogger.tokenSummary(text)) currCorr=\(DecisionLogger.tokenSummary(result.corrected ?? text))")
            logger.info("🔗 PENDING CORRECTION: '\(pendingOriginal)' → '\(pendingCorrected)'")
            logger.info("🔗 Current word: '\(text)' → '\(result.corrected ?? text)'")
            // Need to go back and fix the previous word
            // Previous word is: pendingOriginal + " " + current word
            // We need to delete: pendingOriginal.count + 1 (space) + wordLength + 1 (current space)
            let totalDeleteLength = pendingOriginal.count + 1 + text.count + parts.trailing.count
            let currentCorrected = result.corrected ?? text
            let replacement = pendingCorrected + " " + currentCorrected + parts.trailing
            DecisionLogger.shared.log("REPLACE_PENDING_APPLY: delete=\(totalDeleteLength) repl=\(DecisionLogger.tokenSummary(replacement))")
            logger.info("🔗 Delete \(totalDeleteLength) chars, replace with '\(replacement)' (\(replacement.count) chars)")
            await replaceText(with: replacement, originalLength: totalDeleteLength, proxy: proxy)
            lastCorrectedLength = replacement.count
            lastCorrectedText = replacement
            lastCorrectionTime = timeProvider.now
        } else if let corrected = result.corrected {
            DecisionLogger.shared.log("REPLACE_TOKEN: tok=\(DecisionLogger.tokenSummary(text)) corr=\(DecisionLogger.tokenSummary(corrected)) totalTyped=\(totalTypedLength)")
            logger.info("✅ CORRECTION APPLIED: \(DecisionLogger.tokenSummary(text), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            // If the original token ended with '.' or ',' and that character was used as a mapped letter
            // during correction (common for RU layout: '.'→'ю', ','→'б'), also preserve the literal
            // punctuation at the end when the user finished the token with whitespace.
            let replacement = parts.leading + corrected + parts.trailing
            DecisionLogger.shared.log("REPLACE_TOKEN_APPLY: delete=\(totalTypedLength) repl=\(DecisionLogger.tokenSummary(replacement))")
            await replaceText(with: replacement, originalLength: totalTypedLength, proxy: proxy)
            lastCorrectedLength = replacement.count
            lastCorrectedText = replacement
            lastCorrectionTime = timeProvider.now  // Enable cycling after auto-correction
        } else {
            DecisionLogger.shared.log("NO_REPLACE: tok=\(DecisionLogger.tokenSummary(text)) raw=\(DecisionLogger.tokenSummary(bufferContent))")
            logger.info("ℹ️ No correction needed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            // Still save the text for potential manual cycling
            let replacement = parts.leading + text + parts.trailing
            lastCorrectedLength = replacement.count
            lastCorrectedText = replacement
            lastCorrectionTime = timeProvider.now  // Enable cycling even without auto-correction
        }
        
        // Reset sentence state on sentence-ending punctuation
        if parts.trailing.contains(where: { Self.sentenceEndingPunctuation.contains($0) }) {
            await engine.resetSentence()
        }
        
        logger.debug("🧹 Buffer processing complete")
    }
    
    private func handleHotkeyPress(proxy: CGEventTapProxy) async {
        // Save current layout before cycling (for restoring before flush).
        // Prefer the value captured at the Option tap moment; fall back to the current layout.
        let savedLayoutId = layoutBeforeCycling ?? InputSourceManager.shared.currentLayoutId()
        
        // cyclingActive is already true (set before Task was created)
        // Characters typed during cycling are translated immediately using savedLayoutId
        
        defer {
            // Flush deferred inputs (already translated to correct characters)
            flushDeferredInputs(proxy: proxy, usingLayoutId: savedLayoutId)
            cyclingActive = false
            // Don't reset layoutBeforeCycling here - let the time-based window handle it
        }
        
        logger.info("🔥 === HOTKEY PRESSED ===")
        DecisionLogger.shared.log("HOTKEY: pressed")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        logger.info("📱 App: \(appName) (\(bundleId ?? "nil"))")
        DecisionLogger.shared.log("HOTKEY: App=\(appName)")
        
        // Log buffer state
        logger.info("📋 Buffer state: '\(self.buffer)' (\(self.buffer.count) chars)")
        DecisionLogger.shared.log("HOTKEY: Buffer='\(self.buffer)' (\(self.buffer.count))")
        
        // Check cycling FIRST - if we have valid cycling state and no new typing, continue cycling
        // This is needed because after replaceText, selection is lost
        let hasCycling = await engine.hasCyclingState()
        let timeSinceLastCorrection = timeProvider.now.timeIntervalSince(lastCorrectionTime)
        let noNewTyping = buffer.isEmpty && timeSinceLastCorrection < ThresholdsConfig.shared.timing.lastCorrectionTimeout
        
        // But first check if there's a fresh selection - it takes priority over cycling
        let freshSelection = await getSelectedTextFresh(proxy: proxy)
        let hasNewSelection = lastSelectionWasExplicit && !freshSelection.isEmpty && 
                              freshSelection.trimmingCharacters(in: .whitespacesAndNewlines) != lastCorrectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if hasCycling && noNewTyping && lastCorrectedLength > 0 && !hasNewSelection {
            let savedLength = lastCorrectedLength
            
            // Get the expected length from cycling state to verify consistency
            let expectedLength = await engine.getCurrentCyclingTextLength()
            let savedTextLength = lastCorrectedText.count
            let suffixLength = max(0, savedTextLength - expectedLength)
            let suffix = suffixLength > 0 ? String(lastCorrectedText.suffix(suffixLength)) : ""
            
            // Safety check: if lengths don't match, something went wrong - reset cycling
            let lengthMismatch =
                expectedLength <= 0 ||
                savedLength != savedTextLength ||
                savedLength < expectedLength ||
                (suffixLength > 0 && !suffix.allSatisfy(isDelimiterLikeCharacter))
            
            if lengthMismatch {
                logger.warning("⚠️ Length mismatch: saved=\(savedLength), expected=\(expectedLength), savedText=\(savedTextLength), suffixLen=\(suffixLength) - resetting cycling")
                await engine.resetCycling()
                lastCorrectedLength = 0
                lastCorrectedText = ""
                // Fall through to get fresh selection
            } else {
                logger.info("🔄 CYCLING: no new typing, using saved length (\(savedLength) chars)")
                DecisionLogger.shared.log("HOTKEY: CYCLING - savedLen=\(savedLength)")
                
                if let corrected = await engine.cycleCorrection(bundleId: bundleId) {
                    let finalCorrected = corrected + suffix
                    
                    logger.info("✅ CYCLING: → '\(corrected)' (deleting \(savedLength) chars, suffixLen=\(suffixLength))")
                    DecisionLogger.shared.log("HOTKEY: CYCLE RESULT: '\(corrected)' (delete \(savedLength), suffixLen=\(suffixLength))")
                    
                    await replaceText(with: finalCorrected, originalLength: savedLength, proxy: proxy)
                    
                    // Update to new length for next cycle
                    lastCorrectedLength = finalCorrected.count
                    lastCorrectedText = finalCorrected
                    lastCorrectionTime = timeProvider.now
                    buffer = ""
                    
                    if let targetLang = await engine.getLastCorrectionTargetLanguage() {
                        let preferredLayout = settings.activeLayouts[targetLang.rawValue]
                        let didSwitch = preferredLayout.map { InputSourceManager.shared.switchToLayoutVariant($0) } ?? false
                        if !didSwitch {
                            InputSourceManager.shared.switchTo(language: targetLang)
                        }
                        logger.info("🔄 Switched system layout to: \(targetLang.rawValue) (\(preferredLayout ?? "auto"))")
                    }
                }
                return
            }
        }
        
        // Use fresh selection for new correction
        let rawText = freshSelection
        let hex = rawText.unicodeScalars.prefix(20).map { String(format: "%04X", $0.value) }.joined(separator: " ")
        logger.info("📝 Fresh selection: '\(rawText)' (\(rawText.count) chars) hex: \(hex)")
        DecisionLogger.shared.log("HOTKEY: Fresh selection: '\(rawText)' (\(rawText.count) chars)")
        
        // Reset cycling state for new text
        if hasCycling {
            logger.info("🔄 New text detected, resetting cycling state")
            DecisionLogger.shared.log("HOTKEY: New text, resetting cycling")
        }
        await engine.resetCycling()
        lastCorrectedLength = 0
        lastCorrectedText = ""
        
        let textToConvert = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        DecisionLogger.shared.log("HOTKEY: Text to convert: '\(textToConvert)' (\(textToConvert.count) chars)")
        
        guard !textToConvert.isEmpty else {
            logger.warning("⚠️ No text to correct - textToConvert is empty")
            DecisionLogger.shared.log("HOTKEY: ERROR - no text to correct")
            return
        }
        
        logger.info("📝 Text for manual correction: '\(textToConvert)' (raw len: \(rawText.count))")
        DecisionLogger.shared.log("HOTKEY: Calling correctLastWord...")
        
        if let corrected = await engine.correctLastWord(textToConvert, bundleId: bundleId) {
            DecisionLogger.shared.log("HOTKEY: correctLastWord returned: '\(corrected)'")
            // Preserve leading/trailing whitespace from original
            let leadingWS = String(rawText.prefix(while: { $0.isWhitespace }))
            let trailingWS = String(rawText.reversed().prefix(while: { $0.isWhitespace }).reversed())
            let finalText = leadingWS + corrected + trailingWS
            
            logger.info("✅ MANUAL CORRECTION: \(DecisionLogger.tokenSummary(textToConvert), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            
            // Choose replacement method based on whether we have an explicit selection
            if lastSelectionWasExplicit {
                // Text is selected - just type over it (no backspaces needed)
                DecisionLogger.shared.log("HOTKEY: Typing over selection with '\(finalText)' (\(finalText.count) chars)")
                await typeOverSelection(with: finalText, proxy: proxy)
            } else {
                // No selection - use backspaces to delete buffer content
                DecisionLogger.shared.log("HOTKEY: Replacing \(rawText.count) chars with '\(finalText)' (\(finalText.count) chars)")
                await replaceText(with: finalText, originalLength: rawText.count, proxy: proxy)
            }
            
            lastCorrectedLength = finalText.count
            lastCorrectedText = finalText
            lastCorrectionTime = timeProvider.now
            buffer = ""  // Clear buffer after replacement
            DecisionLogger.shared.log("HOTKEY: Done. lastCorrectedLength=\(lastCorrectedLength)")
            
            // Switch system layout to match the corrected text language
            if let targetLang = await engine.getLastCorrectionTargetLanguage() {
                let preferredLayout = settings.activeLayouts[targetLang.rawValue]
                let didSwitch = preferredLayout.map { InputSourceManager.shared.switchToLayoutVariant($0) } ?? false
                if !didSwitch {
                    InputSourceManager.shared.switchTo(language: targetLang)
                }
                logger.info("🔄 Switched system layout to: \(targetLang.rawValue) (\(preferredLayout ?? "auto"))")
            }
        } else {
            logger.warning("❌ Manual correction failed for: \(DecisionLogger.tokenSummary(textToConvert), privacy: .public)")
            DecisionLogger.shared.log("HOTKEY: ERROR - correctLastWord returned nil!")
        }
    }
    
    /// Get FRESH selected text - prioritizes actual selection over buffer
    private var appsWithoutAXSelection: Set<String> = []
    private var lastSelectionWasExplicit: Bool = false
    
    private func getSelectedTextFresh(proxy: CGEventTapProxy) async -> String {
        lastSelectionWasExplicit = false
        let timeSinceLastKey = timeProvider.now.timeIntervalSince(lastEventTime)
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        // Selection should take priority over the internal buffer: users can select arbitrary text
        // unrelated to our recent typing (especially for single-word hotkey corrections).
        if appsWithoutAXSelection.contains(bundleId) {
            // App is known to not support AX selection: go straight to clipboard.
            if let clipboardText = await getSelectedTextViaClipboard(proxy: proxy), !clipboardText.isEmpty {
                lastSelectionWasExplicit = true
                return clipboardText
            }
        } else {
            // Try AX selection first (instant, no delay).
            if let axText = getSelectedTextViaAccessibility(), !axText.isEmpty {
                lastSelectionWasExplicit = true
                return axText
            }
        }

        // Fast path: use buffer if fresh (< 0.5s). This avoids clipboard side-effects when nothing is selected.
        if !buffer.isEmpty && timeSinceLastKey < 0.5 {
            lastSelectionWasExplicit = false
            return buffer
        }

        // Clipboard fallback (for apps without AX selection or when AX returned empty but selection still exists).
        if let clipboardText = await getSelectedTextViaClipboard(proxy: proxy), !clipboardText.isEmpty {
            if !appsWithoutAXSelection.contains(bundleId) {
                appsWithoutAXSelection.insert(bundleId)
                logger.info("📋 App '\(bundleId)' added to clipboard fallback list")
            }
            lastSelectionWasExplicit = true
            return clipboardText
        }
        
        // Fallback to buffer even if stale
        if !buffer.isEmpty {
            lastSelectionWasExplicit = false
            return buffer
        }
        
        return ""
    }
    
    /// Get selected text via clipboard (Cmd+C) - fallback for apps without AX support
    private func getSelectedTextViaClipboard(proxy: CGEventTapProxy) async -> String? {
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard content
        let savedContent = pasteboard.string(forType: .string)
        let savedChangeCount = pasteboard.changeCount
        
        // Clear clipboard to detect if copy worked
        pasteboard.clearContents()
        
        // Send Cmd+C
        guard let cmdC_down = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 8, keyDown: true),
              let cmdC_up = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 8, keyDown: false) else {
            // Restore clipboard
            if let saved = savedContent {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            return nil
        }
        
        cmdC_down.flags = .maskCommand
        cmdC_up.flags = .maskCommand
        
        cmdC_down.tapPostEvent(proxy)
        cmdC_up.tapPostEvent(proxy)
        
        // Wait for clipboard to update
        try? await Task.sleep(nanoseconds: ThresholdsConfig.shared.timing.clipboardDelayNs)
        
        // Check if clipboard changed
        let newContent = pasteboard.string(forType: .string)
        let gotNewContent = pasteboard.changeCount != savedChangeCount && newContent != nil
        
        // Restore original clipboard
        if let saved = savedContent {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
        
        if gotNewContent {
            return newContent
        }
        
        return nil
    }
    
    /// Get selected text via Accessibility API
    private func getSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }
        
        // Check if there's actually a selection range
        var selectedRange: AnyObject?
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            var range = CFRange()
            if AXValueGetValue(selectedRange as! AXValue, .cfRange, &range) {
                if range.length == 0 {
                    return nil
                }
            }
        }
        
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
              let text = selectedText as? String, !text.isEmpty else {
            return nil
        }
        
        return text
    }
    
    /// Post a keyboard event - uses CGEventTapPostEvent to post "after" our tap (won't be seen by us)
    private func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags, proxy: CGEventTapProxy) {
        guard let keyDown = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        // Post "after" our tap - these events won't come back to our handleEvent
        keyDown.tapPostEvent(proxy)
        keyUp.tapPostEvent(proxy)
    }
    
    /// Type over selected text
    private func typeOverSelection(with newText: String, proxy: CGEventTapProxy) async {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // For apps without AX support, use clipboard paste instead of typing
        if appsWithoutAXSelection.contains(bundleId) {
            await pasteText(newText, proxy: proxy)
        } else {
            typeUnicodeString(newText, proxy: proxy)
        }
    }
    
    /// Paste text via clipboard (Cmd+V) - for apps that don't accept CGEvent typing
    private func pasteText(_ text: String, proxy: CGEventTapProxy) async {
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard
        let savedContent = pasteboard.string(forType: .string)
        
        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Send Cmd+V
        guard let cmdV_down = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 9, keyDown: true),
              let cmdV_up = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 9, keyDown: false) else {
            // Restore clipboard
            if let saved = savedContent {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            return
        }
        
        cmdV_down.flags = .maskCommand
        cmdV_up.flags = .maskCommand
        
        cmdV_down.tapPostEvent(proxy)
        cmdV_up.tapPostEvent(proxy)
        
        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: ThresholdsConfig.shared.timing.pasteDelayNs)
        
        // Restore original clipboard
        if let saved = savedContent {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }
    
    private func replaceText(with newText: String, originalLength: Int, proxy: CGEventTapProxy) async {
        DecisionLogger.shared.log("REPLACE_TEXT: delete=\(originalLength) new=\(DecisionLogger.tokenSummary(newText))")
        // Send backspaces to delete original text
        for _ in 0..<originalLength {
            postKeyEvent(keyCode: 0x33, flags: [], proxy: proxy)
        }
        
        // Small delay for system to process deletions
        try? await Task.sleep(nanoseconds: ThresholdsConfig.shared.timing.deletionDelayNs)
        
        typeUnicodeString(newText, proxy: proxy)
    }
    
    /// Type a string using CGEvent - posts "after" our tap so we don't see our own events
    private func typeUnicodeString(_ string: String, proxy: CGEventTapProxy) {
        
        let filtered = string.unicodeScalars.filter { scalar in
            let value = scalar.value
            return value >= 0x20 || value == 0x09 || value == 0x0A || value == 0x0D
        }
        let safeString = String(String.UnicodeScalarView(filtered))
        
        if safeString.count != string.count {
            logger.warning("⚠️ Filtered \(string.count - safeString.count) control characters from output")
        }
        
        let chars = Array(safeString.utf16)
        guard !chars.isEmpty else { return }
        
        let chunkSize = ThresholdsConfig.shared.timing.typingChunkSize
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            var chunk = Array(chars[i..<end])
            
            guard let event = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 0, keyDown: true) else {
                continue
            }
            event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            event.tapPostEvent(proxy)  // Post "after" our tap
            
            if let upEvent = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: 0, keyDown: false) {
                upEvent.tapPostEvent(proxy)
            }
        }
    }
    
    private func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibility() {
        // Avoid referencing the global `kAXTrustedCheckOptionPrompt` var (Swift 6 concurrency warning).
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        // Start polling for permission grant
        Task { @MainActor in
            await self.startAccessibilityPolling()
        }
    }
    
    private var accessibilityPollTimer: Timer?
    
    private func startAccessibilityPolling() async {
        // Poll to check if permission was granted
        accessibilityPollTimer?.invalidate()
        
        while !AXIsProcessTrusted() {
            try? await Task.sleep(nanoseconds: ThresholdsConfig.shared.timing.accessibilityPollIntervalNs)
        }
        
        logger.info("✅ Accessibility permission granted - restarting event monitor")
        await start()
    }
}

extension CGEvent {
    var keyboardEventCharacters: String? {
        // Convert CGEvent to NSEvent to access characters property
        guard let nsEvent = NSEvent(cgEvent: self) else {
            return nil
        }
        
        let chars = nsEvent.characters
        
        // Filter out non-printable characters
        guard let chars = chars, !chars.isEmpty else {
            return nil
        }
        
        return chars
    }
}
