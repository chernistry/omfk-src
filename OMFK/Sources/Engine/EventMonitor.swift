import Foundation
import AppKit
import CoreGraphics
import os.log

@MainActor
final class EventMonitor {
    private let engine: CorrectionEngine
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer: String = ""
    private var lastEventTime: Date = .distantPast
    private let logger = Logger(subsystem: "com.chernistry.omfk", category: "EventMonitor")
    
    init(engine: CorrectionEngine) {
        self.engine = engine
    }
    
    func start() async {
        guard await checkAccessibility() else {
            logger.error("Accessibility permission denied")
            await requestAccessibility()
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
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
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        let now = Date()
        if now.timeIntervalSince(lastEventTime) > 2.0 {
            buffer = ""
        }
        lastEventTime = now
        
        if let chars = event.keyboardEventCharacters {
            buffer.append(chars)
            
            // Process on word boundaries
            if chars.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                Task { @MainActor in
                    await processBuffer()
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func processBuffer() async {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return }
        
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard await engine.shouldCorrect(for: bundleId) else { return }
        
        if let corrected = await engine.correctText(text, expectedLayout: nil) {
            await replaceText(with: corrected, originalLength: text.count)
        }
        
        buffer = ""
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
    
    private func checkAccessibility() async -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func requestAccessibility() async {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

extension CGEvent {
    var keyboardEventCharacters: String? {
        guard let source = CGEventCreateSourceFromEvent(self) else { return nil }
        let keyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        
        if UCKeyTranslate(
            unsafeBitCast(TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData), to: UnsafePointer<UCKeyboardLayout>.self),
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
