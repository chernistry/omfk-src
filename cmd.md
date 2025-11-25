time node bin/kotef run \
  --root /Users/sasha/IdeaProjects/personal_projects/omfk \
  --goal "Build a modern (2025), production-grade macOS utility called O.M.F.K — Oh My Fucking Keyboard.

  High-level:
  O.M.F.K is a native macOS background app, spiritually similar to Punto Switcher, focused on smart layout correction for Russian / English / Hebrew with first-class Hebrew support and state-of-the-art language detection.

  Product identity:
  - App name (UI): O.M.F.K
  - Long name/tagline: Oh My Fucking Keyboard — smart layout fixer for RU/EN/HE.
  - Menu bar title/icon: minimal icon + short tooltip 'O.M.F.K — layout fixer'.
  - Bundle identifier: com.chernistry.omfk (adjust if needed, but keep omfk as the core id).
  - Use 'O.M.F.K' consistently in the UI, 'Oh My Fucking Keyboard' in about/help texts.

  Primary goal:
  A native macOS app that runs in the background, monitors keyboard input system-wide, automatically detects the language the user is typing in (Russian / English / Hebrew), and:
  - fixes text typed in the wrong layout;
  - optionally switches the active keyboard layout;
  - provides a smooth, low-latency experience.

  Core functionality:
  1) Real-time language detection for input fragments (words/phrases).
  2) Full support for RU / EN / HE, including right-to-left behavior for Hebrew.
  3) Wrong-layout correction (Punto-Switcher-style), but using modern heuristics/ML.
  4) Menu bar app UX: icon in the macOS status bar with quick access to settings and history.
  5) Hotkeys for:
     - manual layout correction of the last typed fragment;
     - toggling auto-correction on/off;
     - cycling languages if needed.
  6) History of recent corrections with the ability to undo.
  7) Per-app rules:
     - excluded apps (e.g., password managers, terminals);
     - different sensitivity thresholds per app if needed.
  8) Non-intrusive UX: minimal dialogs, quiet background operation, no noticeable lag.

  Technical requirements (stack & architecture):
  - Language: Swift (Swift 5.10+ / Swift 6-ready).
  - UI: SwiftUI for all UI, with AppKit integration where needed (NSStatusBar, NSApplication).
  - Frameworks:
      * AppKit for menu bar integration and macOS lifecycle.
      * Core Graphics / Quartz Event Taps (CGEventTap) or NSEvent global monitors for keyboard events.
      * NaturalLanguage framework (NLLanguageRecognizer) as the primary language detector.
      * Additional lightweight heuristic layer on top of NLLanguageRecognizer to better disambiguate RU/HE/EN (character sets, n-grams, scoring).
  - Architecture:
      * /core – language detection, layout mapping, text transformation.
      * /engine – correction engine, rules, per-app policies, hotkey handling.
      * /ui – SwiftUI views for menu bar popover, settings, history.
      * /settings – persistence (UserDefaults or small local store), config management.
      * /logging – structured logs and optional debug overlay.
  - macOS:
      * Target macOS Sonoma / Sequoia.
      * Proper sandboxing where possible; request only required permissions (Accessibility, Input Monitoring).
  - Testing:
      * Unit tests for language detection and layout-conversion logic.
      * Snapshot / integration tests for key correction scenarios (RU↔EN, HE↔EN, mixed).
  - Performance:
      * Language detection must work on small chunks (3–10 words) with minimal latency.
      * Avoid blocking the main thread; use async/actors/Combine where appropriate.

  Final result:
  A polished, stable, and fast macOS language switcher named O.M.F.K (Oh My Fucking Keyboard), with first-class Hebrew support, accurate modern language detection, clean 2025-style architecture, and a native Apple-like menu bar UX." \
  --max-coder-turns 150