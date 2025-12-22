# Ticket 20: Alt-Key Manual Correction Cycling

Spec version: v1.0

## Context

When automatic layout correction fails or is incorrect, users need a manual fallback. The Alt key should allow cycling through possible layout interpretations of the last typed word.

## Current Behavior (Broken)

- Alt key triggers `correctLastWord()` but does not cycle through options
- If correction was applied automatically and user presses Alt, there's no undo
- No visual feedback about what will happen

## Desired Behavior

### Alt Key Press Logic:

1. **If last word was NOT auto-corrected:**
   - 1st press: Convert to most likely alternative language
   - 2nd press: Convert to next most likely language
   - 3rd press: Revert to original
   - ...cycle continues

2. **If last word WAS auto-corrected:**
   - 1st press: Revert to original (undo correction)
   - 2nd press: Try next alternative
   - 3rd press: Back to corrected version
   - ...cycle continues

### Example:

User types `ghbdtn` (intended Russian, English layout active)

**Scenario A - Auto-correction worked:**
- System auto-corrects to `привет`
- User presses Alt → `ghbdtn` (original)
- User presses Alt → `גהבדתנ` (Hebrew interpretation)
- User presses Alt → `привет` (back to corrected)

**Scenario B - Auto-correction didn't trigger:**
- System kept `ghbdtn`
- User presses Alt → `привет` (Russian)
- User presses Alt → `גהבדתנ` (Hebrew)
- User presses Alt → `ghbdtn` (back to original)

## Definition of Done

- [ ] **CorrectionHistory Enhancement**:
  - Track `originalText`, `correctedText`, `wasAutomatic` for last N words
  - Store ordered list of alternative interpretations

- [ ] **Alt Key Handler** (`EventMonitor.swift`):
  - Detect Alt key release (not press, to avoid conflicts)
  - Call `cycleCorrection()` on CorrectionEngine

- [ ] **Cycling Logic** (`CorrectionEngine.swift`):
  - `func cycleCorrection(for lastWord: String) -> String?`
  - Maintain cycling state (index into alternatives)
  - Reset cycling state on new word typed

- [ ] **Alternatives Ordering**:
  - Based on LanguageHypothesis scores from last detection
  - Or based on user's language profile preferences

## Files to Modify

- `OMFK/Sources/Engine/CorrectionEngine.swift`
- `OMFK/Sources/Engine/EventMonitor.swift`
- `OMFK/Sources/Core/ConfidenceRouter.swift` (return all hypotheses with scores)

## Dependencies

- Ticket 17 (CoreML classifier)
- Ticket 19 (testing to verify cycling works)

## Priority

**P1 — HIGH** — Critical for user experience when auto-correction fails.
