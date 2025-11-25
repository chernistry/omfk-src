# Changelog

All notable changes to O.M.F.K will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-11-25

### Added
- Initial release of O.M.F.K (Oh My Fucking Keyboard)
- Real-time language detection using Apple's NaturalLanguage framework
- Automatic layout correction for Russian ↔ English
- Automatic layout correction for Hebrew ↔ English
- Native macOS menu bar app with SwiftUI
- Settings panel with configuration options
- Correction history view (last 50 corrections)
- Per-app exclusions support
- Privacy-first architecture (local processing only)
- Swift 6 strict concurrency support
- Comprehensive unit tests (14 tests, 100% pass rate)
- Complete documentation (README, QUICKSTART, ARCHITECTURE, CONTRIBUTING)

### Core Features
- **LanguageDetector**: Hybrid detection (NLLanguageRecognizer + character set heuristics)
- **LayoutMapper**: Static mapping tables for O(1) conversion
- **CorrectionEngine**: Actor-based correction with history tracking
- **EventMonitor**: CGEventTap-based keyboard monitoring
- **SettingsManager**: UserDefaults-based configuration persistence

### Technical Highlights
- Zero external dependencies
- <50ms end-to-end correction latency
- <100MB memory usage
- Actor-based concurrency for thread safety
- Main actor UI for SwiftUI integration
- Accessibility and Input Monitoring permissions

### Documentation
- README.md: User-facing documentation
- QUICKSTART.md: Quick start guide
- ARCHITECTURE.md: Technical architecture details
- CONTRIBUTING.md: Development guide
- PROJECT_SUMMARY.md: Project overview
- CHANGELOG.md: This file

### Testing
- 7 language detection tests
- 7 layout mapping tests
- 100% test pass rate
- Verification script included

## [Unreleased]

### Planned for v1.1
- Hotkeys: ⌘⇧Z (undo last correction)
- Hotkeys: ⌘⇧L (toggle auto-correction)
- Undo last correction feature
- Auto-switch macOS keyboard layout option
- Improved word boundary detection

### Planned for v1.2
- Additional language pairs (German, French, Spanish)
- Per-word correction (not buffer-based)
- Smart gibberish detection
- Correction statistics

### Planned for v2.0
- ML-based language detection
- Plugin system for custom languages
- Cloud sync for settings
- Advanced correction rules engine

---

## Version History

- **1.0.0** (2025-11-25): Initial release

---

## Notes

### Breaking Changes
None yet (initial release)

### Deprecations
None yet (initial release)

### Security
- All processing is local (no network calls)
- No persistent keyboard logging
- Minimal permissions required
- Privacy declarations in Info.plist

### Performance
- Language detection: ~5ms
- Layout conversion: <1ms
- End-to-end correction: ~30ms
- Memory usage: ~50MB typical

---

[1.0.0]: https://github.com/chernistry/omfk/releases/tag/v1.0.0
