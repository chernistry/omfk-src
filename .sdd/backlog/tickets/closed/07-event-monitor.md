# Ticket: 07 EventMonitor with CGEventTap

Spec version: v1.0 / ADR-001, Component 3 (EventMonitor)

## Context
- Links to `.sdd/architect.md`: ADR-001 (CGEventTap), Component 3 (EventMonitor actor), Strategic Risk 3 (Performance)
- Links to `.sdd/project.md`: Definition of Done items 2, 5, 12 (Monitoring, correction, latency)
- Core component for keyboard event capture and correction

## Objective & Definition of Done
Implement EventMonitor actor with CGEventTap lifecycle, text buffer management, and correction triggering.

- [ ] `EventMonitor.swift` created as actor with CGEventTap setup
- [ ] `startMonitoring()` creates CGEventTap, adds to run loop, enables tap
- [ ] `stopMonitoring()` disables tap and cleans up
- [ ] `handleEvent(type:event:)` callback processes keyDown events
- [ ] Text buffer accumulates characters, triggers correction at word boundaries
- [ ] Timeout events (.tapDisabledByTimeout) handled with auto-restart
- [ ] Buffer cleared immediately after correction (privacy requirement)
- [ ] Integration with LanguageDetector, LayoutMapper, CorrectionEngine
- [ ] Actor isolation enforced for Swift 6 concurrency

## Steps
1. Create `OMFK/Engine/EventMonitor.swift`
2. Define `actor EventMonitor`
3. Add properties: `private var eventTap: CFMachPort?`, `private var textBuffer: String = ""`, `private var currentLayout: NLLanguage = .english`
4. Add dependencies: `private let detector = LanguageDetector()`, `private let mapper = LayoutMapper()`
5. Implement `func startMonitoring() async`:
   - Check permission via PermissionManager
   - Create event mask: `(1 << CGEventType.keyDown.rawValue)`
   - Call `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: eventCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())`
   - Create run loop source: `CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)`
   - Add to run loop: `CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)`
   - Enable tap: `CGEvent.tapEnable(tap: eventTap, enable: true)`
6. Implement `func stopMonitoring() async`:
   - Disable tap: `CGEvent.tapEnable(tap: eventTap!, enable: false)`
   - Clear buffer: `textBuffer = ""`
7. Implement `nonisolated func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>?`:
   - Handle timeout: if `type == .tapDisabledByTimeout`, re-enable tap and return event
   - Extract character from event: `event.keyboardGetUnicodeString()`
   - Append to buffer (ignore non-text keys)
   - Check word boundary (space, enter): if yes, trigger correction
   - Return event (or nil to cancel)
8. Implement `private func triggerCorrection() async`:
   - Detect language: `let (lang, conf) = detector.detectWithFallback(textBuffer)`
   - If confidence >0.6 and lang != currentLayout: convert text, post corrected events, clear buffer
9. Implement `private func postCorrectedText(_ text: String)`:
   - Delete original text (post backspace events)
   - Post corrected text (create CGEvent for each character)
10. Create callback function: `private func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?`

## Affected files/modules
- `OMFK/Engine/EventMonitor.swift` (new)

## Tests
- Manual test: Run app, type in wrong layout, verify correction
- Integration tests in ticket 13

## Risks & Edge Cases
- CGEventTap may fail to create (permission denied): handle gracefully
- Timeout events must be handled or tap stops working
- Buffer must be cleared after correction (privacy requirement)
- Non-text keys (arrows, modifiers) must be ignored
- Backspace must remove last character from buffer

## Dependencies
- Upstream tickets: 01 (project setup), 04 (LanguageDetector), 05 (LayoutMapper), 06 (PermissionManager)
- Downstream tickets: 12 (AppCoordinator integration), 13 (integration tests)