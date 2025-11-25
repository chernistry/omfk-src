# Ticket: 01 Project Setup and Configuration

Spec version: v1.0 / ADR-004, ADR-005

## Context
- Links to `.sdd/architect.md` sections: Go/No-Go Preconditions, Proposed Project Structure
- Links to `.sdd/project.md`: Definition of Done item 19 (Build succeeds with zero warnings)
- Foundation for all subsequent tickets

## Objective & Definition of Done
Create the Xcode project with proper configuration, folder structure, and build settings to support Swift 6 concurrency and macOS Sonoma/Sequoia deployment.

- [ ] Xcode project created with bundle identifier `com.chernistry.omfk`
- [ ] Target deployment set to macOS 14.0+
- [ ] Swift 6 strict concurrency checking enabled
- [ ] Folder structure matches proposed architecture (/Core, /Engine, /UI, /Settings, /Logging)
- [ ] Info.plist includes privacy declarations for Accessibility
- [ ] Entitlements configured for `com.apple.security.automation.apple-events`
- [ ] SwiftLint and SwiftFormat configuration files added
- [ ] Project builds with zero warnings

## Steps
1. Create new macOS App project in Xcode 15+ with SwiftUI lifecycle
2. Set bundle identifier to `com.chernistry.omfk`, deployment target to macOS 14.0+
3. Enable Swift 6 strict concurrency in Build Settings (`SWIFT_STRICT_CONCURRENCY = complete`)
4. Create folder structure: OMFK/{Core,Engine,UI,Settings,Logging}, Tests/{CoreTests,EngineTests,IntegrationTests,PerformanceTests,Resources/LanguageCorpus}
5. Add Info.plist entries for `NSPrivacyAccessedAPITypes` with Accessibility declarations
6. Add entitlements file with `com.apple.security.automation.apple-events`
7. Create `.swiftlint.yml` with rules (line length 120, force unwrap warning, etc.)
8. Create `.swiftformat` with rules (indent 4 spaces, trailing commas, etc.)
9. Build project and resolve any warnings

## Affected files/modules
- `OMFK.xcodeproj` (new)
- `OMFK/Info.plist` (new)
- `OMFK/OMFK.entitlements` (new)
- `.swiftlint.yml` (new)
- `.swiftformat` (new)

## Tests
- Build project: `xcodebuild -project OMFK.xcodeproj -scheme OMFK -configuration Debug build`
- Verify zero warnings in build output
- Run SwiftLint: `swiftlint`

## Risks & Edge Cases
- Swift 6 strict concurrency may require additional annotations in later tickets
- Privacy declarations must match actual API usage or app will be rejected
- Entitlements must be properly signed for Accessibility to work

## Dependencies
- Upstream tickets: None (first ticket)
- Downstream tickets: All tickets depend on this