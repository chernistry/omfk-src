# Project: O.M.F.K — Oh My Fucking Keyboard
## Goal
Build a native macOS menu bar utility that automatically detects the language being typed (Russian/English/Hebrew) and corrects text typed in the wrong keyboard layout, with first-class Hebrew support and modern language detection.
## Tech Stack
- **Language**: Swift 5.10+ (Swift 6-ready)
- **UI**: SwiftUI + AppKit (NSStatusBar, NSApplication)
- **Frameworks**:
 - AppKit for menu bar and macOS lifecycle
 - CGEventTap/NSEvent for global keyboard monitoring
 - NaturalLanguage (NLLanguageRecognizer) for language detection
 - UserDefaults for settings persistence
- **Architecture**: Modular structure (/core, /engine, /ui, /settings, /logging)
- **Target**: macOS Sonoma/Sequoia
- **Testing**: XCTest for unit and integration tests
## Scope
- Real-time keyboard input monitoring system-wide
- Language detection for RU/EN/HE with custom heuristics layer + NSSpellChecker word validation
- Automatic wrong-layout correction with undo capability
- Menu bar app with status icon and popover UI
- Settings panel for configuration (hotkeys, per-app rules, sensitivity)
- History view showing recent corrections
- Hotkey support for manual correction, toggle auto-correction, language cycling
- Per-app exclusion rules (password managers, terminals, etc.)
- Proper macOS permissions handling (Accessibility, Input Monitoring)
- RTL text support for Hebrew
- Low-latency, non-blocking architecture
## Definition of Done
- [ ] Menu bar app launches and displays status icon
- [ ] Global keyboard event monitoring active with proper permissions
- [ ] Language detection working for RU/EN/HE on 3-10 word chunks
- [ ] NSSpellChecker validates words in detected language; converts layout if invalid
- [ ] Layout mapping tables implemented for RU↔EN and HE↔EN
- [ ] Automatic text correction replaces wrong-layout text in real-time
- [ ] Manual correction hotkey converts last typed fragment
- [ ] Toggle auto-correction hotkey implemented
- [ ] Settings UI with hotkey configuration, per-app rules, and sensitivity controls
- [ ] History view displays last 20+ corrections with undo functionality
- [ ] Per-app exclusion list functional (user can add/remove apps)
- [ ] Hebrew RTL rendering correct in UI and correction logic
- [ ] No noticeable input lag (<50ms detection + correction)
- [ ] Unit tests cover language detection accuracy (>90% for clear text)
- [ ] Integration tests validate RU↔EN, HE↔EN, and mixed-text scenarios
- [ ] App properly requests and handles Accessibility/Input Monitoring permissions
- [ ] Bundle identifier set to com.chernistry.omfk
- [ ] App name displays as "O.M.F.K" in UI, "Oh My Fucking Keyboard" in About
- [ ] Crash-free operation for 1+ hour continuous use
- [ ] Memory usage stable (<100MB typical)
- [ ] Build succeeds with zero warnings on Xcode 15+