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
    private var lastActiveApp: String = ""
    private let logger = Logger.events
    private let settings: SettingsManager
    
    // Event source for synthetic events
    private let syntheticEventSource: CGEventSource?
    
    init(engine: CorrectionEngine) {
        self.engine = engine
        self.settings = SettingsManager.shared
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
    private var currentProxy: CGEventTapProxy?  // Store proxy for posting events "after" our tap
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
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
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let myPID = Int64(getpid())
        if sourcePID == myPID && sourcePID != 0 {
            return Unmanaged.passUnretained(event)
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
                    let now = Date()
                    if now.timeIntervalSince(lastHotkeyTime) < 0.5 {
                        logger.debug("⏭️ Hotkey debounced (too soon after last)")
                        return Unmanaged.passUnretained(event)
                    }
                    lastHotkeyTime = now
                    
                    // Freeze buffers BEFORE starting async task
                    cyclingActive = true
                    
                    // Single hotkey - context-aware behavior
                    logger.info("🔥 OPTION TAP - context-aware correction")
                    Task { @MainActor in
                        await handleHotkeyPress()
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
        
        // Ignore key events with Command or Control modifiers (shortcuts like Cmd+C, Cmd+A)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
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
            // Filter out control characters (keep only printable + space/newline)
            let filtered = chars.filter { char in
                char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char == " " || char == "\n" || char == "\t"
            }
            guard !filtered.isEmpty else {
                return Unmanaged.passUnretained(event)
            }
            
            // If cycling is active, ignore all typing (it's our synthetic events)
            if cyclingActive {
                return Unmanaged.passUnretained(event)
            }
            
            buffer.append(filtered)
            phraseBuffer.append(filtered)
            logger.info("⌨️ Typed: \(DecisionLogger.tokenSummary(filtered), privacy: .public) | Buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            
            // Process on word boundaries (space/newline triggers auto-correction)
            if chars.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                logger.info("📍 Word boundary detected (space/newline) - processing buffer")
                // Capture buffer content before clearing to avoid race condition
                let textToProcess = buffer
                buffer = ""  // Clear immediately to prevent next char from being added
                Task { @MainActor in
                    await self.processBufferContent(textToProcess)
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
    
    private func processBufferContent(_ bufferContent: String) async {
        let text = bufferContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let letterCount = text.filter { $0.isLetter }.count
        
        // Special case: single Latin letters that are likely Russian prepositions/conjunctions
        // d→в, c→с, r→к, j→о, e→у, b→и, z→я (typed on EN keyboard instead of RU)
        let singleLetterRuPrepositions: [Character: Character] = [
            "d": "в", "c": "с", "r": "к", "j": "о", "e": "у", "b": "и", "z": "я"
        ]
        
        if letterCount == 1, text.count == 1,
           let char = text.first,
           let ruPreposition = singleLetterRuPrepositions[Character(char.lowercased())] {
            // Check if preferred language is Russian
            if settings.preferredLanguage == .russian {
                let corrected = char.isUppercase ? String(ruPreposition).uppercased() : String(ruPreposition)
                logger.info("✅ Single letter preposition: '\(text)' → '\(corrected)'")
                await replaceText(with: corrected + " ", originalLength: 2) // +1 for space
                lastCorrectedLength = corrected.count + 1
                lastCorrectedText = corrected
                return
            }
        }
        
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
            let textWithSpace = corrected + " "
            await replaceText(with: textWithSpace, originalLength: wordLength + 1)
            lastCorrectedLength = textWithSpace.count
            lastCorrectedText = textWithSpace  // Include space for accurate cycling
            lastCorrectionTime = Date()  // Enable cycling after auto-correction
        } else {
            logger.info("ℹ️ No correction needed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            // Still save the text for potential manual cycling
            let textWithSpace = text + " "
            lastCorrectedLength = textWithSpace.count
            lastCorrectedText = textWithSpace
            lastCorrectionTime = Date()  // Enable cycling even without auto-correction
        }
        
        logger.debug("🧹 Buffer processing complete")
    }
    
    private func handleHotkeyPress() async {
        // Freeze buffers for the entire duration of hotkey handling
        cyclingActive = true
        defer { cyclingActive = false }
        
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
        let timeSinceLastCorrection = Date().timeIntervalSince(lastCorrectionTime)
        let noNewTyping = buffer.isEmpty && timeSinceLastCorrection < 3.0
        
        // But first check if there's a fresh selection - it takes priority over cycling
        let freshSelection = await getSelectedTextFresh()
        let hasNewSelection = lastSelectionWasExplicit && !freshSelection.isEmpty && 
                              freshSelection.trimmingCharacters(in: .whitespacesAndNewlines) != lastCorrectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if hasCycling && noNewTyping && lastCorrectedLength > 0 && !hasNewSelection {
            let savedLength = lastCorrectedLength
            
            // Get the expected length from cycling state to verify consistency
            let expectedLength = await engine.getCurrentCyclingTextLength()
            
            // Safety check: if lengths don't match, something went wrong - reset cycling
            if expectedLength > 0 && abs(savedLength - expectedLength) > 2 {
                logger.warning("⚠️ Length mismatch: saved=\(savedLength), expected=\(expectedLength) - resetting cycling")
                await engine.resetCycling()
                lastCorrectedLength = 0
                lastCorrectedText = ""
                // Fall through to get fresh selection
            } else {
                logger.info("🔄 CYCLING: no new typing, using saved length (\(savedLength) chars)")
                DecisionLogger.shared.log("HOTKEY: CYCLING - savedLen=\(savedLength)")
                
                if let corrected = await engine.cycleCorrection(bundleId: bundleId) {
                    let hadSpace = await engine.cyclingHadTrailingSpace()
                    let finalCorrected = hadSpace ? corrected + " " : corrected
                    
                    logger.info("✅ CYCLING: → '\(corrected)' (deleting \(savedLength) chars, hadSpace=\(hadSpace))")
                    DecisionLogger.shared.log("HOTKEY: CYCLE RESULT: '\(corrected)' (delete \(savedLength))")
                    
                    await replaceText(with: finalCorrected, originalLength: savedLength)
                    
                    // Update to new length for next cycle
                    lastCorrectedLength = finalCorrected.count
                    lastCorrectedText = finalCorrected
                    lastCorrectionTime = Date()
                    buffer = ""
                    
                    if let targetLang = await engine.getLastCorrectionTargetLanguage() {
                        InputSourceManager.shared.switchTo(language: targetLang)
                        logger.info("🔄 Switched system layout to: \(targetLang.rawValue)")
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
                await typeOverSelection(with: finalText)
            } else {
                // No selection - use backspaces to delete buffer content
                DecisionLogger.shared.log("HOTKEY: Replacing \(rawText.count) chars with '\(finalText)' (\(finalText.count) chars)")
                await replaceText(with: finalText, originalLength: rawText.count)
            }
            
            lastCorrectedLength = finalText.count
            lastCorrectedText = finalText
            lastCorrectionTime = Date()
            buffer = ""  // Clear buffer after replacement
            DecisionLogger.shared.log("HOTKEY: Done. lastCorrectedLength=\(lastCorrectedLength)")
            
            // Switch system layout to match the corrected text language
            if let targetLang = await engine.getLastCorrectionTargetLanguage() {
                InputSourceManager.shared.switchTo(language: targetLang)
                logger.info("🔄 Switched system layout to: \(targetLang.rawValue)")
            }
        } else {
            logger.warning("❌ Manual correction failed for: \(DecisionLogger.tokenSummary(textToConvert), privacy: .public)")
            DecisionLogger.shared.log("HOTKEY: ERROR - correctLastWord returned nil!")
        }
    }
    
    /// Get FRESH selected text - prioritizes actual selection over buffer
    private var appsWithoutAXSelection: Set<String> = []
    private var lastSelectionWasExplicit: Bool = false
    
    private func getSelectedTextFresh() async -> String {
        lastSelectionWasExplicit = false
        let timeSinceLastKey = Date().timeIntervalSince(lastEventTime)
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // Fast path: use buffer if fresh (< 0.5s)
        if !buffer.isEmpty && timeSinceLastKey < 0.5 {
            lastSelectionWasExplicit = false
            return buffer
        }
        
        // Check if this app is known to not support AX selection
        if appsWithoutAXSelection.contains(bundleId) {
            // Go straight to clipboard fallback
            if let clipboardText = await getSelectedTextViaClipboard() {
                lastSelectionWasExplicit = true
                return clipboardText
            }
        } else {
            // Try AX selection first (instant, no delay)
            if let axText = getSelectedTextViaAccessibility(), !axText.isEmpty {
                lastSelectionWasExplicit = true
                return axText
            }
            
            // AX returned empty - try clipboard fallback
            if let clipboardText = await getSelectedTextViaClipboard(), !clipboardText.isEmpty {
                // Remember this app doesn't support AX selection
                appsWithoutAXSelection.insert(bundleId)
                logger.info("📋 App '\(bundleId)' added to clipboard fallback list")
                lastSelectionWasExplicit = true
                return clipboardText
            }
        }
        
        // Fallback to buffer even if stale
        if !buffer.isEmpty {
            lastSelectionWasExplicit = false
            return buffer
        }
        
        return ""
    }
    
    /// Get selected text via clipboard (Cmd+C) - fallback for apps without AX support
    private func getSelectedTextViaClipboard() async -> String? {
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
        
        if let proxy = currentProxy {
            cmdC_down.tapPostEvent(proxy)
            cmdC_up.tapPostEvent(proxy)
        } else {
            cmdC_down.post(tap: .cghidEventTap)
            cmdC_up.post(tap: .cghidEventTap)
        }
        
        // Wait for clipboard to update
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
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
    private func postKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let proxy = currentProxy,
              let keyDown = CGEvent(keyboardEventSource: syntheticEventSource, virtualKey: keyCode, keyDown: true),
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
    private func typeOverSelection(with newText: String) async {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        
        // For apps without AX support, use clipboard paste instead of typing
        if appsWithoutAXSelection.contains(bundleId) {
            await pasteText(newText)
        } else {
            typeUnicodeString(newText)
        }
    }
    
    /// Paste text via clipboard (Cmd+V) - for apps that don't accept CGEvent typing
    private func pasteText(_ text: String) async {
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
        
        if let proxy = currentProxy {
            cmdV_down.tapPostEvent(proxy)
            cmdV_up.tapPostEvent(proxy)
        } else {
            cmdV_down.post(tap: .cghidEventTap)
            cmdV_up.post(tap: .cghidEventTap)
        }
        
        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Restore original clipboard
        if let saved = savedContent {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }
    
    private func replaceText(with newText: String, originalLength: Int) async {
        // Send backspaces to delete original text
        for _ in 0..<originalLength {
            postKeyEvent(keyCode: 0x33, flags: [])
        }
        
        // Small delay for system to process deletions
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        
        typeUnicodeString(newText)
    }
    
    /// Type a string using CGEvent - posts "after" our tap so we don't see our own events
    private func typeUnicodeString(_ string: String) {
        guard let proxy = currentProxy else { return }
        
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
        
        let chunkSize = 20
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
