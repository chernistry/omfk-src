# O.M.F.K Architecture

## Overview

O.M.F.K is a native macOS menu bar application built with Swift 6, SwiftUI, and AppKit. It monitors keyboard input system-wide, detects the language being typed, and automatically corrects text typed in the wrong keyboard layout.

## Core Principles

1. **Privacy-First**: All processing is local, no network calls, no persistent logging
2. **Low Latency**: <50ms correction latency requirement
3. **Native macOS**: Uses Apple frameworks exclusively (no external dependencies)
4. **Swift 6 Ready**: Strict concurrency checking enabled
5. **Minimal Permissions**: Only Accessibility and Input Monitoring

## Architecture Layers

### 1. Core Layer (`Sources/Core/`)

**Purpose**: Language detection and layout mapping logic

#### LanguageDetector.swift
- **Actor-based**: Thread-safe language detection
- **Hybrid approach**: 
  - Primary: Apple's NLLanguageRecognizer for 3+ word inputs
  - Fallback: Character set heuristics for short inputs (1-2 words)
- **Supported languages**: Russian, English, Hebrew
- **Performance**: <10ms detection time

```swift
actor LanguageDetector {
    func detect(_ text: String) async -> Language?
}
```

#### LayoutMapper.swift
- **Static mapping tables**: O(1) character lookup
- **Bidirectional conversion**: RU↔EN, HE↔EN
- **Keyboard layouts**:
  - Russian: ЙЦУКЕН ↔ QWERTY
  - Hebrew: Hebrew Standard ↔ QWERTY

```swift
struct LayoutMapper {
    static func convert(_ text: String, from: Language, to: Language) -> String?
}
```

### 2. Engine Layer (`Sources/Engine/`)

**Purpose**: Event monitoring and correction logic

#### EventMonitor.swift
- **CGEventTap**: Low-level keyboard event interception
- **Main actor**: All event handling on main thread
- **Buffer management**: Accumulates characters until word boundary
- **Auto-restart**: Handles tap timeout/disable events
- **Permission handling**: Requests Accessibility access

**Event Flow**:
1. CGEventTap intercepts keyDown events
2. Extract character from event
3. Accumulate in buffer
4. On whitespace/newline: process buffer
5. Clear buffer after correction

```swift
@MainActor
final class EventMonitor {
    func start() async
    func stop()
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>
}
```

#### CorrectionEngine.swift
- **Actor-based**: Thread-safe correction state
- **History tracking**: Last 50 corrections
- **Per-app rules**: Excluded apps support
- **Correction strategies**:
  1. Expected layout mode: Correct if detected ≠ expected
  2. Auto-detect mode: Correct if detected ≠ preferred language

```swift
actor CorrectionEngine {
    func correctText(_ text: String, expectedLayout: Language?) async -> String?
    func shouldCorrect(for bundleId: String?) async -> Bool
}
```

### 3. UI Layer (`Sources/UI/`)

**Purpose**: SwiftUI-based user interface

#### MenuBarView.swift
- **MenuBarExtra**: Native macOS Sequoia menu bar integration
- **Quick actions**: Toggle, Settings, History, Quit
- **Status indicator**: Visual feedback (green/gray dot)

#### SettingsView.swift
- **Form-based**: Native macOS settings UI
- **Sections**:
  - General: Enable/disable, preferred language
  - Excluded Apps: Per-app rules
  - About: Version info

#### HistoryView.swift
- **List-based**: Recent corrections display
- **Record format**: Original → Corrected (LANG → LANG)
- **Actions**: Clear history

### 4. Settings Layer (`Sources/Settings/`)

**Purpose**: Configuration persistence

#### SettingsManager.swift
- **ObservableObject**: SwiftUI reactive updates
- **UserDefaults**: Persistent storage
- **Settings**:
  - `isEnabled`: Auto-correction toggle
  - `preferredLanguage`: Primary language
  - `excludedApps`: Set of bundle IDs
  - `autoSwitchLayout`: Keyboard layout switching

```swift
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
}
```

### 5. Logging Layer (`Sources/Logging/`)

**Purpose**: Structured logging with OSLog

```swift
extension Logger {
    static let app = Logger(subsystem: "com.chernistry.omfk", category: "app")
    static let engine = Logger(subsystem: "com.chernistry.omfk", category: "engine")
    static let detection = Logger(subsystem: "com.chernistry.omfk", category: "detection")
}
```

