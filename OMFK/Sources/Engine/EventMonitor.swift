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
                logger.info("⏱️ Buffer timeout (\(String(format: "%.1f", timeSinceLastEvent))s) - clearing buffer: '\(self.buffer, privacy: .public)'")
            }
            buffer = ""
        }
        lastEventTime = now
        
        if let chars = event.keyboardEventCharacters {
            buffer.append(chars)
            logger.info("⌨️ Typed: '\(chars, privacy: .public)' | Buffer: '\(self.buffer, privacy: .public)' (len=\(self.buffer.count))")
            
            // Reset cycling state on new input
            Task { @MainActor in
                await engine.resetCycling()
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
            logger.debug("⏭️ Buffer too short (\(text.count) chars), skipping: '\(text, privacy: .public)'")
            return
        }
        
        logger.info("🔍 Processing buffer: '\(text, privacy: .public)' (len=\(text.count))")
        
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
            logger.info("✅ CORRECTION APPLIED: '\(text, privacy: .public)' → '\(corrected, privacy: .public)'")
            await replaceText(with: corrected, originalLength: text.count)
        } else {
            logger.info("ℹ️ No correction needed for: '\(text, privacy: .public)'")
        }
        
        buffer = ""
        logger.debug("🧹 Buffer cleared")
    }
    
    private func handleHotkeyPress() async {
        logger.info("🔥 === HOTKEY PRESSED - Manual Correction Mode ===")
        
        // Prefer current selection if any, otherwise fall back to last word
        let text = await getSelectedOrLastWord()
        guard !text.isEmpty else {
            logger.warning("⚠️ No text to correct (selection empty, buffer empty)")
            return
        }
        
        logger.info("📝 Text for manual correction: '\(text, privacy: .public)' (len=\(text.count))")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        if let corrected = await engine.correctLastWord(text, bundleId: bundleId) {
            logger.info("✅ MANUAL CORRECTION: '\(text, privacy: .public)' → '\(corrected, privacy: .public)'")
            await replaceText(with: corrected, originalLength: text.count)
        } else {
            logger.warning("❌ Manual correction failed for: '\(text, privacy: .public)'")
        }
    }
    
    private func getSelectedOrLastWord() async -> String {
        logger.debug("🔍 Attempting to get selected text or last word...")
        
        // 1. Try current selection via Cmd+C
        let pb = NSPasteboard.general
        pb.clearContents()

        let cmdC = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true)
        cmdC?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        if let selected = pb.string(forType: .string), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.info("✅ Using selected text: '\(trimmed, privacy: .public)'")
            return trimmed
        }

        // 2. Fall back to buffer if available
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            logger.info("✅ Using buffer text: '\(text, privacy: .public)'")
            return text
        }
        
        logger.debug("⚠️ No selection or buffer, trying word selection...")
        
        // 3. Fallback: select word backward and copy
        // Cmd+Shift+Left to select word
        let cmdShiftLeft = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: true)
        cmdShiftLeft?.flags = [.maskCommand, .maskShift]
        cmdShiftLeft?.post(tap: .cghidEventTap)
        
        // Cmd+C to copy
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let cmdC2 = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true)
        cmdC2?.flags = .maskCommand
        cmdC2?.post(tap: .cghidEventTap)
        
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let result = pb.string(forType: .string) ?? ""
        if !result.isEmpty {
            logger.info("✅ Selected word backward: '\(result, privacy: .public)'")
        } else {
            logger.warning("❌ Failed to get any text")
        }
        return result
    }
    
    private func replaceText(with newText: String, originalLength: Int) async {
        logger.info("🔄 Replacing text: deleting \(originalLength) chars, typing '\(newText, privacy: .public)'")
        
        // Delete original text
        for _ in 0..<originalLength {
            let deleteEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: true) // Delete key
            deleteEvent?.post(tap: .cghidEventTap)
        }
        
        // Type new text
        for char in newText {
            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UniChar(char.unicodeScalars.first!.value)])
                event.post(tap: .cghidEventTap)
            }
        }
        
        logger.info("✅ Text replacement complete")
    }
    
    private func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
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
