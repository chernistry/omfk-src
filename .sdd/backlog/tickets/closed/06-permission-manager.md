# Ticket: 06 Permission Manager for Accessibility

Spec version: v1.0 / ADR-001, Component PermissionManager

## Context
- Links to `.sdd/architect.md`: ADR-001 (CGEventTap requires Accessibility), Strategic Risk 1 (Permission denial)
- Links to `.sdd/project.md`: Definition of Done item 15 (Properly requests and handles permissions)
- Critical for CGEventTap functionality

## Objective & Definition of Done
Implement PermissionManager to check and request Accessibility permission with graceful degradation.

- [ ] `PermissionManager.swift` created with permission checking logic
- [ ] `checkAccessibilityPermission()` method using `AXIsProcessTrustedWithOptions`
- [ ] `requestPermission()` method showing system dialog with prompt
- [ ] `@Published var hasAccessibility: Bool` for UI observation
- [ ] Graceful degradation: returns false if denied, doesn't crash
- [ ] Unit tests for permission state handling
- [ ] @MainActor isolation for UI updates

## Steps
1. Create `OMFK/Engine/PermissionManager.swift`
2. Define `@MainActor class PermissionManager: ObservableObject`
3. Add `@Published var hasAccessibility: Bool = false`
4. Implement `func checkAccessibilityPermission() -> Bool`:
   - Call `AXIsProcessTrustedWithOptions(nil)`
   - Return result
5. Implement `func requestPermission()`:
   - Create options dict: `[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]`
   - Call `AXIsProcessTrustedWithOptions(options as CFDictionary)`
   - Update `hasAccessibility` property
6. Implement `func openSystemPreferences()`:
   - Open System Settings to Privacy & Security > Accessibility
   - Use `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
7. Add polling mechanism: `func startPolling()` to check permission every 2 seconds (for when user grants in System Settings)
8. Create `Tests/EngineTests/PermissionManagerTests.swift` with test cases

## Affected files/modules
- `OMFK/Engine/PermissionManager.swift` (new)
- `Tests/EngineTests/PermissionManagerTests.swift` (new)

## Tests
- Run unit tests: `xcodebuild test -scheme OMFK -destination 'platform=macOS'`
- Test cases:
  - `testCheckPermissionWhenGranted()`: Mock granted permission, verify returns true
  - `testCheckPermissionWhenDenied()`: Mock denied permission, verify returns false
  - `testRequestPermissionShowsDialog()`: Verify system dialog appears (manual test)
  - `testPollingUpdatesState()`: Grant permission externally, verify polling detects change
- Manual test: Run app without permission, verify system dialog appears

## Risks & Edge Cases
- Permission may be revoked while app is running: polling mechanism detects this
- System dialog may be dismissed without granting: app must handle gracefully
- `AXIsProcessTrustedWithOptions` may return false positives on some macOS versions: test on Sonoma/Sequoia

## Dependencies
- Upstream tickets: 01 (project setup)
- Downstream tickets: 07 (EventMonitor), 12 (AppCoordinator integration)