## Data Flow

```
User Types → CGEventTap → EventMonitor → Buffer
                                ↓
                         Word Boundary?
                                ↓
                    CorrectionEngine.shouldCorrect()
                                ↓
                    LanguageDetector.detect()
                                ↓
                    LayoutMapper.convert()
                                ↓
                    Replace Text (Delete + Type)
                                ↓
                    Add to History
```

## Concurrency Model

### Swift 6 Strict Concurrency

- **Actors**: `LanguageDetector`, `CorrectionEngine`
- **@MainActor**: `EventMonitor`, `SettingsManager`, `AppDelegate`
- **Sendable**: All data types crossing actor boundaries

### Thread Safety

1. **Event handling**: Main thread (CGEventTap requirement)
2. **Language detection**: Actor-isolated (async)
3. **Settings**: Main actor (SwiftUI requirement)
4. **History**: Actor-isolated (CorrectionEngine)

## Performance Characteristics

### Latency Budget

- Event capture: <5ms
- Language detection: <10ms
- Layout conversion: <1ms (O(1) lookup)
- Text replacement: <30ms
- **Total**: <50ms end-to-end

### Memory Usage

- Base: ~50MB
- Per correction record: ~1KB
- History (50 records): ~50KB
- **Total**: <100MB typical

## Security & Privacy

### Permissions

1. **Accessibility**: Required for CGEventTap
2. **Input Monitoring**: Required for keyboard event reading

### Privacy Measures

1. **No network**: All processing local
2. **No persistent logs**: Typed text cleared immediately
3. **Limited history**: Only 50 recent corrections
4. **No analytics**: No telemetry or tracking
5. **Sandboxed**: Where possible (event tap requires entitlements)

### Info.plist Declarations

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Monitor keyboard input for layout correction</string>

<key>NSInputMonitoringUsageDescription</key>
<string>Detect and correct wrong layout typing</string>
```

## Testing Strategy

### Unit Tests

1. **LanguageDetectorTests**: Language detection accuracy
2. **LayoutMapperTests**: Character mapping correctness

### Integration Tests (Manual)

1. Type Russian in English layout → Auto-correct
2. Type Hebrew in English layout → Auto-correct
3. Excluded app → No correction
4. Disabled state → No correction

### Performance Tests

```bash
# Profile with Instruments
xcodebuild -scheme OMFK -configuration Release -derivedDataPath .build
open -a Instruments .build/Build/Products/Release/OMFK.app
```

## Build Configuration

### Swift Package Manager

```swift
platforms: [.macOS(.v14)]
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency")
]
```

### Compiler Flags

- Swift 6 strict concurrency
- Optimization: `-O` (release)
- Warnings as errors: Disabled (Carbon API warnings)

## Deployment

### Requirements

- macOS Sonoma (14.0+)
- Xcode 15+
- Swift 5.10+

### Distribution

1. **Development**: `swift run`
2. **Release**: `swift build -c release`
3. **App Bundle**: Xcode archive + export

### Code Signing

```bash
# Sign for local use
codesign --force --deep --sign - .build/release/OMFK
```

## Future Enhancements

### Planned Features

1. **Hotkeys**: ⌘⇧Z (undo), ⌘⇧L (toggle)
2. **More languages**: Add support for other language pairs
3. **Smart detection**: ML-based gibberish detection
4. **Layout switching**: Auto-switch macOS keyboard layout
5. **Undo**: Revert last correction

### Performance Optimizations

1. **Predictive correction**: Start detection before word boundary
2. **Caching**: Cache recent detection results
3. **Batch processing**: Process multiple words at once

### Architecture Improvements

1. **Plugin system**: Extensible language support
2. **Rule engine**: Complex per-app correction rules
3. **Statistics**: Correction accuracy metrics

## Troubleshooting

### Common Issues

1. **Event tap disabled**: Auto-restart mechanism handles this
2. **Permission denied**: Prompt user to grant in System Settings
3. **High CPU**: Reduce buffer processing frequency
4. **Memory leak**: History limited to 50 records

### Debugging

```bash
# Enable debug logging
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug

# Profile performance
instruments -t "Time Profiler" .build/release/OMFK
```

## References

- [CGEventTap Documentation](https://developer.apple.com/documentation/coregraphics/cgeventtap)
- [NLLanguageRecognizer](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
