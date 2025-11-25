# O.M.F.K Architecture Specification
## Hard Constraints
### Domain-Specific Prohibitions
- **No persistent keyboard logging**: Typed text must be cleared immediately after correction (privacy requirement)
- **No network calls**: All processing must be local (security + latency requirement)
- **No external ML models**: Use only Apple's NaturalLanguage framework (sandboxing + offline requirement)
- **No Carbon APIs**: Deprecated in 2025; use CGEventTap and modern Swift alternatives
### Compliance Requirements
- **macOS Privacy**: Info.plist must declare `NSPrivacyAccessedAPITypes` for Accessibility/Input Monitoring
- **Accessibility**: VoiceOver support for all UI controls
- **Sandboxing**: App Store distribution requires sandboxing where possible; request minimal permissions
### Technology Restrictions
- **Swift 6-ready**: Code must compile with strict concurrency checking enabled
- **macOS Sonoma/Sequoia only**: Target deployment 14.0+
- **No external dependencies for core**: Layout mapping and language detection must be self-contained (KeyboardShortcuts package allowed for UI)
---
## Go/No-Go Preconditions
### Blocking Prerequisites
- [ ] Xcode 15+ installed with Swift 5.10+ toolchain
- [ ] macOS Sonoma/Sequoia development machine (for testing MenuBarExtra, privacy declarations)
- [ ] Accessibility permission granted on development machine (for CGEventTap testing)
- [ ] Test corpus prepared: 50+ sample phrases per language (RU/EN/HE) for language detection validation
### Required Resources
- **No API keys/credentials**: All processing is local
- **Test data**: Create `Tests/Resources/LanguageCorpus/` with:
 - `russian.txt`: 50 phrases (3-10 words each)
 - `english.txt`: 50 phrases
 - `hebrew.txt`: 50 phrases (including RTL test cases)
 - `mixed.txt`: 20 phrases with language switches
### Environment Setup
- **Bundle identifier**: `com.chernistry.omfk` (must be configured in Xcode project)
- **Signing**: Development signing certificate (for local testing); distribution certificate (for release)
- **Entitlements**: `com.apple.security.automation.apple-events` (for Accessibility)
### Dependency Readiness
- **KeyboardShortcuts package**: github.com/sindresorhus/KeyboardShortcuts (v2.0+, Swift 6 compatible)
- **No external services**: All functionality is local
---
## Goals & Non-Goals
### Goals
1. **System-wide keyboard monitoring** (DoD: "Global keyboard event monitoring active with proper permissions")
  - CGEventTap captures all keyDown events
  - Accessibility permission requested and handled gracefully
2. **Accurate language detection for RU/EN/HE** (DoD: "Language detection working for RU/EN/HE on 3-10 word chunks", ">90% accuracy")
  - NLLanguageRecognizer with languageHints
  - NSSpellChecker for word validation (dictionary lookup)
  - Character-set fallback for short text (<3 words)
  - Confidence threshold >0.6
3. **Real-time layout correction** (DoD: "Automatic text correction replaces wrong-layout text in real-time", "<50ms detection + correction")
  - Hardcoded RU↔EN, HE↔EN character mapping tables
  - Async language detection (non-blocking)
  - Text replacement via CGEvent posting
4. **Menu bar app with settings/history** (DoD: "Menu bar app launches and displays status icon", "Settings UI", "History view displays last 20+ corrections")
  - MenuBarExtra with SwiftUI
  - Settings: toggle auto-correction, hotkeys, per-app rules
  - History: last 20 corrections with undo
5. **Production-grade quality** (DoD: "Crash-free operation for 1+ hour", "<100MB memory", "Build succeeds with zero warnings")
  - Unit tests >80% coverage
  - Integration tests for RU↔EN, HE↔EN scenarios
  - Performance tests for <50ms latency
