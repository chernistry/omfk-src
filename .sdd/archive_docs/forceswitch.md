# OMFK Force Switch / Manual Correction Logic

## Current Implementation (v2.0)

### Trigger: Option (Alt) Key Tap

**Hotkey**: Left Option (keyCode 58) — press and release without other keys.

**Detection**: Via `flagsChanged` event in CGEventTap:
- On Option press: `optionKeyWasPressed = true`
- On Option release (if no other keys pressed): trigger `handleHotkeyPress()`
- If another key pressed while Option held: reset flag (not a tap)

**Note**: Option+Shift was removed. Single Option key handles all modes.

---

## Three Operating Modes

| Mode | Trigger Condition | Text Source | Cycling Order |
|------|-------------------|-------------|---------------|
| 1. Undo/cycle after correction | Alt within 3s of last correction | `lastCorrectedText` | original → lang2 → lang3 → original |
| 2. Manual buffer correction | Alt with no selection, buffer empty but `lastCorrectedText` exists | `lastCorrectedText` | same as above |
| 3. Manual selection correction | Alt with text selected | AX API or clipboard fallback | smart → lang1 → lang2 → original |

### Mode Detection Logic

```swift
handleHotkeyPress():
    // Mode 1 & 2: Check for existing cycling state
    if hasCyclingState && timeSinceLastCorrection < 3.0 && lastCorrectedLength > 0:
        → Continue cycling through alternatives
        
    // Mode 3: Get fresh selection
    rawText = getSelectedTextFresh()
    if rawText.isEmpty:
        → "no text to correct" error
    else:
        → Create new cycling state, start correction
```

---

## Text Acquisition Strategy

### Primary Path: Accessibility API (for supported apps)

```swift
getSelectedTextFresh():
    1. If buffer not empty and fresh (< 0.5s): return buffer
    2. Try AX API: AXUIElementCopyAttributeValue(kAXSelectedTextAttribute)
       - If returns non-empty text: return it (set lastSelectionWasExplicit = true)
    3. Fallback to buffer even if stale
    4. Return empty string if nothing available
```

**Apps with working AX support:**
- TextEdit (`com.apple.TextEdit`)
- Typora (`abnerworks.Typora`)
- Safari (`com.apple.Safari`)
- Notes (`com.apple.Notes`)

### Fallback Path: Clipboard (for apps without AX support)

**Apps requiring clipboard fallback:**
- Sublime Text (`com.sublimetext.4`)
- VS Code (`com.microsoft.VSCode`)
- Terminal (`com.apple.Terminal`)
- Electron-based apps
- Web text fields in browsers

**Clipboard fallback algorithm:**
```swift
getSelectedTextViaClipboard():
    1. Save current clipboard content
    2. Send Cmd+C to copy selection
    3. Wait 100ms for clipboard update
    4. Read clipboard content
    5. Restore original clipboard
    6. Return copied text
```

### App Detection Strategy

OMFK should auto-detect which apps need clipboard fallback:

```swift
// Cache per bundle ID
var appsWithoutAXSelection: Set<String> = []

func getSelectedText(bundleId: String) -> String:
    // If known to not support AX, go straight to clipboard
    if appsWithoutAXSelection.contains(bundleId):
        return getSelectedTextViaClipboard()
    
    // Try AX first
    if let axText = getSelectedTextViaAccessibility(), !axText.isEmpty:
        return axText
    
    // AX returned empty - try clipboard fallback
    let clipboardText = getSelectedTextViaClipboard()
    if !clipboardText.isEmpty:
        // Remember this app doesn't support AX
        appsWithoutAXSelection.insert(bundleId)
    
    return clipboardText
```

---

## Cycling State

### Structure

```swift
struct CyclingState {
    let originalText: String           // Original text before any correction
    let alternatives: [Alternative]    // All variants including original
    var currentIndex: Int              // Current position in cycle
    let wasAutomatic: Bool             // Auto-correction or manual hotkey
    let autoHypothesis: LanguageHypothesis?
    let timestamp: Date                // For timeout (60s)
    let hadTrailingSpace: Bool         // Preserve trailing space in cycling
}

struct Alternative {
    let text: String
    let hypothesis: LanguageHypothesis?
}
```

### Cycling State Creation

**After auto-correction (in `correctText()`):**
```
Original: "ghbdtn" → Corrected: "привет"
Alternatives:
  [0] "ghbdtn"  — original (undo target)
  [1] "привет"  — auto-corrected (current)
  [2] "גהבדתנ"  — third language alternative
currentIndex = 1 (showing corrected)
```

**After typing "correct" text (no correction needed):**
```
Original: "привет" (already correct Russian)
Alternatives:
  [0] "привет"  — original (current)
  [1] "ghbdtn"  — convert to English layout
  [2] "גהבדתנ"  — convert to Hebrew layout
currentIndex = 0 (showing original)
```

**For manual correction (`correctLastWord()`):**
```
Original: "wloM"
Alternatives:
  [0] "wloM"    — original (undo target)
  [1] "שלום"    — smart correction (best guess)
  [2] "цдщь"    — EN→RU conversion
  [3] ...       — other unique conversions
currentIndex = 0, first cycle() returns [1]
```

### Cycling Behavior

```swift
cycleCorrection():
    currentIndex = (currentIndex + 1) % alternatives.count
    return alternatives[currentIndex].text
```

**Example cycle for "привет" (correct Russian):**
1. Initial state: showing "привет " (index 0)
2. Alt #1 → "ghbdtn " (index 1, English)
3. Alt #2 → "גהבדתנ " (index 2, Hebrew)
4. Alt #3 → "привет " (index 0, back to original)
5. ...continues cycling

---

## Text Replacement

### For apps with AX support (explicit selection)

```swift
typeOverSelection(with: text):
    // Simply type the new text - it replaces selection
    typeUnicodeString(text)
```

### For buffer-based replacement

```swift
replaceText(with: text, originalLength: count):
    // Delete original text with backspaces
    for _ in 0..<count:
        postBackspace()
    // Type new text
    typeUnicodeString(text)
```

### Event Posting

Use `CGEventTapPostEvent(proxy, event)` instead of `CGEventPost()` to avoid synthetic events being captured by our own event tap.

---

## State Invalidation

Cycling state is reset when:
- User types new characters (non-whitespace)
- App focus changes
- Mouse click detected
- Navigation keys pressed (arrows, Home, End, etc.)
- More than 60 seconds since last correction
- Backspace/Delete pressed

---

## Comparison: Auto-correction vs Manual Correction

| Aspect | Auto-correction | Manual (hotkey) |
|--------|-----------------|-----------------|
| Trigger | Space/Enter after word | Option tap |
| Text source | Internal buffer | Selection or lastCorrectedText |
| Creates cycling state | Yes | Yes |
| First Alt action | Undo to original | Next alternative |
| Trailing space | Adds space | Preserves original |
| Works without typing | No | Yes (with selection) |

---

## Files

- `EventMonitor.swift` — hotkey detection, text acquisition, replacement, cycling coordination
- `CorrectionEngine.swift` — cycling logic, alternative generation, language detection
- `LayoutMapper.swift` — character conversion between layouts
- `SelectionCapture.swift` — selection detection and replacement planning

---

## Known Limitations

1. **Clipboard fallback is slower** — requires Cmd+C round-trip (~100-200ms)
2. **Some apps don't support either method** — rare, but possible
3. **No visual preview** — user doesn't see available alternatives before cycling
4. **Undo (Cmd+Z) behavior varies** — depends on how app handles synthetic input
