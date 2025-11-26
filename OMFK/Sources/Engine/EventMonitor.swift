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
    private let logger = Logger(subsystem: "com.chernistry.omfk", category: "EventMonitor")
    private let settings: SettingsManager
    
    init(engine: CorrectionEngine) {
        self.engine = engine
        self.settings = SettingsManager.shared
    }
    
    func start() async {
        guard checkAccessibility() else {
            logger.error("Accessibility permission denied")
            requestAccessibility()
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
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
            logger.error("Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        logger.info("Event monitor started")
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
                logger.info("Event tap re-enabled after timeout/disable")
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Check for hotkey (left Alt by default, keyCode 58)
        if settings.hotkeyEnabled && keyCode == Int64(settings.hotkeyKeyCode) {
            logger.info("Hotkey pressed, triggering manual correction")
            Task { @MainActor in
                await handleHotkeyPress()
            }
            return Unmanaged.passUnretained(event)
        }
        
        let now = Date()
        if now.timeIntervalSince(lastEventTime) > 2.0 {
            if !buffer.isEmpty {
                logger.debug("Buffer cleared due to timeout: '\(self.buffer, privacy: .public)'")
            }
            buffer = ""
        }
        lastEventTime = now
        
        if let chars = event.keyboardEventCharacters {
            buffer.append(chars)
            logger.debug("Key pressed: '\(chars, privacy: .public)', buffer: '\(self.buffer, privacy: .public)'")
            
            // Process on word boundaries
            if chars.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                logger.info("Word boundary detected, processing buffer")
                Task { @MainActor in
                    await processBuffer()
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func processBuffer() async {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else {
            logger.debug("Buffer too short, skipping: '\(text, privacy: .public)'")
            return
        }
        
        logger.info("Processing buffer: '\(text, privacy: .public)'")
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        logger.info("Frontmost app: \(bundleId ?? "unknown", privacy: .public)")
        
        guard await engine.shouldCorrect(for: bundleId) else {
            logger.info("Correction disabled for this app")
            return
        }

        // If auto-switch is enabled, treat the preferred language as the expected layout.
        // This makes the engine more decisive about converting words into the user's primary layout.
        let expectedLayout: Language? = settings.autoSwitchLayout ? settings.preferredLanguage : nil

        if let corrected = await engine.correctText(text, expectedLayout: expectedLayout) {
            logger.info("Correction found: '\(text, privacy: .public)' -> '\(corrected, privacy: .public)'")
            await replaceText(with: corrected, originalLength: text.count)
        } else {
            logger.info("No correction needed")
        }
        
        buffer = ""
    }
    
    private func handleHotkeyPress() async {
        // Prefer current selection if any, otherwise fall back to last word
        let text = await getSelectedOrLastWord()
        guard !text.isEmpty else {
            logger.warning("No text to correct")
            return
        }
        
        logger.info("Manual correction for: '\(text, privacy: .public)'")
        
        if let corrected = await engine.correctLastWord(text) {
            logger.info("Manual correction: '\(text, privacy: .public)' -> '\(corrected, privacy: .public)'")
            await replaceText(with: corrected, originalLength: text.count)
        } else {
            logger.warning("Manual correction failed")
        }
    }
    
    private func getSelectedOrLastWord() async -> String {
        // 1. Try current selection via Cmd+C
        let pb = NSPasteboard.general
        pb.clearContents()

        let cmdC = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true)
        cmdC?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        if let selected = pb.string(forType: .string), !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.info("Using selected text for hotkey correction")
            return selected.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Fall back to buffer if available
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        
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
        return pb.string(forType: .string) ?? ""
    }
    
    private func replaceText(with newText: String, originalLength: Int) async {
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
        let keyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        
        guard let layoutData = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        
        let layout = unsafeBitCast(layoutData, to: UnsafePointer<UCKeyboardLayout>.self)
        
        if UCKeyTranslate(
            layout,
            UInt16(getIntegerValueField(.keyboardEventKeycode)),
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            nil,
            4,
            &length,
            &chars
        ) == noErr {
            return String(utf16CodeUnits: chars, count: length)
        }
        return nil
    }
}
