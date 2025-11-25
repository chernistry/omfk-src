# O.M.F.K Best Practices Guide (2025)
## 1. TL;DR
- **Swift 6 concurrency**: Use actors for event processing, async language detection; avoid blocking main thread (<50ms requirement)
- **CGEventTap over NSEvent**: Required for event modification/cancellation; handle timeout/disable events with auto-restart
- **NLLanguageRecognizer + NSSpellChecker**: Set languageHints to [.russian, .english, .hebrew]; validate words with NSSpellChecker.rangeOfMisspelledWord(); convert layout if word invalid in detected language
- **MenuBarExtra (SwiftUI)**: Replaces NSStatusItem custom views; simpler lifecycle, better Sequoia compatibility
- **Layout mapping tables**: Hardcode RU↔EN, HE↔EN character maps; O(1) lookup, no external deps
- **Permissions**: Request Accessibility + Input Monitoring explicitly; graceful degradation if denied
- **Security**: Clear typed text buffers immediately after correction; no persistent keyboard logs
- **Performance SLO**: <50ms detection+correction; <100MB memory; test with 1000+ corrections/hour
- **Testing**: Unit tests for layout maps + language detection (>90% accuracy); integration tests for RU↔EN, HE↔EN, mixed scenarios
- **2025 changes**: Swift 6 strict concurrency, MenuBarExtra stable, Carbon APIs deprecated, privacy declarations required
**Observability**: OSLog for structured logging, Instruments for profiling event latency  
**Security**: Local-only processing, no network, PII cleanup, sandboxed where possible  
**CI/CD**: Xcode Cloud or GitHub Actions, SwiftLint + SwiftFormat, XCTest coverage >80%  
**Cost**: $0 runtime (local app), ~$10/mo CI if using paid services
---
## 2. Landscape — What's New in 2025
### Swift & macOS
- **Swift 6** (stable): Strict concurrency checking, data isolation, Sendable protocol enforcement. Migration from Swift 5.10 requires auditing shared mutable state.
- **macOS Sequoia**: Privacy declarations in Info.plist required for Accessibility/Input Monitoring (`NSPrivacyAccessedAPITypes`). Stricter sandboxing for App Store distribution.
- **SwiftUI MenuBarExtra**: Mature API for menu bar apps (introduced macOS 13, stable in 14+). Replaces NSStatusItem with custom NSView (deprecated pattern).
- **NaturalLanguage framework**: No major API changes; still best for 10+ word inputs. Short-text detection requires custom heuristics.
### Deprecations & EOL
- **Carbon Event Manager**: Fully deprecated; use CGEventTap or modern hotkey libraries (e.g., KeyboardShortcuts package).
- **NSStatusItem custom views**: Discouraged; MenuBarExtra is preferred for SwiftUI apps.
- **Synchronous event handling on main thread**: Violates Swift 6 concurrency; use actors/async.
### Tooling Maturity
- **Testing**: XCTest mature; Swift Testing framework (preview) for async tests.
- **Observability**: OSLog with privacy-aware logging; Instruments for CGEventTap profiling.
- **Security**: Xcode 15+ includes dependency scanning; use `swift package audit` for vulnerabilities.
### Alternative Approaches
- **NSEvent global monitors**: Simpler API but can't modify/cancel events; unsuitable for text replacement.
- **Accessibility API (AXUIElement)**: Can read/modify text fields but requires per-app integration; not system-wide.
- **Input Method Kit**: Complex framework for custom input methods; overkill for layout correction.
### Red Flags & Traps
- **Copying old Carbon hotkey code**: Still prevalent in Stack Overflow answers; use modern alternatives (KeyboardShortcuts package or CGEventTap).
- **Ignoring CGEventTap timeout events**: Event tap disables after 1 second of no events; must re-enable or app stops working.
- **Blocking language detection**: NLLanguageRecognizer is fast but not instant; running on main thread causes input lag.
- **No confidence thresholds**: NLLanguageRecognizer returns low-confidence guesses for short text; filter results <0.6 confidence.
- **Storing full keyboard history**: Privacy risk and memory leak; clear buffers after correction.
---
## 3. Architecture Patterns
### Pattern A — Single-Actor Event Pipeline (MVP)
**When to use**: Initial implementation; <1000 corrections/hour; single-user workload.
**Steps**:
1. **EventMonitor actor**: Owns CGEventTap, processes keyDown events, accumulates text buffer.
2. **LanguageDetector**: Synchronous wrapper around NLLanguageRecognizer with character-set fallback.
3. **LayoutMapper**: Hardcoded RU↔EN, HE↔EN character maps; O(1) lookup.
4. **CorrectionEngine**: Decides when to correct (confidence threshold, buffer length), posts corrected events.
**Pros**: Simple, low latency for MVP, easy to debug.  
**Cons**: Single bottleneck; language detection blocks event processing; no caching.
**Code outline**:
```swift
@MainActor
class AppCoordinator: ObservableObject {
   let eventMonitor = EventMonitor()
   func start() async {
       await eventMonitor.startMonitoring()
   }
}
actor EventMonitor {
   private var eventTap: CFMachPort?
   private var textBuffer: String = ""
   private let detector = LanguageDetector()
   private let mapper = LayoutMapper()
   func startMonitoring() {
       let mask = (1 << CGEventType.keyDown.rawValue)
       eventTap = CGEvent.tapCreate(
           tap: .cgSessionEventTap,
           place: .headInsertEventTap,
           options: .defaultTap,
           eventsOfInterest: CGEventMask(mask),
           callback: eventCallback,
           userInfo: Unmanaged.passUnretained(self).toOpaque()
       )
   }
   func processEvent(_ event: CGEvent) -> CGEvent? {
       textBuffer.append(event.characters)
       if textBuffer.count >= 3 {
           let (lang, confidence) = detector.detect(textBuffer)
           if confidence > 0.6, lang != currentLayout {
               let corrected = mapper.convert(textBuffer, to: lang)
           }
       }
       return event
   }
}
```
**Optional later**: Add caching for repeated phrases, async language detection.
---
### Pattern B — Multi-Actor Pipeline with Caching (Scale-up)
**When to use**: >1000 corrections/hour; need <20ms latency; multiple concurrent operations (UI updates, logging, history).
**Migration from A**:
1. Split EventMonitor into EventCapture (CGEventTap only) and CorrectionPipeline (language detection + mapping).
2. Use async/await for language detection; cache results for repeated 3-5 word phrases.
3. Add HistoryActor for undo/redo; SettingsActor for per-app rules.
**Steps**:
1. **EventCapture actor**: Minimal CGEventTap handling; sends events to pipeline via AsyncStream.
2. **CorrectionPipeline actor**: Async language detection, caching, correction logic.
3. **HistoryActor**: Stores last 50 corrections with timestamps; provides undo.
4. **SettingsActor**: Per-app rules, exclusion list, sensitivity thresholds.
**Pros**: Non-blocking, scalable, better separation of concerns.  
**Cons**: More complex, requires Swift 6 concurrency understanding, harder to debug race conditions.
**Code outline**:
```swift
actor EventCapture {
   private var eventStream: AsyncStream<CGEvent>.Continuation?
   func startMonitoring() -> AsyncStream<CGEvent> {
       AsyncStream { continuation in
           self.eventStream = continuation
       }
   }
}
actor CorrectionPipeline {
   private let detector = LanguageDetector()
   private let mapper = LayoutMapper()
   private var cache: [String: (lang: String, confidence: Double)] = [:]
   func process(_ events: AsyncStream<CGEvent>) async {
       for await event in events {
           let text = extractText(event)
           let result = cache[text] ?? await detector.detectAsync(text)
           cache[text] = result
       }
   }
}
```
---
## 3.1 Conflicting Practices & Alternatives
### Conflict 1: CGEventTap vs NSEvent Global Monitors
**Options**:
- **A**: CGEventTap (tap: .cgSessionEventTap, options: .defaultTap)
- **B**: NSEvent.addGlobalMonitorForEvents(matching: .keyDown)
**When each is preferable**:
- **A**: Required for O.M.F.K (must modify/cancel events for text replacement). Requires Accessibility permission.
- **B**: Simpler for read-only monitoring (e.g., analytics, logging). Cannot modify events.
**Trade-offs**:
- **A**: PerfGain=High (can cancel wrong events), SecRisk=Medium (requires Accessibility), DevTime=High (complex setup), Maintainability=Medium (must handle timeouts).
- **B**: PerfGain=Low (can't modify), SecRisk=Low (no Accessibility), DevTime=Low, Maintainability=High.
**Project constraint**: Definition of Done requires "automatic text correction replaces wrong-layout text" → **Must use CGEventTap (A)**.
---
### Conflict 2: Synchronous vs Async Language Detection
**Options**:
- **A**: Synchronous NLLanguageRecognizer.processString() in event callback
- **B**: Async detection with Task/actor isolation
**When each is preferable**:
- **A**: MVP with <100 corrections/hour; acceptable if detection <10ms.
- **B**: Production with <50ms total latency requirement; allows UI updates during detection.
**Trade-offs**:
- **A**: PerfGain=Medium (simple, low overhead), DevTime=Low, Maintainability=High. Risk: blocks event processing if detection >10ms.
- **B**: PerfGain=High (non-blocking), DevTime=Medium (Swift 6 concurrency), Maintainability=Medium (async debugging).
**Project constraint**: "<50ms detection + correction" + "avoid blocking main thread" → **Use async (B) for production, sync (A) acceptable for MVP**.
---
### Conflict 3: Carbon Hotkeys vs Modern Alternatives
**Options**:
- **A**: Carbon Event Manager (InstallEventHandler, RegisterEventHotKey)
- **B**: KeyboardShortcuts Swift package (github.com/sindresorhus/KeyboardShortcuts)
- **C**: CGEventTap with modifier flag checking
**When each is preferable**:
- **A**: Legacy code; deprecated in 2025.
- **B**: User-configurable hotkeys with UI; actively maintained.
- **C**: Full control; no external deps; more complex.
**Trade-offs**:
- **A**: Deprecated, not Swift 6 compatible, hard to maintain.
- **B**: DX=High, Maintainability=High, Cost=Low (free package). Adds dependency.
- **C**: DevTime=High, Maintainability=Medium, no deps.
**Recommendation**: **Use B (KeyboardShortcuts)** for user-facing hotkeys; **C (CGEventTap)** for internal event handling.
---
## 4. Priority 1 — CGEventTap Setup & Permissions
### Why
Critical path for system-wide keyboard monitoring. Without CGEventTap, app cannot intercept/modify events. Mitigates risk: "CGEventTap permission denial (High)".
### Scope
**In**: CGEventTap creation, run loop integration, Accessibility permission request, timeout/disable handling, graceful degradation.  
**Out**: NSEvent monitors, Carbon APIs, Input Method Kit.
### Decisions
1. **Use .cgSessionEventTap**: Monitors current user session; requires Accessibility permission.
2. **Handle timeout events**: CGEventTap disables after 1 second of inactivity; re-enable in callback.
3. **Request permissions early**: Show system dialog on first launch; provide fallback UI if denied.
4. **Graceful degradation**: If permission denied, show menu bar icon with "Enable Accessibility" prompt; disable correction.
**Alternatives rejected**:
- `.cgAnnotatedSessionEventTap`: Requires Input Monitoring permission; unnecessary for this use case.
- NSEvent global monitors: Cannot modify events.
### Implementation Outline
**Step 1**: Check Accessibility permission
```swift
func checkAccessibilityPermission() -> Bool {
   let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
   return AXIsProcessTrustedWithOptions(options as CFDictionary)
}
```
**Step 2**: Create CGEventTap
```swift
actor EventMonitor {
   private var eventTap: CFMachPort?
   func startMonitoring() {
       guard checkAccessibilityPermission() else {
           return
       }
       let mask = (1 << CGEventType.keyDown.rawValue)
       eventTap = CGEvent.tapCreate(
           tap: .cgSessionEventTap,
           place: .headInsertEventTap,
           options: .defaultTap,
           eventsOfInterest: CGEventMask(mask),
           callback: { proxy, type, event, refcon in
               guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
               let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
               return monitor.handleEvent(type: type, event: event)
           },
           userInfo: Unmanaged.passUnretained(self).toOpaque()
       )
       guard let eventTap = eventTap else {
           return
       }
       let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
       CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
       CGEvent.tapEnable(tap: eventTap, enable: true)
   }
   nonisolated func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
       if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
           CGEvent.tapEnable(tap: eventTap!, enable: true)
           return Unmanaged.passUnretained(event)
       }
       return Unmanaged.passUnretained(event)
   }
}
```
**Step 3**: Add privacy declarations (Info.plist)
```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
   <dict>
       <key>NSPrivacyAccessedAPIType</key>
       <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
       <key>NSPrivacyAccessedAPITypeReasons</key>
       <array>
           <string>35F9.1</string>
       </array>
   </dict>
</array>
```
**Step 4**: Handle permission denial
```swift
@MainActor
class PermissionManager: ObservableObject {
   @Published var hasAccessibility = false
   func requestPermission() {
       hasAccessibility = checkAccessibilityPermission()
       if !hasAccessibility {
       }
   }
}
```
**Step 5**: Test permission flow
- Launch app without permission → system dialog appears
- Deny permission → app shows fallback UI
- Grant permission → app starts monitoring
- Revoke permission while running → app detects and shows prompt
### Guardrails & SLOs
- **Latency**: Event callback <5ms (measured with Instruments)
- **Memory**: EventMonitor actor <10MB
- **Reliability**: Auto-restart after timeout within 100ms
### Failure Modes & Recovery
| Failure | Detection | Remediation | Rollback |
|---------|-----------|-------------|----------|
| Permission denied | `AXIsProcessTrustedWithOptions` returns false | Show UI prompt with "Open System Settings" | Disable correction, show menu bar icon |
| CGEventTap creation fails | `CGEvent.tapCreate` returns nil | Log error, retry after 5s (max 3 attempts) | Disable correction |
| Timeout event | `type == .tapDisabledByTimeout` | Re-enable tap immediately | None (automatic) |
| Run loop not running | Events not received after 1s | Check run loop, restart tap | Restart app |
---
## 5. Priority 2 — Language Detection with NLLanguageRecognizer
### Why
Core functionality for identifying RU/EN/HE text. Mitigates risk: "Language detection accuracy for short text (High)".
### Scope
**In**: NLLanguageRecognizer with languageHints, confidence thresholds, character-set fallback for 1-2 word inputs, caching.  
**Out**: Server-based ML models, custom neural networks, full NLP pipelines.
### Decisions
1. **Set languageHints**: `[.russian: 0.33, .english: 0.33, .hebrew: 0.34]` to constrain detection to target languages.
2. **Confidence threshold**: Reject results <0.6; use character-set fallback for short text.
3. **NSSpellChecker validation**: Check if detected text is valid word in detected language; if not, try converting layout and re-check.
4. **Character-set fallback**: If text <3 words, check Unicode ranges (Cyrillic U+0400-04FF, Hebrew U+0590-05FF, Latin U+0000-007F).
5. **Cache results**: Store last 100 detected phrases (3-10 words) with LRU eviction.
**Alternatives rejected**:
- No hints: NLLanguageRecognizer may guess wrong for similar scripts (e.g., Serbian vs Russian).
- Server-based detection: Adds latency, privacy risk, cost.
### Implementation Outline
**Step 1**: Wrap NLLanguageRecognizer
```swift
struct LanguageDetector {
   func detect(_ text: String) -> (language: NLLanguage?, confidence: Double) {
       let recognizer = NLLanguageRecognizer()
       recognizer.languageHints = [.russian: 0.33, .english: 0.33, .hebrew: 0.34]
       recognizer.processString(text)
       guard let dominant = recognizer.dominantLanguage else {
           return (nil, 0.0)
       }
       let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
       let confidence = hypotheses[dominant] ?? 0.0
       return (dominant, confidence)
   }
}
```
**Step 2**: Add character-set fallback
```swift
extension LanguageDetector {
   func detectWithFallback(_ text: String) -> (language: NLLanguage?, confidence: Double) {
       let (lang, conf) = detect(text)
       if conf < 0.6 || text.split(separator: " ").count < 3 {
           if text.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
               return (.russian, 0.8)
           } else if text.unicodeScalars.contains(where: { (0x0590...0x05FF).contains($0.value) }) {
               return (.hebrew, 0.8)
           } else if text.unicodeScalars.allSatisfy({ (0x0000...0x007F).contains($0.value) }) {
               return (.english, 0.7)
           }
       }
       return (lang, conf)
   }
   
   func isValidWord(_ word: String, language: NLLanguage) -> Bool {
       let checker = NSSpellChecker.shared
       let range = NSRange(location: 0, length: word.utf16.count)
       let misspelled = checker.rangeOfMisspelledWord(
           in: word,
           range: range,
           startingAt: 0,
           wrap: false,
           language: language.rawValue
       )
       return misspelled.location == NSNotFound
   }
}
```
**Step 3**: Add caching
```swift
actor LanguageCache {
   private var cache: [String: (NLLanguage?, Double)] = [:]
   private var accessOrder: [String] = []
   private let maxSize = 100
   func get(_ text: String) -> (NLLanguage?, Double)? {
       cache[text]
   }
   func set(_ text: String, result: (NLLanguage?, Double)) {
       if cache.count >= maxSize {
           let oldest = accessOrder.removeFirst()
           cache.removeValue(forKey: oldest)
       }
       cache[text] = result
       accessOrder.append(text)
   }
}
```
**Step 4**: Async detection
```swift
actor LanguageDetectionService {
   private let detector = LanguageDetector()
   private let cache = LanguageCache()
   func detectAsync(_ text: String) async -> (NLLanguage?, Double) {
       if let cached = await cache.get(text) {
           return cached
       }
       let result = detector.detectWithFallback(text)
       await cache.set(text, result: result)
       return result
   }
}
```
**Step 5**: Test with known samples
```swift
func testLanguageDetection() {
   let detector = LanguageDetector()
   let ru = detector.detectWithFallback("Привет мир")
   XCTAssertEqual(ru.language, .russian)
   XCTAssertGreaterThan(ru.confidence, 0.8)
   let he = detector.detectWithFallback("שלום עולם")
   XCTAssertEqual(he.language, .hebrew)
   XCTAssertGreaterThan(he.confidence, 0.8)
   let en = detector.detectWithFallback("Hello world")
   XCTAssertEqual(en.language, .english)
   XCTAssertGreaterThan(en.confidence, 0.8)
   let short = detector.detectWithFallback("Привет")
   XCTAssertEqual(short.language, .russian)
}
```
### Guardrails & SLOs
- **Accuracy**: >90% for 3+ word inputs (measured with test corpus)
- **Latency**: <10ms per detection (async, off main thread)
- **Cache hit rate**: >70% for repeated phrases
### Failure Modes & Recovery
| Failure | Detection | Remediation | Rollback |
|---------|-----------|-------------|----------|
| Low confidence (<0.6) | Check confidence score | Use character-set fallback | Skip correction |
| NLLanguageRecognizer returns nil | Check dominantLanguage | Use character-set fallback | Skip correction |
| Wrong language detected | User reports via UI | Add to training corpus, adjust hints | Manual undo |
| Cache memory leak | Monitor cache size | Enforce LRU eviction | Clear cache |
---
## 6. Priority 3 — Menu Bar UI with SwiftUI
### Why
User-facing interface for settings, history, status. Mitigates risk: "Non-intrusive UX" requirement.
### Scope
**In**: MenuBarExtra with SwiftUI, status icon, popover with settings/history, hotkey configuration UI.  
**Out**: Custom NSStatusItem views, separate window-based UI, Dock icon.
### Decisions
1. **Use MenuBarExtra**: SwiftUI-native, simpler than NSStatusItem, better Sequoia compatibility.
2. **Status icon**: SF Symbol "keyboard" with badge for correction count.
3. **Popover content**: Tabs for Settings, History, About.
4. **Settings**: Toggle auto-correction, hotkey recorder, per-app rules list, sensitivity slider.
5. **History**: List of last 20 corrections with undo button.
**Alternatives rejected**:
- NSStatusItem with custom NSView: Deprecated pattern, harder to maintain.
- Separate window: Less discoverable, not menu bar app pattern.
### Implementation Outline
**Step 1**: Create MenuBarExtra
```swift
@main
struct OMFKApp: App {
   @StateObject private var appState = AppState()
   var body: some Scene {
       MenuBarExtra("O.M.F.K", systemImage: "keyboard") {
           MenuBarContentView()
               .environmentObject(appState)
       }
   }
}
```
**Step 2**: MenuBarContentView with tabs
```swift
struct MenuBarContentView: View {
   @EnvironmentObject var appState: AppState
   @State private var selectedTab = 0
   var body: some View {
       VStack(spacing: 0) {
           Picker("", selection: $selectedTab) {
               Text("Settings").tag(0)
               Text("History").tag(1)
               Text("About").tag(2)
           }
           .pickerStyle(.segmented)
           .padding()
           TabView(selection: $selectedTab) {
               SettingsView().tag(0)
               HistoryView().tag(1)
               AboutView().tag(2)
           }
           .frame(width: 400, height: 500)
       }
   }
}
```
**Step 3**: SettingsView
```swift
struct SettingsView: View {
   @EnvironmentObject var appState: AppState
   var body: some View {
       Form {
           Section("Auto-Correction") {
               Toggle("Enable", isOn: $appState.isEnabled)
               Slider(value: $appState.sensitivity, in: 0...1) {
                   Text("Sensitivity")
               }
           }
           Section("Hotkeys") {
               HotkeyRecorder("Manual Correction", hotkey: $appState.manualCorrectionHotkey)
               HotkeyRecorder("Toggle Auto-Correction", hotkey: $appState.toggleHotkey)
           }
           Section("Per-App Rules") {
               List(appState.excludedApps) { app in
                   Text(app.name)
               }
               Button("Add App...") {
               }
           }
       }
       .padding()
   }
}
```
**Step 4**: HistoryView
```swift
struct HistoryView: View {
   @EnvironmentObject var appState: AppState
   var body: some View {
       List(appState.history) { correction in
           HStack {
               VStack(alignment: .leading) {
                   Text(correction.original)
                       .strikethrough()
                   Text(correction.corrected)
                       .foregroundColor(.green)
               }
               Spacer()
               Button("Undo") {
                   appState.undo(correction)
               }
           }
       }
   }
}
```
**Step 5**: Test UI
- Launch app → menu bar icon appears
- Click icon → popover opens with tabs
- Toggle auto-correction → state updates, event monitoring pauses
- Add excluded app → app appears in list
- View history → last 20 corrections shown
- Click undo → correction reverted
### Guardrails & SLOs
- **UI responsiveness**: <16ms frame time (60fps)
- **Memory**: UI <20MB
- **Accessibility**: VoiceOver support for all controls
### Failure Modes & Recovery
| Failure | Detection | Remediation | Rollback |
|---------|-----------|-------------|----------|
| MenuBarExtra not visible | Check NSStatusBar | Restart app | Show alert |
| Popover doesn't open | Click event not received | Check event handling | Restart app |
| Settings not persisted | UserDefaults read fails | Use in-memory defaults | Show warning |
| History list empty | No corrections recorded | Check event pipeline | None |
---
## 7. Testing Strategy
### Unit Tests
**Scope**: Layout mapping, language detection, character-set fallback, confidence thresholds.
**Frameworks**: XCTest, Swift Testing (preview).
**Patterns**:
```swift
final class LayoutMapperTests: XCTestCase {
   func testRussianToEnglish() {
       let mapper = LayoutMapper()
       let input = "Ghbdtn vbh" // "Привет мир" in wrong layout
       let expected = "Привет мир"
       XCTAssertEqual(mapper.convert(input, from: .russian, to: .english), expected)
   }
   func testHebrewToEnglish() {
       let mapper = LayoutMapper()
       let input = "akuo okvg" // "שלום עולם" in wrong layout
       let expected = "שלום עולם"
       XCTAssertEqual(mapper.convert(input, from: .hebrew, to: .english), expected)
   }
}
final class LanguageDetectionTests: XCTestCase {
   func testRussianDetection() {
       let detector = LanguageDetector()
       let (lang, conf) = detector.detectWithFallback("Привет мир как дела")
       XCTAssertEqual(lang, .russian)
       XCTAssertGreaterThan(conf, 0.9)
   }
   func testShortTextFallback() {
       let detector = LanguageDetector()
       let (lang, conf) = detector.detectWithFallback("Привет")
       XCTAssertEqual(lang, .russian)
       XCTAssertGreaterThan(conf, 0.7) // Lower threshold for fallback
   }
}
```
**Coverage target**: >80% for /core, /engine modules.
---
### Integration Tests
**Scope**: CGEventTap event flow, text replacement simulation, end-to-end correction scenarios.
**Patterns**:
```swift
final class CorrectionIntegrationTests: XCTestCase {
   func testRussianToEnglishCorrection() async {
       let pipeline = CorrectionPipeline()
       let events = simulateTyping("Ghbdtn vbh") // Wrong layout
       for event in events {
           await pipeline.process(event)
       }
       let corrected = await pipeline.getLastCorrection()
       XCTAssertEqual(corrected?.text, "Привет мир")
   }
   func testHebrewRTLCorrection() async {
       let pipeline = CorrectionPipeline()
       let events = simulateTyping("akuo okvg") // Wrong layout
       for event in events {
           await pipeline.process(event)
       }
       let corrected = await pipeline.getLastCorrection()
       XCTAssertEqual(corrected?.text, "שלום עולם")
       XCTAssertTrue(corrected?.isRTL ?? false)
   }
}
```
---
### Performance Tests
**Scope**: <50ms latency, <100MB memory, 1000+ corrections/hour.
**Patterns**:
```swift
final class PerformanceTests: XCTestCase {
   func testDetectionLatency() {
       let detector = LanguageDetector()
       measure {
           _ = detector.detectWithFallback("Привет мир как дела")
       }
   }
   func testCorrectionThroughput() async {
       let pipeline = CorrectionPipeline()
       let events = (0..<1000).map { _ in simulateTyping("Ghbdtn") }.flatMap { $0 }
       let start = Date()
       for event in events {
           await pipeline.process(event)
       }
       let duration = Date().timeIntervalSince(start)
       XCTAssertLessThan(duration, 50.0) // <50ms per correction
   }
}
```
---
### Security Tests
**Scope**: Permission handling, PII cleanup, no persistent keyboard logs.
**Patterns**:
```swift
final class SecurityTests: XCTestCase {
   func testTextBufferCleared() async {
       let monitor = EventMonitor()
       await monitor.processEvent(simulateTyping("sensitive"))
       let buffer = await monitor.getTextBuffer()
       XCTAssertTrue(buffer.isEmpty, "Buffer should be cleared after correction")
   }
   func testNoKeyboardLogging() {
       let logPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
       let logFiles = try? FileManager.default.contentsOfDirectory(at: logPath, includingPropertiesForKeys: nil)
       XCTAssertNil(logFiles?.first(where: