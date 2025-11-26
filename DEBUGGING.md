# OMFK Debugging Guide

## Comprehensive Logging

The application now has detailed logging at every decision point. All logs use the subsystem `com.chernistry.omfk` with the following categories:

### Log Categories

- **app** - Application lifecycle events
- **engine** - Correction engine decisions and logic
- **detection** - Language detection with character analysis
- **events** - Keyboard event capture and processing
- **inputSource** - Input source/layout switching
- **hotkey** - Hotkey detection and manual correction

### Viewing Logs in Real-Time

Use the provided script to stream all OMFK logs with color highlighting:

```bash
./view_logs.sh
```

Or manually with the `log` command:

```bash
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug --style compact
```

### Viewing Historical Logs

To see logs from the last run:

```bash
log show --predicate 'subsystem == "com.chernistry.omfk"' --last 5m --style compact
```

### Filtering by Category

To see only specific categories:

```bash
# Only keyboard events
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "events"' --level debug

# Only language detection
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "detection"' --level debug

# Only correction engine
log stream --predicate 'subsystem == "com.chernistry.omfk" AND category == "engine"' --level debug
```

## What to Look For

### 1. Event Tap Initialization

When you start the app, you should see:

```
✅ Accessibility permission granted
✅ Event tap created successfully
✅ Event monitor started and enabled - waiting for keyboard events...
=== EventMonitor is now active ===
```

If you see `❌ Accessibility permission denied`, grant permissions in:
**System Settings → Privacy & Security → Accessibility**

### 2. Keyboard Event Capture

Every key press should log:

```
🔵 KEY EVENT: keyCode=X, flags=Y
⌨️ Typed: 'a' | Buffer: 'hello' (len=5)
```

If you don't see these logs when typing, the event tap is not capturing events.

### 3. Language Detection

When processing text, you'll see:

```
🔍 === LANGUAGE DETECTION ===
Input: 'ghbdtn' (len=6)
Character analysis: RU=0, EN=6, HE=0
✅ Detected: English
```

### 4. Correction Logic

The engine logs every decision:

```
🔍 === CORRECTION ATTEMPT ===
Input: 'ghbdtn' (len=6)
✅ Detected language: en
📖 Word 'ghbdtn' valid in en: NO
🔄 Word invalid in detected language - trying conversions...
🔄 Trying conversion: en → ru: 'ghbdtn' → 'привет'
📖 Converted word 'привет' valid in ru: YES
✅ VALID CONVERSION FOUND!
✅ CORRECTION APPLIED: 'ghbdtn' → 'привет'
```

### 5. Hotkey Detection

When pressing the hotkey (left Alt by default):

```
🔥 HOTKEY DETECTED (keyCode 58) - triggering manual correction
🔥 === HOTKEY PRESSED - Manual Correction Mode ===
📝 Text for manual correction: 'test' (len=4)
✅ MANUAL CORRECTION: 'test' → 'тест'
```

### 6. Layout Switching

When auto-switch is enabled:

```
🔄 Auto-switch enabled - switching input source to ru
🔄 === SWITCHING INPUT SOURCE ===
Target language: ru
Found 3 input sources
✅ Found matching source: [ru]
✅ Successfully switched to ru
```

## Troubleshooting

### No Logs Appearing

1. **Check if app is running**: Look for OMFK in Activity Monitor
2. **Check permissions**: System Settings → Privacy & Security → Accessibility
3. **Restart the app**: Sometimes the event tap needs a fresh start

### Event Tap Not Capturing

If you see the startup logs but no key events:

1. **Verify accessibility permission** is granted
2. **Check if another app** is intercepting events (Karabiner, BetterTouchTool, etc.)
3. **Try restarting** your Mac (event taps can get stuck)

### Language Detection Not Working

Check the logs for:
- Character analysis counts (RU=X, EN=Y, HE=Z)
- NLLanguageRecognizer results
- Spell checker results

### Corrections Not Applying

Look for:
- `🚫 Correction disabled for app` - app is in exclusion list
- `❌ Correction globally disabled` - toggle is off in settings
- `ℹ️ No correction needed` - word is valid in detected language

### Layout Not Switching

Check for:
- `❌ No input source found for language: XX` - language not installed
- `❌ Failed to select input source` - permission issue
- Available sources list in logs

## Testing Scenarios

### Test 1: Basic RU→EN Correction

1. Start the app and log viewer
2. Type in English layout: `ghbdtn` (should be "привет")
3. Press Space
4. Check logs for detection and correction

### Test 2: Hotkey Correction

1. Type some text in wrong layout
2. Select the text (or leave cursor at end)
3. Press left Alt (or configured hotkey)
4. Check logs for hotkey detection and manual correction

### Test 3: Auto-Switch

1. Enable "Auto-switch layout" in settings
2. Type a word in wrong layout
3. Press Space
4. Check logs for layout switching
5. Continue typing - should now be in correct layout

### Test 4: Excluded Apps

1. Add current app to exclusion list
2. Try typing in wrong layout
3. Should see: `🚫 Correction disabled for app`

## Performance Monitoring

Monitor event processing latency:

```bash
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug | \
  grep -E "(Processing buffer|CORRECTION APPLIED)" | \
  awk '{print $1, $2}'
```

Each correction should complete in <50ms.

## Common Issues

### Issue: "Buffer too short"

This is normal - the app only processes words with 3+ characters.

### Issue: "Word valid in detected language"

The word exists in the dictionary, so no correction is needed. This is correct behavior.

### Issue: "No valid conversions found"

The converted text doesn't exist in the target language dictionary. This might be:
- A proper noun
- A technical term
- An abbreviation
- Actually correct in the original language

## Advanced Debugging

### Export Logs to File

```bash
log show --predicate 'subsystem == "com.chernistry.omfk"' --last 1h > omfk_debug.log
```

### Watch Specific Text

```bash
log stream --predicate 'subsystem == "com.chernistry.omfk" AND eventMessage CONTAINS "привет"'
```

### Count Events

```bash
log show --predicate 'subsystem == "com.chernistry.omfk" AND category == "events"' --last 5m | wc -l
```

## Getting Help

When reporting issues, include:

1. Output from `./view_logs.sh` during the problem
2. macOS version: `sw_vers`
3. App version and build
4. Steps to reproduce
5. Expected vs actual behavior