### Non-Goals
1. **Support for languages beyond RU/EN/HE**: Out of scope for MVP
2. **Cloud-based ML models**: Local-only processing
3. **Custom input method**: Not building an IME; only correcting wrong-layout text
4. **App Store distribution in MVP**: Focus on direct distribution first; sandboxing optional
5. **Windows/Linux support**: macOS-only
### Definition of Done Mapping
All 19 DoD items from `.sdd/project.md` are covered by Goals 1-5 above. Critical path:
- Goal 1 → DoD items 1-2 (menu bar, monitoring, permissions)
- Goal 2 → DoD items 3, 13 (language detection, accuracy)
- Goal 3 → DoD items 4-7, 11-12 (correction, hotkeys, latency)
- Goal 4 → DoD items 8-10 (UI, history, per-app rules)
- Goal 5 → DoD items 14-19 (testing, stability, build quality)
---
## Metric Profile & Strategic Risk Map
### Metric Profile (Relative Weights)
- **PerfGain**: 0.25 (High) — <50ms latency is hard requirement
- **SecRisk**: 0.20 (Medium-High) — Handles keyboard input but local-only
- **Maintainability**: 0.20 (High) — Modular architecture, long-term support
- **DevTime**: 0.15 (Medium) — Complex event handling, Swift 6 concurrency
- **DX**: 0.10 (Medium) — Swift 6 learning curve, CGEventTap complexity
- **Cost**: 0.05 (Low) — Local app, no cloud costs
- **Scalability**: 0.05 (Low) — Single-user workload
**Rationale**: Performance and security are top priorities due to real-time keyboard monitoring. Maintainability is critical for long-term evolution. Cost and scalability are low since this is a local utility app.
### Strategic Risks
1. **CGEventTap permission denial** (High)
  - Impact: App cannot function without Accessibility permission
  - Mitigation: Clear onboarding, graceful degradation, fallback UI
2. **Language detection accuracy for short text** (High)
  - Impact: Wrong corrections frustrate users
  - Mitigation: Character-set fallback, confidence thresholds, user feedback loop
3. **Performance degradation under load** (Medium)
  - Impact: Input lag >50ms violates DoD
  - Mitigation: Async detection, caching, performance tests
4. **Hebrew RTL rendering bugs** (Medium)
  - Impact: Incorrect text display/correction
  - Mitigation: Dedicated RTL tests, Unicode bidirectional algorithm compliance
5. **Memory leaks from event retention** (Medium)
  - Impact: Memory usage >100MB violates DoD
  - Mitigation: Clear text buffers immediately, LRU cache eviction, memory profiling
6. **Swift 6 concurrency migration issues** (Medium)
  - Impact: Data races, crashes
  - Mitigation: Strict concurrency checking, actor isolation, thorough testing
7. **Dependency on KeyboardShortcuts package** (Low)
  - Impact: Package abandonment or breaking changes
  - Mitigation: Pin version, consider vendoring or fallback to CGEventTap hotkeys
