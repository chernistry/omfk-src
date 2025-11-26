# Implementation Notes - Comprehensive Logging & Debugging

## What Was Implemented

### 1. Comprehensive Logging System

Added detailed logging at every decision point across all components:

#### Logger.swift
- Added 3 new log categories: `events`, `inputSource`, `hotkey`
- Total 6 categories now: app, engine, detection, events, inputSource, hotkey

#### EventMonitor.swift
- **Startup logging**: Detailed event tap creation with success/failure indicators
- **Settings logging**: Shows current configuration on startup
- **Key event logging**: Every key press with keyCode, flags, and extracted characters
- **Buffer management**: Logs buffer state, timeouts, and clearing
- **Hotkey detection**: Clear indicators when hotkey is pressed
- **Processing decisions**: Logs why text is/isn't processed
- **Text replacement**: Logs deletion and typing operations

#### CorrectionEngine.swift
- **Correction attempts**: Full trace of every correction attempt
- **Language detection results**: Shows detected language for each word
- **Validation results**: Spell checker results for each word
- **Conversion attempts**: Logs all attempted conversions with results
- **Auto-switch decisions**: Shows when and why layout switching occurs
- **Manual corrections**: Separate logging for hotkey-triggered corrections

#### LanguageDetector.swift
- **Detection method**: Shows which method was used (NLLanguageRecognizer vs character set)
- **Character analysis**: Counts of Cyrillic, Latin, and Hebrew characters
- **NLLanguageRecognizer results**: Raw output from Apple's framework
- **Spell check results**: Detailed validation results for each word

#### InputSourceManager.swift
- **Current layout queries**: Shows current input source language
- **Available sources**: Lists all available keyboard layouts
- **Switch attempts**: Detailed logging of layout switching with success/failure
- **Error handling**: Clear error messages when layouts aren't found

### 2. Visual Indicators

All logs use emoji indicators for quick scanning:
- ✅ Success/confirmation
- ❌ Error/failure
- ⚠️ Warning
- 🔥 Hotkey events
- 🔍 Detection/search
- 🔄 Conversion/switching
- ⌨️ Keyboard input
- 📍 Word boundaries
- 📱 App context
- 🎯 Expected layout
- 📖 Dictionary validation
- 🧹 Cleanup operations

### 3. Debugging Tools

#### run_with_logs.sh
- Builds the app
- Starts it in background
- Streams logs with color highlighting
- Checks for running instances
- Validates startup

#### view_logs.sh
- Streams logs from running app
- Color-coded output
- Filters by subsystem

#### DEBUGGING.md
- Complete debugging guide
- Log category explanations
- Troubleshooting scenarios
- Testing procedures
- Common issues and solutions

## How to Use

### Quick Start

```bash
# Build and run with live logs
./run_with_logs.sh
```

Then type something in any app to see the event capture and processing.

### View Logs Only

If the app is already running:

```bash
./view_logs.sh
```

### Filter by Category

```bash
# Only keyboard events
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "events"' --level debug

# Only language detection
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "detection"' --level debug

# Only correction engine
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "engine"' --level debug
```

## Diagnostic Workflow

### 1. Verify Event Capture

Start the app and check for:
```
✅ Accessibility permission granted
✅ Event tap created successfully
✅ Event monitor started and enabled
```

Then type a few characters and look for:
```
🔵 KEY EVENT: keyCode=X
⌨️ Typed: 'a' | Buffer: 'test'
```

**If you don't see key events**: Event tap is not working. Check permissions.

### 2. Verify Language Detection

Type a word and press space. Look for:
```
🔍 === LANGUAGE DETECTION ===
Input: 'test'
Character analysis: RU=0, EN=4, HE=0
✅ Detected: English
```

**If detection is wrong**: Check character counts and NLLanguageRecognizer output.

### 3. Verify Correction Logic

Type a word in wrong layout (e.g., "ghbdtn" for "привет") and press space:
```
🔍 === CORRECTION ATTEMPT ===
Input: 'ghbdtn'
✅ Detected language: en
📖 Word 'ghbdtn' valid in en: NO
🔄 Trying conversion: en → ru: 'ghbdtn' → 'привет'
📖 Converted word 'привет' valid in ru: YES
✅ VALID CONVERSION FOUND!
✅ CORRECTION APPLIED
```

**If no correction**: Check if word is valid in detected language or conversion failed.

### 4. Verify Hotkey

Press left Alt (or configured hotkey):
```
🔥 HOTKEY DETECTED (keyCode 58)
🔥 === HOTKEY PRESSED - Manual Correction Mode ===
📝 Text for manual correction: 'test'
✅ MANUAL CORRECTION: 'test' → 'тест'
```

**If hotkey doesn't work**: Check keyCode in settings and logs.

### 5. Verify Auto-Switch

Enable "Auto-switch layout" in settings, then type in wrong layout:
```
🔄 Auto-switch enabled - switching input source to ru
🔄 === SWITCHING INPUT SOURCE ===
Target language: ru
✅ Found matching source: [ru]
✅ Successfully switched to ru
```

**If switching fails**: Check available sources list in logs.

## Known Behaviors

### "Buffer too short"
Normal - app only processes words with 3+ characters for accuracy.

### "Word valid in detected language"
Correct behavior - no correction needed if word exists in dictionary.

### "No valid conversions found"
The converted text doesn't exist in target language dictionary. Could be:
- Proper noun
- Technical term
- Abbreviation
- Mixed language text

## Performance

All operations should complete in <50ms. Monitor with:
```bash
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug | \
  grep -E "Processing buffer|CORRECTION APPLIED"
```

## Next Steps

1. **Test basic correction**: Type "ghbdtn" (should become "привет")
2. **Test hotkey**: Type text, press Alt
3. **Test auto-switch**: Enable in settings, type in wrong layout
4. **Test exclusions**: Add app to exclusion list, verify no corrections
5. **Monitor performance**: Check log timestamps for latency

## Troubleshooting

If something doesn't work:

1. **Check logs** - they show exactly what's happening
2. **Verify permissions** - Accessibility and Input Monitoring
3. **Check settings** - Is correction enabled? Is app excluded?
4. **Restart app** - Event tap can get stuck
5. **Check for conflicts** - Other keyboard tools (Karabiner, etc.)

## Files Modified

- `OMFK/Sources/Logging/Logger.swift` - Added new log categories
- `OMFK/Sources/Engine/EventMonitor.swift` - Comprehensive event logging
- `OMFK/Sources/Engine/CorrectionEngine.swift` - Detailed correction logic logging
- `OMFK/Sources/Core/LanguageDetector.swift` - Detection method logging
- `OMFK/Sources/Core/InputSourceManager.swift` - Layout switching logging

## Files Created

- `run_with_logs.sh` - Quick start script
- `view_logs.sh` - Log viewer script
- `DEBUGGING.md` - Complete debugging guide
- `IMPLEMENTATION_NOTES.md` - This file

## Testing Checklist

- [x] Build compiles without errors
- [ ] Event tap captures key presses
- [ ] Language detection works for RU/EN/HE
- [ ] Corrections apply correctly
- [ ] Hotkey triggers manual correction
- [ ] Auto-switch changes layout
- [ ] Exclusions prevent corrections
- [ ] Logs are comprehensive and clear
