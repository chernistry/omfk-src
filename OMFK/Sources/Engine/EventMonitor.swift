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
    private let logger = Logger.events
    private let settings: SettingsManager
    private var isReplacing: Bool = false  // Flag to ignore our own events during replacement
    
    init(engine: CorrectionEngine) {
        self.engine = engine
        self.settings = SettingsManager.shared
        logger.info("EventMonitor initialized")
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
    private var shiftWasHeldWithOption = false  // Track if Shift was held with Option
    private var phraseBuffer: String = ""  // Buffer for entire phrase (cleared on app switch/click)
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("⚠️ Event tap was disabled (timeout/user input), re-enabling...")
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Ignore our own events during text replacement
        if isReplacing {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // Handle flagsChanged for Option key (modifier keys don't generate keyDown)
        if type == .flagsChanged {
            let isOptionPressed = flags.contains(.maskAlternate)
            let isShiftPressed = flags.contains(.maskShift)
            
            // Detect Option key tap (press and release without other keys)
            if settings.hotkeyEnabled && settings.hotkeyKeyCode == 58 {
                if isOptionPressed && !optionKeyWasPressed {
                    // Option just pressed - track if Shift is also held
                    optionKeyWasPressed = true
                    shiftWasHeldWithOption = isShiftPressed
                } else if !isOptionPressed && optionKeyWasPressed {
                    // Option just released - this is a tap!
                    optionKeyWasPressed = false
                    let wasShiftHeld = shiftWasHeldWithOption
                    shiftWasHeldWithOption = false
                    
                    if wasShiftHeld {
                        // Shift+Option = convert last phrase/line
                        logger.info("🔥 SHIFT+OPTION TAP - converting last phrase")
                        Task { @MainActor in
                            await handleHotkeyPress(convertPhrase: true)
                        }
                    } else {
                        // Option only = convert last word
                        logger.info("🔥 OPTION TAP - converting last word")
                        Task { @MainActor in
                            await handleHotkeyPress(convertPhrase: false)
                        }
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Reset option tracking if any other key is pressed while Option is held
        if optionKeyWasPressed {
            optionKeyWasPressed = false
            shiftWasHeldWithOption = false
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        logger.debug("🔵 KEY EVENT: keyCode=\(keyCode), flags=\(flags.rawValue)")
        
        let now = Date()
        let timeSinceLastEvent = now.timeIntervalSince(lastEventTime)
        if timeSinceLastEvent > 2.0 {
            if !buffer.isEmpty {
                logger.info("⏱️ Buffer timeout (\(String(format: "%.1f", timeSinceLastEvent))s) - clearing buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            }
            buffer = ""
            phraseBuffer = ""  // Also clear phrase on timeout
        }
        lastEventTime = now
        
        if let chars = event.keyboardEventCharacters {
            buffer.append(chars)
            phraseBuffer.append(chars)
            logger.info("⌨️ Typed: \(DecisionLogger.tokenSummary(chars), privacy: .public) | Buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            
            // Reset cycling state on new input
            Task { @MainActor in
                await engine.resetCycling()
                lastCorrectedLength = 0
                lastCorrectedText = ""
            }
            
            // Process on word boundaries
            if chars.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                logger.info("📍 Word boundary detected (space/newline) - processing buffer")
                // Capture buffer content before clearing to avoid race condition
                let textToProcess = buffer
                buffer = ""  // Clear immediately to prevent next char from being added
                Task { @MainActor in
                    await self.processBufferContent(textToProcess)
                }
            }
        } else {
            logger.debug("⚠️ No characters extracted from keyCode \(keyCode)")
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func processBufferContent(_ bufferContent: String) async {
        let text = bufferContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let letterCount = text.filter { $0.isLetter }.count
        guard letterCount >= 2 else {
            logger.debug("⏭️ Buffer too short (\(text.count) chars / \(letterCount) letters), skipping: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return
        }
        
        // Count only the word length (without trailing whitespace)
        // The space that triggered processing is AFTER the cursor, we only delete the word
        let wordLength = text.count
        
        logger.info("🔍 Processing buffer: \(DecisionLogger.tokenSummary(text), privacy: .public) (word len: \(wordLength))")
        
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

        if let corrected = await engine.correctText(text, expectedLayout: expectedLayout) {
            logger.info("✅ CORRECTION APPLIED: \(DecisionLogger.tokenSummary(text), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            // Delete word + the space that triggered (cursor is after space)
            await replaceText(with: corrected + " ", originalLength: wordLength + 1)
            lastCorrectedLength = corrected.count + 1
            lastCorrectedText = corrected
        } else {
            logger.info("ℹ️ No correction needed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        }
        
        logger.debug("🧹 Buffer processing complete")
    }
    
    private func handleHotkeyPress(convertPhrase: Bool = false) async {
        logger.info("🔥 === HOTKEY PRESSED - \(convertPhrase ? "PHRASE" : "WORD") Mode ===")
        
        // First check if we have a recent auto-correction to undo/cycle
        if await engine.hasCyclingState() {
            logger.info("🔄 Cycling through alternatives for recent correction")
            if let corrected = await engine.cycleCorrection(bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
                let hadSpace = await engine.cyclingHadTrailingSpace()
                let lengthToDelete = lastCorrectedLength
                let textToType = hadSpace ? corrected + " " : corrected
                logger.info("✅ CYCLING: → \(DecisionLogger.tokenSummary(corrected), privacy: .public) (deleting \(lengthToDelete) chars, space: \(hadSpace))")
                await replaceText(with: textToType, originalLength: lengthToDelete)
                lastCorrectedLength = textToType.count
                lastCorrectedText = corrected
            }
            return
        }
        
        // Get text to convert
        let text: String
        if convertPhrase {
            // Shift+Option: use entire phrase buffer
            text = phraseBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("📝 Phrase mode - using phraseBuffer: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        } else {
            // Option only: get last word
            text = await getSelectedOrLastWord()
        }
        
        guard !text.isEmpty else {
            logger.warning("⚠️ No text to correct")
            return
        }
        
        logger.info("📝 Text for manual correction: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        if let corrected = await engine.correctLastWord(text, bundleId: bundleId) {
            logger.info("✅ MANUAL CORRECTION: \(DecisionLogger.tokenSummary(text), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            let lengthToDelete = convertPhrase ? phraseBuffer.count : text.count
            await replaceText(with: corrected, originalLength: lengthToDelete)
            lastCorrectedLength = corrected.count
            lastCorrectedText = corrected
            
            // Switch system layout to match the corrected text language
            if let targetLang = await engine.getLastCorrectionTargetLanguage() {
                InputSourceManager.shared.switchTo(language: targetLang)
                logger.info("🔄 Switched system layout to: \(targetLang.rawValue)")
            }
        } else {
            logger.warning("❌ Manual correction failed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        }
    }
    
    private func getSelectedOrLastWord() async -> String {
        logger.debug("🔍 Attempting to get selected text or last word...")
        
        // Priority 1: Use our own buffer (most reliable, no external dependencies)
        if !lastCorrectedText.isEmpty {
            logger.info("✅ Using last corrected text: \(DecisionLogger.tokenSummary(self.lastCorrectedText), privacy: .public)")
            return lastCorrectedText
        }
        
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            logger.info("✅ Using buffer text: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return text
        }
        
        // Priority 2: Try Accessibility API (kAXSelectedTextAttribute)
        if let axText = getSelectedTextViaAccessibility() {
            let trimmed = axText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logger.info("✅ Using AX selected text: \(DecisionLogger.tokenSummary(trimmed), privacy: .public)")
                return trimmed
            }
        }
        
        // Priority 3: Fallback to clipboard (for apps where AX doesn't work)
        logger.debug("⚠️ No buffer or AX selection, falling back to clipboard...")
        let pb = NSPasteboard.general
        let originalContents = pb.string(forType: .string)
        pb.clearContents()

        postKeyEvent(keyCode: 0x08, flags: .maskCommand) // Cmd+C
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        if let selected = pb.string(forType: .string), 
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           selected != originalContents {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("✅ Using clipboard selection: \(DecisionLogger.tokenSummary(trimmed), privacy: .public)")
            return trimmed
        }
        
        // Priority 4: Select word backward and copy
        logger.debug("⚠️ No clipboard selection, trying word selection...")
        pb.clearContents()
        postKeyEvent(keyCode: 0x7B, flags: [.maskAlternate, .maskShift]) // Option+Shift+Left
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        postKeyEvent(keyCode: 0x08, flags: .maskCommand) // Cmd+C
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let result = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Restore original clipboard if we got nothing
        if result.isEmpty, let original = originalContents {
            pb.clearContents()
            pb.setString(original, forType: .string)
        }
        
        if !result.isEmpty {
            logger.info("✅ Selected word backward: \(DecisionLogger.tokenSummary(result), privacy: .public)")
        } else {
            logger.warning("❌ Failed to get any text")
        }
        return result
    }
    
    /// Get selected text via Accessibility API (kAXSelectedTextAttribute)
    private func getSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            logger.debug("⚠️ AX: Could not get focused element")
            return nil
        }
        
        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
              let text = selectedText as? String else {
            logger.debug("⚠️ AX: Could not get selected text attribute")
            return nil
        }
        
        return text
    }
    
    /// Post a keyboard event with proper keyDown and keyUp
    private func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private func replaceText(with newText: String, originalLength: Int) async {
        logger.info("🔄 Replacing text: deleting \(originalLength) chars, typing \(DecisionLogger.tokenSummary(newText), privacy: .public)")
        
        // Set flag to ignore our own events
        isReplacing = true
        defer { isReplacing = false }
        
        // Delete original text using backspace
        for _ in 0..<originalLength {
            postKeyEvent(keyCode: 0x33, flags: []) // Backspace key
        }
        
        // Longer delay to ensure all deletions are processed before typing
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Type new text using Unicode string method
        typeUnicodeString(newText)
        
        // Wait for typing to complete
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        logger.info("✅ Text replacement complete")
    }
    
    /// Type a string using CGEvent's Unicode string capability
    private func typeUnicodeString(_ string: String) {
        let chars = Array(string.utf16)
        
        // CGEvent can handle up to ~20 characters at once
        let chunkSize = 20
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            var chunk = Array(chars[i..<end])
            
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                continue
            }
            event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            event.post(tap: .cghidEventTap)
            
            // Also post keyUp for completeness
            if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                upEvent.post(tap: .cghidEventTap)
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