### Architecture Influence
- **High SecRisk + PerfGain**: Use actors for isolation, async for non-blocking, clear buffers immediately
- **High Maintainability**: Modular structure (/core, /engine, /ui), clear interfaces, comprehensive tests
- **Medium DevTime**: Start with MVP (Pattern A), defer optimizations (Pattern B) until proven necessary
---
## Alternatives
### A) Single-Actor Event Pipeline (MVP)
**When to use**: Initial implementation; <1000 corrections/hour; acceptable 10-20ms latency.
**Pros**:
- Simple architecture, easy to debug
- Low overhead, minimal actor coordination
- Fast to implement (2-3 weeks)
**Cons**:
- Language detection blocks event processing
- No caching for repeated phrases
- Single bottleneck for all operations
**Constraints**: Must handle CGEventTap timeout events; must clear text buffers after correction.
---
### B) Multi-Actor Pipeline with Caching (Scale-up)
**When to use**: >1000 corrections/hour; need <20ms latency; multiple concurrent operations.
**Pros**:
- Non-blocking language detection
- Cache hit rate >70% for repeated phrases
- Better separation of concerns (EventCapture, CorrectionPipeline, HistoryActor, SettingsActor)
**Cons**:
- More complex, harder to debug
- Requires Swift 6 concurrency expertise
- Longer implementation time (4-5 weeks)
**Constraints**: Must maintain actor isolation; must handle AsyncStream backpressure.
---
### C) Hybrid Approach (Deferred)
**When to use**: If MVP performance is insufficient but full multi-actor is overkill.
**Pros**:
- Async language detection only (simplest optimization)
- Keep single-actor for event handling
- Incremental migration path
**Cons**:
- Still has some blocking (layout mapping, event posting)
- Partial benefits of full async architecture
**Constraints**: Not recommended; either stay with A or fully migrate to B.
---
## Research Conflicts & Resolutions
### Conflict 1: CGEventTap vs NSEvent Global Monitors
**Options**: A) CGEventTap, B) NSEvent.addGlobalMonitorForEvents
**Chosen**: **A (CGEventTap)**
**Why**: DoD requires "automatic text correction replaces wrong-layout text" → must modify/cancel events. NSEvent monitors are read-only.
**Trade-offs**: Higher DevTime (complex setup), Medium SecRisk (requires Accessibility), but High PerfGain (can cancel wrong events).
**ADR**: [ADR-001]
**Implications**:
- Components: EventMonitor actor must handle CGEventTap lifecycle, timeout events
- Data model: No impact
- Quality: Must test permission denial, timeout recovery
---
### Conflict 2: Synchronous vs Async Language Detection
**Options**: A) Synchronous NLLanguageRecognizer in event callback, B) Async detection with actors
**Chosen**: **B (Async) for production, A (Sync) acceptable for MVP**
**Why**: DoD requires "<50ms detection + correction" + "avoid blocking main thread". Async allows UI updates during detection.
**Trade-offs**: Medium DevTime (Swift 6 concurrency), but High PerfGain (non-blocking), High Maintainability (better separation).
**ADR**: [ADR-002]
**Implications**:
- Components: LanguageDetectionService actor, AsyncStream for event pipeline
- Data model: Cache for detected phrases (LRU, max 100 entries)
- Quality: Performance tests must validate <50ms end-to-end latency
---
### Conflict 3: Carbon Hotkeys vs Modern Alternatives
**Options**: A) Carbon Event Manager, B) KeyboardShortcuts package, C) CGEventTap with modifier flags
**Chosen**: **B (KeyboardShortcuts) for user-facing hotkeys, C (CGEventTap) for internal event handling**
**Why**: Carbon is deprecated (2025). KeyboardShortcuts provides user-configurable UI with High DX, High Maintainability. CGEventTap for internal use avoids external dependency for core functionality.
**Trade-offs**: Low Cost (free package), Medium DX (adds dependency), but High Maintainability (actively maintained).
**ADR**: [ADR-003]
**Implications**:
- Components: HotkeyManager uses KeyboardShortcuts for settings UI; EventMonitor uses CGEventTap for manual correction trigger
- Data model: UserDefaults stores hotkey configurations
- Quality: Test hotkey conflicts, system-wide registration
---
## MVP Recommendation
**Choice**: **Alternative A (Single-Actor Event Pipeline)**
**Why**:
- Satisfies all DoD requirements with simplest architecture
- DevTime 2-3 weeks vs 4-5 weeks for Alternative B
- Performance acceptable for MVP (<1000 corrections/hour, 10-20ms latency)
- Easier to debug and validate correctness
- Clear migration path to Alternative B if needed
**Scale-up Path**:
1. **Trigger**: Performance tests show >50ms latency or user reports lag
2. **Migration**: Split EventMonitor into EventCapture + CorrectionPipeline actors
3. **Add caching**: LanguageCache actor with LRU eviction
4. **Add history/settings actors**: HistoryActor, SettingsActor for concurrent access
5. **Estimated effort**: 1-2 weeks (incremental refactoring)
**Rollback Plan**:
- If Alternative B introduces data races or complexity: revert to Alternative A
- Keep Alternative A implementation in git branch `mvp-single-actor`
- Rollback criteria: >3 concurrency-related crashes in 1 week, or >2 weeks debugging actor issues
---
## Architecture Overview
### Component Diagram (Text)
```
┌─────────────────────────────────────────────────────────────┐
│                         OMFKApp                             │
│                    (SwiftUI @main)                          │
└────────────────────────┬────────────────────────────────────┘
                        │
                        ├─────────────────────────────────────┐
                        │                                     │
               ┌────────▼────────┐                  ┌─────────▼────────┐
               │  AppCoordinator │                  │  MenuBarExtra    │
               │   (@MainActor)  │                  │    (SwiftUI)     │
               └────────┬────────┘                  └─────────┬────────┘
                        │                                     │
                        │                           ┌─────────┴────────┐
                        │                           │                  │
               ┌────────▼────────┐         ┌────────▼────────┐ ┌──────▼──────┐
               │  EventMonitor   │         │  SettingsView   │ │ HistoryView │
               │     (actor)     │         │   (SwiftUI)     │ │  (SwiftUI)  │
               └────────┬────────┘         └─────────────────┘ └─────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
┌────────▼────────┐ ┌───▼──────────┐ ┌──▼─────────────┐
│ LanguageDetector│ │ LayoutMapper │ │ CorrectionEngine│
│    (struct)     │ │   (struct)   │ │    (struct)     │
└─────────────────┘ └──────────────┘ └─────────────────┘
        │
        │
┌────────▼────────┐
│NLLanguageRecognizer│
│  (Apple framework) │
└────────────────────┘
External:
- CGEventTap (Core Graphics)
- UserDefaults (settings persistence)
- KeyboardShortcuts (hotkey UI)
```
### Data Schema (High-Level)
**In-Memory (Actors)**
```swift
actor EventMonitor {
   private var textBuffer: String = ""  // Cleared after correction
   private var eventTap: CFMachPort?
   private var currentLayout: NLLanguage = .english
}
actor LanguageCache {
   private var cache: [String: (NLLanguage?, Double)] = [:]  // Max 100 entries
   private var accessOrder: [String] = []  // LRU tracking
}
```
**Persistent (UserDefaults)**
```swift
struct AppSettings: Codable {
   var isEnabled: Bool = true
   var sensitivity: Double = 0.7  // Confidence threshold
   var excludedApps: [String] = []  // Bundle identifiers
   var manualCorrectionHotkey: KeyboardShortcut?
   var toggleHotkey: KeyboardShortcut?
}
struct CorrectionHistory: Codable {
   var corrections: [Correction] = []  // Max 20 entries
}
struct Correction: Codable, Identifiable {
   let id: UUID
   let timestamp: Date
   let original: String
   let corrected: String
   let language: String  // "ru", "en", "he"
}
```
**Layout Mapping Tables (Hardcoded)**
```swift
struct LayoutMapper {
   private let ruToEn: [Character: Character] = [
       "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t",
       "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p",
   ]
   private let heToEn: [Character: Character] = [
       "ש": "a", "ד": "s", "ג": "d", "כ": "f", "ע": "g",
   ]
}
```
### External Integrations
- **CGEventTap**: System-wide keyboard event capture (Core Graphics framework)
- **NLLanguageRecognizer**: Language detection (NaturalLanguage framework)
- **UserDefaults**: Settings persistence (Foundation framework)
- **KeyboardShortcuts**: Hotkey configuration UI (Swift package, github.com/sindresorhus/KeyboardShortcuts)
- **No network calls**: All processing is local
---
## Discovery
**Note**: No existing repository provided. Starting from scratch.
### Proposed Project Structure
```
OMFK/
├── OMFK/
│   ├── OMFKApp.swift                    # @main entry point, MenuBarExtra
│   ├── AppCoordinator.swift             # @MainActor coordinator
│   ├── Core/
│   │   ├── LanguageDetector.swift       # NLLanguageRecognizer wrapper
│   │   ├── LayoutMapper.swift           # RU↔EN, HE↔EN character maps
│   │   └── Models.swift                 # Correction, AppSettings
│   ├── Engine/
│   │   ├── EventMonitor.swift           # CGEventTap actor
│   │   ├── CorrectionEngine.swift       # Correction logic
│   │   ├── PermissionManager.swift      # Accessibility permission handling
│   │   └── HotkeyManager.swift          # KeyboardShortcuts integration
│   ├── UI/
│   │   ├── MenuBarContentView.swift     # Tab container
│   │   ├── SettingsView.swift           # Settings UI
│   │   ├── HistoryView.swift            # Correction history
│   │   └── AboutView.swift              # About/help
│   ├── Settings/
│   │   └── SettingsStore.swift          # UserDefaults wrapper
│   └── Logging/
│       └── Logger.swift                 # OSLog wrapper
├── Tests/
│   ├── CoreTests/
│   │   ├── LanguageDetectorTests.swift
│   │   └── LayoutMapperTests.swift
│   ├── EngineTests/
│   │   └── CorrectionEngineTests.swift
│   ├── IntegrationTests/
│   │   └── CorrectionIntegrationTests.swift
│   ├── PerformanceTests/
│   │   └── LatencyTests.swift
│   └── Resources/
│       └── LanguageCorpus/
│           ├── russian.txt
│           ├── english.txt
│           ├── hebrew.txt
│           └── mixed.txt
├── .swiftlint.yml
├── .swiftformat
└── Package.swift                        # Swift Package Manager
```
### Key Files & Integration Points
- **OMFKApp.swift**: Entry point; creates AppCoordinator and MenuBarExtra
- **EventMonitor.swift**: CGEventTap setup; integrates with LanguageDetector, LayoutMapper, CorrectionEngine
- **LanguageDetector.swift**: NLLanguageRecognizer wrapper; character-set fallback
- **LayoutMapper.swift**: Hardcoded character mapping tables
- **SettingsStore.swift**: UserDefaults persistence; observed by SwiftUI views
### Extension Points (Minimal Change Surface)
- **Adding new language**: Update LayoutMapper with new character map; add to languageHints
- **Custom heuristics**: Extend LanguageDetector.detectWithFallback()
- **Per-app rules**: Extend SettingsStore with app-specific thresholds
---
## MCDM for Major Choices
### Criteria Weights (SMART Method)
- **PerfGain**: 0.25 (Critical for <50ms requirement)
- **SecRisk**: 0.20 (Handles keyboard input)
- **DevTime**: 0.15 (Time to MVP)
- **Maintainability**: 0.20 (Long-term support)
- **Cost**: 0.05 (Local app, minimal)
- **Scalability**: 0.05 (Single-user)
- **DX**: 0.10 (Developer experience)
### Decision Matrix: Architecture Pattern
| Alternative | PerfGain | SecRisk | DevTime | Maintainability | Cost | Scalability | DX | Weighted Score |
|-------------|----------|---------|---------|-----------------|------|-------------|----|----|
| A (Single-Actor) | 7 | 8 | 9 | 7 | 9 | 6 | 8 | **7.65** |
| B (Multi-Actor) | 9 | 8 | 5 | 8 | 9 | 9 | 6 | 7.50 |
| C (Hybrid) | 8 | 8 | 7 | 6 | 9 | 7 | 7 | 7.35 |
**Scoring (1-9 scale)**:
- **PerfGain**: A=7 (10-20ms), B=9 (<10ms), C=8 (15ms)
- **SecRisk**: All=8 (same security model)
- **DevTime**: A=9 (2-3 weeks), B=5 (4-5 weeks), C=7 (3-4 weeks)
- **Maintainability**: A=7 (simple), B=8 (modular), C=6 (mixed patterns)
- **Cost**: All=9 (local app)
- **Scalability**: A=6 (limited), B=9 (high), C=7 (medium)
- **DX**: A=8 (easy to debug), B=6 (complex), C=7 (moderate)
**Recommendation**: **Alternative A (Single-Actor)** — Highest weighted score (7.65). Best balance of DevTime, DX, and sufficient PerfGain for MVP. Clear migration path to B if needed.
**Trade-offs**:
- Sacrifice 2-3ms latency for 2 weeks faster delivery
- Simpler debugging and validation
- Lower risk of concurrency bugs
**Rollback Plan**: Keep A implementation in `mvp-single-actor` branch; revert if B introduces issues.
---
## Key Decisions (ADR-Style)
### [ADR-001] Use CGEventTap over NSEvent Global Monitors
**Context**: Need system-wide keyboard monitoring with ability to modify/cancel events.
**Decision**: Use `CGEvent.tapCreate(tap: .cgSessionEventTap, ...)` for event capture.
**Alternatives**:
- NSEvent.addGlobalMonitorForEvents: Read-only, cannot modify events
- Accessibility API (AXUIElement): Per-app integration, not system-wide
**Rationale**: DoD requires "automatic text correction replaces wrong-layout text". CGEventTap is the only API that allows event modification/cancellation system-wide.
**Consequences**:
- Requires Accessibility permission (must handle denial gracefully)
- Must handle timeout/disable events (re-enable tap)
- Higher complexity than NSEvent monitors
**Status**: Accepted
---
### [ADR-002] Async Language Detection for Production
**Context**: NLLanguageRecognizer takes 5-10ms; blocking main thread causes input lag.
**Decision**: Use async/await with actor isolation for language detection in production. Synchronous acceptable for MVP.
**Alternatives**:
- Synchronous detection in event callback: Simpler but blocks event processing
- Background thread with GCD: Manual synchronization, error-prone
**Rationale**: DoD requires "<50ms detection + correction" and "avoid blocking main thread". Async allows UI updates and better responsiveness.
**Consequences**:
- Requires Swift 6 concurrency (actors, async/await)
- More complex debugging (async stack traces)
- Better separation of concerns (LanguageDetectionService actor)
**Status**: Accepted (deferred to post-MVP if performance is sufficient)
---
### [ADR-003] KeyboardShortcuts Package for Hotkey UI
**Context**: Need user-configurable hotkeys with UI for settings.
**Decision**: Use KeyboardShortcuts Swift package (github.com/sindresorhus/KeyboardShortcuts) for hotkey configuration UI. Use CGEventTap for internal hotkey detection.
**Alternatives**:
- Carbon Event Manager: Deprecated, not Swift 6 compatible
- Custom CGEventTap implementation: High DevTime, reinventing wheel
**Rationale**: KeyboardShortcuts provides mature UI with High DX and Maintainability. Actively maintained, Swift 6 compatible.
**Consequences**:
- External dependency (mitigated by pinning version)
- Must integrate with CGEventTap for actual hotkey detection
- Simplifies settings UI implementation
**Status**: Accepted
---
### [ADR-004] MenuBarExtra over NSStatusItem
**Context**: Need menu bar app UI for macOS Sonoma/Sequoia.
**Decision**: Use SwiftUI `MenuBarExtra` for menu bar integration.
**Alternatives**:
- NSStatusItem with custom NSView: Deprecated pattern, harder to maintain
- Separate window-based UI: Not menu bar app pattern
**Rationale**: MenuBarExtra is SwiftUI-native, simpler lifecycle, better Sequoia compatibility. Recommended by Apple for new apps.
**Consequences**:
- Requires macOS 13+ (acceptable for Sonoma/Sequoia target)
- Simpler SwiftUI integration
- Better future compatibility
**Status**: Accepted
---
### [ADR-005] Hardcoded Layout Mapping Tables
**Context**: Need RU↔EN, HE↔EN character conversion for layout correction.
**Decision**: Hardcode character mapping tables as `[Character: Character]` dictionaries in LayoutMapper struct.
**Alternatives**:
- Load from external file: Adds complexity, no benefit for fixed mappings
- Generate dynamically: Unnecessary overhead
**Rationale**: Layout mappings are static and well-defined. Hardcoding provides O(1) lookup, no external dependencies, and compile-time validation.
**Consequences**:
- Adding new language requires code change (acceptable for MVP)
- Fast lookup (<1ms)
- No runtime errors from missing files
**Status**: Accepted
---
### [ADR-006] Character-Set Fallback for Short Text
**Context**: NLLanguageRecognizer unreliable for <3 word inputs.
**Decision**: If confidence <0.6 or text <3 words, use Unicode range detection (Cyrillic U+0400-04FF, Hebrew U+0590-05FF, Latin U+0000-007F).
**Alternatives**:
- Skip correction for short text: Poor UX
- Lower confidence threshold: Increases false positives
**Rationale**: Character sets are unambiguous for RU/HE/EN. Provides reliable fallback for short inputs.
**Consequences**:
- Higher accuracy for short text
- Simple implementation (Unicode range checks)
- May misidentify mixed-script text (acceptable trade-off)
**Status**: Accepted
---
### [ADR-007] LRU Cache for Language Detection
**Context**: Repeated phrases (e.g., "Hello", "Привет") detected multiple times.
**Decision**: Cache last 100 detected phrases with LRU eviction in LanguageCache actor.
**Alternatives**:
- No caching: Redundant detection overhead
- Unlimited cache: Memory leak risk
**Rationale**: Cache hit rate >70% expected for common phrases. LRU eviction prevents unbounded growth.
**Consequences**:
- Reduced detection latency for repeated phrases
- Memory overhead <1MB (100 entries × ~10KB each)
- Must implement LRU eviction logic
**Status**: Accepted (deferred to Alternative B)
---
## Components
### 1. OMFKApp (SwiftUI @main)
**Responsibility**: App entry point, lifecycle management, MenuBarExtra setup.
**Interfaces**:
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
**Dependencies**: AppState (@MainActor), MenuBarContentView.
**Typical Flows**:
1. App launch → create AppState → start EventMonitor
2. User clicks menu bar icon → show MenuBarContentView
3. App termination → stop EventMonitor, save settings
**Edge Cases**:
1. Launch without Accessibility permission → show permission prompt
2. EventMonitor fails to start → show error alert
3. Settings load fails → use defaults
---
### 2. AppCoordinator (@MainActor)
**Responsibility**: Coordinate EventMonitor, SettingsStore, HistoryStore. Manage app state.
**Interfaces**:
```swift
@MainActor
class AppCoordinator: ObservableObject {
   @Published var isEnabled: Bool = true
   @Published var history: [Correction] = []
   private let eventMonitor = EventMonitor()
   private let settingsStore = SettingsStore()
   func start() async {
       await eventMonitor.startMonitoring()
   }
   func stop() async {
       await eventMonitor.stopMonitoring()
   }
   func addCorrection(_ correction: Correction) {
       history.insert(correction, at: 0)
       if history.count > 20 {
           history.removeLast()
       }
   }
}
```
**Dependencies**: EventMonitor (actor), SettingsStore, HistoryStore.
**Typical Flows**:
1. Start monitoring → check permissions → create CGEventTap
2. Correction made → add to history → notify UI
3. Settings changed → update EventMonitor configuration
**Edge Cases**:
1. Permission denied → disable monitoring, show prompt
2. EventMonitor crashes → restart with exponential backoff
3. History full (>20) → evict oldest entry
---
### 3. EventMonitor (actor)
**Responsibility**: CGEventTap lifecycle, event capture, text buffer management, correction triggering.
**Interfaces**:
```swift
actor EventMonitor {
   private var eventTap: CFMachPort?
   private var textBuffer: String = ""
   private let detector = LanguageDetector()
   private let mapper = LayoutMapper()
   private let engine = CorrectionEngine()
   func startMonitoring() async {
       guard checkAccessibilityPermission() else { return }
   }
   func stopMonitoring() async {
       CGEvent.tapEnable(tap: eventTap!, enable: false)
   }
   nonisolated func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
   }
}
```
**Dependencies**: LanguageDetector, LayoutMapper, CorrectionEngine, PermissionManager.
**Typical Flows**:
1. keyDown event → extract character → append to buffer
2. Buffer ≥3 words → detect language → check confidence
3. Confidence >0.6 + wrong layout → convert text → post corrected events → clear buffer
**Edge Cases**:
1. Timeout event (.tapDisabledByTimeout) → re-enable tap immediately
2. Permission revoked while running → stop monitoring, notify coordinator
3. Buffer >100 characters → force correction or clear (prevent memory leak)
4. Non-text keys (arrows, modifiers) → ignore, don't append to buffer
5. Backspace → remove last character from buffer
6. Enter/Space → trigger correction if buffer