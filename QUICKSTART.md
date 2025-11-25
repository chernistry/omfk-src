# O.M.F.K Quick Start Guide

## Prerequisites

- macOS Sonoma (14.0) or later
- Xcode 15+ with Swift 5.10+

## Build & Run

### Option 1: Swift Package Manager (Recommended)

```bash
# Build
swift build -c release

# Run
swift run
```

### Option 2: Xcode

```bash
# Open in Xcode
open Package.swift

# Then press ⌘R to build and run
```

## First Launch Setup

1. **Grant Permissions**: On first launch, O.M.F.K will request two permissions:
   - **Accessibility** - Required to monitor keyboard events
   - **Input Monitoring** - Required to read typed characters
   
2. **System Settings**: If prompted, go to:
   - System Settings → Privacy & Security → Accessibility
   - System Settings → Privacy & Security → Input Monitoring
   - Enable O.M.F.K in both sections

3. **Restart**: After granting permissions, restart the app

## Usage

### Menu Bar

- Click the keyboard icon in the menu bar to access:
  - Toggle auto-correction on/off
  - Settings
  - Correction history
  - Quit

### Settings

- **Enable auto-correction**: Toggle automatic layout correction
- **Auto-switch keyboard layout**: Automatically switch macOS keyboard layout
- **Preferred language**: Set your primary language (EN/RU/HE)
- **Excluded apps**: Add apps where correction should be disabled

### How It Works

1. Type normally in any application
2. O.M.F.K detects the language you're typing
3. If you typed in the wrong layout, it automatically corrects it
4. View correction history from the menu bar

### Supported Conversions

- Russian ↔ English (ЙЦУКЕН ↔ QWERTY)
- Hebrew ↔ English (Hebrew Standard ↔ QWERTY)

## Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter LanguageDetectorTests
```

## Troubleshooting

### App doesn't correct text

1. Check that auto-correction is enabled (menu bar icon)
2. Verify permissions are granted in System Settings
3. Check if the current app is in the excluded list
4. Restart the app

### Permissions not working

1. Remove O.M.F.K from Accessibility and Input Monitoring
2. Restart your Mac
3. Launch O.M.F.K again and grant permissions

### Build errors

```bash
# Clean build
rm -rf .build
swift build
```

## Development

### Project Structure

```
OMFK/
├── Sources/
│   ├── Core/           # Language detection & layout mapping
│   │   ├── LanguageDetector.swift
│   │   └── LayoutMapper.swift
│   ├── Engine/         # Correction engine & event monitoring
│   │   ├── CorrectionEngine.swift
│   │   └── EventMonitor.swift
│   ├── UI/             # SwiftUI views
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   └── HistoryView.swift
│   ├── Settings/       # Configuration management
│   │   └── SettingsManager.swift
│   ├── Logging/        # Structured logging
│   │   └── Logger.swift
│   └── OMFKApp.swift   # App entry point
├── Resources/
│   └── Info.plist      # Privacy declarations
└── Tests/              # Unit tests
    ├── LanguageDetectorTests.swift
    └── LayoutMapperTests.swift
```

### Adding New Language Pairs

1. Add language to `Language` enum in `LanguageDetector.swift`
2. Add character mappings in `LayoutMapper.swift`
3. Update language hints in `LanguageDetector.init()`
4. Add tests in `LayoutMapperTests.swift`

## Performance

- Language detection: <10ms for typical input
- Correction latency: <50ms end-to-end
- Memory usage: <100MB typical

## Privacy

- All processing is local (no network calls)
- No persistent keyboard logging
- Typed text is cleared immediately after correction
- Only correction history is stored (last 50 corrections)

## License

Copyright © 2025 Chernistry. All rights reserved.
