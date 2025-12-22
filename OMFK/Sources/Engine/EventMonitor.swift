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
    private var lastCorrectedLength: Int = 0  // Track length of last corrected text for cycling
    private let logger = Logger.events
    private let settings: SettingsManager
    
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
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
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
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.warning("⚠️ Event tap was disabled (timeout/user input), re-enabling...")
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        logger.debug("🔵 KEY EVENT: keyCode=\(keyCode), flags=\(flags.rawValue)")
        
        // Check for hotkey (left Alt by default, keyCode 58)
        if settings.hotkeyEnabled && keyCode == Int64(settings.hotkeyKeyCode) {
            logger.info("🔥 HOTKEY DETECTED (keyCode \(keyCode)) - triggering manual correction")
            Task { @MainActor in
                await handleHotkeyPress()
            }
            return Unmanaged.passUnretained(event)
        }
        
        let now = Date()
        let timeSinceLastEvent = now.timeIntervalSince(lastEventTime)
        if timeSinceLastEvent > 2.0 {
            if !buffer.isEmpty {
                logger.info("⏱️ Buffer timeout (\(String(format: "%.1f", timeSinceLastEvent))s) - clearing buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            }
            buffer = ""
        }
        lastEventTime = now
        
        if let chars = event.keyboardEventCharacters {
            buffer.append(chars)
            logger.info("⌨️ Typed: \(DecisionLogger.tokenSummary(chars), privacy: .public) | Buffer: \(DecisionLogger.tokenSummary(self.buffer), privacy: .public)")
            
            // Reset cycling state on new input
            Task { @MainActor in
                await engine.resetCycling()
                lastCorrectedLength = 0
            }
            
            // Process on word boundaries
            if chars.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                logger.info("📍 Word boundary detected (space/newline) - processing buffer")
                Task { @MainActor in
                    await processBuffer()
                }
            }
        } else {
            logger.debug("⚠️ No characters extracted from keyCode \(keyCode)")
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func processBuffer() async {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else {
            logger.debug("⏭️ Buffer too short (\(text.count) chars), skipping: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return
        }
        
        // Calculate actual length in buffer (including trailing space that triggered processing)
        let bufferLength = buffer.count
        
        logger.info("🔍 Processing buffer: \(DecisionLogger.tokenSummary(text), privacy: .public) (buffer len: \(bufferLength))")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        logger.info("📱 Frontmost app: \(bundleId ?? "unknown", privacy: .public)")
        
        guard await engine.shouldCorrect(for: bundleId) else {
            logger.info("🚫 Correction disabled for app: \(bundleId ?? "unknown", privacy: .public)")
            return
        }
        
        logger.info("✅ Correction enabled for this app - proceeding...")

        // If auto-switch is enabled, treat the preferred language as the expected layout.
        // This makes the engine more decisive about converting words into the user's primary layout.
        let expectedLayout: Language? = settings.autoSwitchLayout ? settings.preferredLanguage : nil
        if let expected = expectedLayout {
            logger.info("🎯 Auto-switch enabled, expected layout: \(expected.rawValue, privacy: .public)")
        }

        if let corrected = await engine.correctText(text, expectedLayout: expectedLayout) {
            logger.info("✅ CORRECTION APPLIED: \(DecisionLogger.tokenSummary(text), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            // Delete only the word (not the trailing space), replace with corrected text
            // The space that triggered processing is already in the field after the cursor
            // We need to go back past the space, delete the word, type corrected, then move forward
            
            // Simpler approach: delete bufferLength chars (including space), type corrected + space
            await replaceText(with: corrected + " ", originalLength: bufferLength)
            // Store the corrected text length (with space) for potential cycling
            lastCorrectedLength = corrected.count + 1
        } else {
            logger.info("ℹ️ No correction needed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        }
        
        buffer = ""
        logger.debug("🧹 Buffer cleared")
    }
    
    private func handleHotkeyPress() async {
        logger.info("🔥 === HOTKEY PRESSED - Manual Correction Mode ===")
        
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
            }
            return
        }
        
        // No recent correction - get selected text or last word
        let text = await getSelectedOrLastWord()
        guard !text.isEmpty else {
            logger.warning("⚠️ No text to correct (selection empty, buffer empty)")
            return
        }
        
        logger.info("📝 Text for manual correction: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        if let corrected = await engine.correctLastWord(text, bundleId: bundleId) {
            logger.info("✅ MANUAL CORRECTION: \(DecisionLogger.tokenSummary(text), privacy: .public) → \(DecisionLogger.tokenSummary(corrected), privacy: .public)")
            await replaceText(with: corrected, originalLength: text.count)
            lastCorrectedLength = corrected.count
        } else {
            logger.warning("❌ Manual correction failed for: \(DecisionLogger.tokenSummary(text), privacy: .public)")
        }
    }
    
    private func getSelectedOrLastWord() async -> String {
        logger.debug("🔍 Attempting to get selected text or last word...")
        
        let pb = NSPasteboard.general
        let originalContents = pb.string(forType: .string)
        pb.clearContents()

        // 1. Try to copy current selection via Cmd+C
        postKeyEvent(keyCode: 0x08, flags: .maskCommand) // C key
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        if let selected = pb.string(forType: .string), 
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           selected != originalContents {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("✅ Using selected text: \(DecisionLogger.tokenSummary(trimmed), privacy: .public)")
            return trimmed
        }

        // 2. Fall back to buffer if available
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            logger.info("✅ Using buffer text: \(DecisionLogger.tokenSummary(text), privacy: .public)")
            return text
        }
        
        logger.debug("⚠️ No selection or buffer, trying word selection...")
        
        // 3. Select word backward using Option+Shift+Left (selects one word)
        pb.clearContents()
        postKeyEvent(keyCode: 0x7B, flags: [.maskAlternate, .maskShift]) // Left arrow
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Copy the selection
        postKeyEvent(keyCode: 0x08, flags: .maskCommand) // C key
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
        
        // Delete original text using backspace
        for _ in 0..<originalLength {
            postKeyEvent(keyCode: 0x33, flags: []) // Backspace key
        }
        
        // Small delay to ensure deletions are processed
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        
        // Type new text using Unicode string method (more reliable for non-ASCII)
        typeUnicodeString(newText)
        
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
