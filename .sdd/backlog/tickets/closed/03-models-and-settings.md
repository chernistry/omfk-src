# Ticket: 03 Core Models and Settings Store

Spec version: v1.0 / Data Schema, Component 2

## Context
- Links to `.sdd/architect.md`: Data Schema (Persistent UserDefaults), Component 2 (AppCoordinator)
- Links to `.sdd/project.md`: Definition of Done items 8-10 (Settings UI, History, Per-app rules)
- Foundation for settings persistence and history management

## Objective & Definition of Done
Implement core data models (Correction, AppSettings) and SettingsStore for UserDefaults persistence.

- [ ] `Models.swift` created with Correction, AppSettings structs (Codable, Identifiable)
- [ ] `SettingsStore.swift` created with UserDefaults wrapper
- [ ] Settings load/save with proper defaults (isEnabled=true, sensitivity=0.7)
- [ ] History limited to 20 entries with automatic eviction
- [ ] Unit tests for SettingsStore (save, load, defaults)
- [ ] All code compiles with Swift 6 strict concurrency

## Steps
1. Create `OMFK/Core/Models.swift`
2. Define `Correction` struct: `id: UUID`, `timestamp: Date`, `original: String`, `corrected: String`, `language: String`
3. Define `AppSettings` struct: `isEnabled: Bool`, `sensitivity: Double`, `excludedApps: [String]`, `manualCorrectionHotkey: String?`, `toggleHotkey: String?`
4. Make both structs conform to `Codable`, `Identifiable`, `Sendable`
5. Create `OMFK/Settings/SettingsStore.swift` with `@MainActor class SettingsStore: ObservableObject`
6. Implement `@Published var settings: AppSettings`, `@Published var history: [Correction]`
7. Implement `loadSettings()`, `saveSettings()`, `addCorrection(_:)` with 20-entry limit
8. Add UserDefaults keys as constants (e.g., `private let settingsKey = "omfk.settings"`)
9. Create `Tests/CoreTests/SettingsStoreTests.swift` with tests for load/save/defaults

## Affected files/modules
- `OMFK/Core/Models.swift` (new)
- `OMFK/Settings/SettingsStore.swift` (new)
- `Tests/CoreTests/SettingsStoreTests.swift` (new)

## Tests
- Run unit tests: `xcodebuild test -scheme OMFK -destination 'platform=macOS'`
- Test cases:
  - `testDefaultSettings()`: Load settings with no saved data, verify defaults
  - `testSaveAndLoadSettings()`: Save settings, reload, verify equality
  - `testHistoryLimit()`: Add 25 corrections, verify only last 20 retained
  - `testCodableRoundtrip()`: Encode/decode Correction and AppSettings

## Risks & Edge Cases
- UserDefaults may fail to save (disk full, permissions): handle gracefully with error logging
- History eviction must be FIFO (oldest first)
- Sendable conformance may require `@unchecked Sendable` for some types

## Dependencies
- Upstream tickets: 01 (project setup)
- Downstream tickets: 05 (AppCoordinator), 10 (SettingsView), 11 (HistoryView)