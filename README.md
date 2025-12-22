# O.M.F.K — Oh My Fucking Keyboard

A modern macOS utility for smart keyboard layout correction with first-class support for Russian, English, and Hebrew.

## Features

- **Real-time language detection** using Apple's NaturalLanguage framework + custom heuristics
- **Automatic layout correction** for RU ↔ EN and HE ↔ EN
- **Menu bar app** with clean, native macOS UI
- **Per-app exclusions** for password managers, terminals, etc.
- **Correction history** with undo capability
- **Privacy-first**: All processing is local, no network calls, no persistent logging
- **Swift 6-ready** with strict concurrency checking

## Requirements

- macOS Sonoma (14.0) or later
- Xcode 15+ with Swift 5.10+
- Accessibility and Input Monitoring permissions

## Building

```bash
swift build -c release
```

## Running

```bash
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

## Testing

```bash
./omfk.sh test
```

## Debugging

The app includes comprehensive logging for debugging. To run with live logs:

```bash
./omfk.sh run --logs
```

Or view logs separately:

```bash
./omfk.sh logs stream
```

See [DEBUGGING.md](DEBUGGING.md) for detailed debugging guide.

### Log Categories

- **app** - Application lifecycle
- **engine** - Correction logic and decisions
- **detection** - Language detection with character analysis
- **events** - Keyboard event capture (every key press)
- **inputSource** - Layout switching
- **hotkey** - Hotkey detection and manual correction

### Quick Diagnostics

Check if event capture is working:
```bash
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "events"' --level debug
```

Then type something - you should see logs for every key press.

## Architecture

```
OMFK/
├── Sources/
│   ├── Core/           # Language detection & layout mapping
│   ├── Engine/         # Correction engine & event monitoring
│   ├── UI/             # SwiftUI views
│   ├── Settings/       # Configuration management
│   └── OMFKApp.swift   # App entry point
├── Resources/
│   └── Info.plist      # Privacy declarations
└── Tests/              # Unit tests
```

## Permissions

On first launch, O.M.F.K will request:

1. **Accessibility** - Required to monitor keyboard events
2. **Input Monitoring** - Required to read typed characters

Grant these in System Settings → Privacy & Security.

## Usage

1. Launch O.M.F.K
2. Click the keyboard icon in the menu bar
3. Toggle auto-correction on/off
4. Configure settings and excluded apps
5. Type normally - corrections happen automatically

## Hotkeys

- **⌘⇧Z** - Undo last correction (planned)
- **⌘⇧L** - Toggle auto-correction (planned)

## License

Copyright © 2025 Chernistry. All rights reserved.
