# Ticket: 08 AppCoordinator and App Entry Point

Spec version: v1.0 / Component 1 (OMFKApp), Component 2 (AppCoordinator)

## Context
- Links to `.sdd/architect.md`: Component 1 (OMFKApp), Component 2 (AppCoordinator)
- Links to `.sdd/project.md`: Definition of Done item 1 (Menu bar app launches)
- Coordinates all components and manages app lifecycle

## Objective & Definition of Done
Implement OMFKApp entry point and AppCoordinator to manage EventMonitor, SettingsStore, and app state.

- [ ] `OMFKApp.swift` created with @main and MenuBarExtra
- [ ] `AppCoordinator.swift` created as @MainActor ObservableObject
- [ ] AppCoordinator starts/stops EventMonitor
- [ ] AppCoordinator manages settings and history
- [ ] App launches and displays menu bar icon
- [ ] Clicking icon shows placeholder popover
- [ ] App terminates cleanly (stops monitoring, saves settings)

## Steps
1. Create `OMFK/OMFKApp.swift`
2. Define `@main struct OMFKApp: App`
3. Add `@StateObject private var coordinator = AppCoordinator()`
4. Implement `var body: some Scene` with `MenuBarExtra("O.M.F.K", systemImage: "keyboard") { Text("Placeholder") }`
5. Add `.environmentObject(coordinator)` to MenuBarExtra content
6. Create `OMFK/AppCoordinator.swift`
7. Define `@MainActor class AppCoordinator: ObservableObject`
8. Add properties: `@Published var isEnabled: Bool = true`, `@Published var history: [Correction] = []`, `private let eventMonitor = EventMonitor()`, `private let settingsStore = SettingsStore()`, `private let permissionManager = PermissionManager()`
9. Implement `init()`:
   - Load settings from SettingsStore
   - Initialize history
10. Implement `func start() async`:
   - Check permission via PermissionManager
   - If granted, start EventMonitor
   - If denied, show permission prompt
11. Implement `func stop() async`:
   - Stop EventMonitor
   - Save settings
12. Implement `func addCorrection(_ correction: Correction)`:
   - Insert at index 0
   - Limit to 20 entries
   - Save to SettingsStore
13. Add `onAppear` to MenuBarExtra to call `coordinator.start()`

## Affected files/modules
- `OMFK/OMFKApp.swift` (new)
- `OMFK/AppCoordinator.swift` (new)

## Tests
- Manual test: Run app, verify menu bar icon appears
- Manual test: Click icon, verify placeholder popover shows
- Manual test: Quit app, verify monitoring stops
- Unit tests for AppCoordinator in ticket 14

## Risks & Edge Cases
- App may launch without permission: show permission prompt immediately
- EventMonitor may fail to start: show error alert
- Settings may fail to load: use defaults

## Dependencies
- Upstream tickets: 01 (project setup), 03 (Models, SettingsStore), 06 (PermissionManager), 07 (EventMonitor)
- Downstream tickets: 10 (SettingsView), 11 (HistoryView), 12 (MenuBarContentView)