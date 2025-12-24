# Ticket 27: Fix Alt Hotkey Behavior — Unified Cycling for All Correction Modes

## Problem Statement

The Alt hotkey currently has inconsistent behavior across different correction scenarios:

1. **Bug 1: Cycling doesn't work after auto-correction** — When auto-correction triggers (space after wrong-layout word), pressing Alt does nothing. Cycling only works after manual hotkey correction.

2. **Bug 2: Wrong cycling order** — Alternatives are presented in arbitrary order instead of user-friendly sequence (undo first, then alternatives).

3. **Bug 3: Option+Shift exists but shouldn't** — We want a single hotkey (Alt/Option) with context-aware behavior, not multiple hotkey combinations.

## Root Cause Analysis

### Bug 1: Missing cyclingState after auto-correction
- `processBufferContent()` calls `engine.correctText()` which does NOT initialize `cyclingState`
- `correctLastWord()` (manual hotkey) DOES initialize `cyclingState`
- Result: After auto-correction, `engine.hasCyclingState()` returns false, so Alt press is ignored

### Bug 2: Arbitrary alternative order
- `correctLastWord()` builds alternatives in this order: original → smart → all conversions sorted by score
- Expected order depends on context (auto-correction vs manual correction)

### Bug 3: Dual hotkey system
- `flagsChanged` handler checks for both `.option` and `[.option, .shift]`
- Should be unified into single `.option` with context-aware behavior

## Expected Behavior

### Three Operating Modes (Single Alt Hotkey)

| Mode | Trigger Condition | Cycling Order |
|------|-------------------|---------------|
| 1. Undo auto-correction | Alt pressed within 3s after auto-correction | original → lang3 → original → auto-corrected → lang3 → ... |
| 2. Manual buffer correction | Alt pressed with no selection, buffer has content | smart → lang1 → lang2 → original → smart → ... |
| 3. Manual selection correction | Alt pressed with text selected | smart(per-word) → whole→lang1 → whole→lang2 → original → ... |

### Detailed Cycling Sequences

**Mode 1 (After auto-correction `ghbdtn` → `привет `):**
1. Alt #1 → `ghbdtn ` (undo — return to original)
2. Alt #2 → `גהבדתנ ` (convert to 3rd language if user has Hebrew)
3. Alt #3 → `ghbdtn ` (back to original)
4. Alt #4 → `привет ` (back to auto-corrected)
5. Alt #5 → `גהבדתנ ` (3rd language again)
6. ...cycles through [original, auto-corrected, lang3]

**Mode 2 (Manual correction of buffer content):**
1. Alt #1 → smart correction (best guess per language detection)
2. Alt #2 → whole text → Russian
3. Alt #3 → whole text → Hebrew  
4. Alt #4 → original (undo all)
5. ...cycles through [smart, ru, he, original]

**Mode 3 (Manual correction of selected text):**
1. Alt #1 → smart per-word correction (each word to its best language)
2. Alt #2 → whole selection → Russian
3. Alt #3 → whole selection → Hebrew
4. Alt #4 → original selection (undo all)
5. ...cycles through [smart-per-word, whole→ru, whole→he, original]

---

## Implementation Strategies

### Strategy A: Minimal Fix — Add cyclingState to auto-correction

**Approach:** Modify `processBufferContent()` to initialize `cyclingState` after auto-correction, similar to `correctLastWord()`.

**Changes:**
1. In `CorrectionEngine.correctText()`, build and store `cyclingState` with alternatives
2. Ensure `lastCorrectedLength` and `lastCorrectedText` are set in `EventMonitor.processBufferContent()`

**Pros:**
- Minimal code changes (~20 lines)
- Low risk of breaking existing functionality
- Fast to implement (1-2 hours)

**Cons:**
- Doesn't fix cycling order (Bug 2)
- Doesn't remove Option+Shift (Bug 3)
- Partial solution

**Risk:** Low
**Effort:** Low (1-2 hours)

---

### Strategy B: Refactor CyclingState with Mode-Aware Ordering

**Approach:** Create different `CyclingState` configurations based on correction mode, with appropriate alternative ordering for each.

**Changes:**
1. Add `CyclingMode` enum: `.undoAuto`, `.manualBuffer`, `.manualSelection`
2. Modify `CyclingState` to include mode and generate alternatives in correct order
3. Update `correctText()` and `correctLastWord()` to pass mode
4. Reorder alternatives based on mode:
   - `.undoAuto`: [original, lang3, autoCorrected] 
   - `.manualBuffer`: [smart, lang1, lang2, original]
   - `.manualSelection`: [smartPerWord, wholeLang1, wholeLang2, original]

**Pros:**
- Fixes Bug 1 and Bug 2
- Clean separation of concerns
- Extensible for future modes

**Cons:**
- More complex than Strategy A
- Requires careful testing of all three modes
- Doesn't address Bug 3 (Option+Shift)

**Risk:** Medium
**Effort:** Medium (4-6 hours)

---

### Strategy C: Unified Hotkey Handler with Context Detection

**Approach:** Remove Option+Shift handling, make single Alt hotkey detect context automatically.

**Changes:**
1. Remove `[.option, .shift]` branch from `flagsChanged` handler
2. In Alt handler, detect context:
   - If `hasCyclingState() && timeSinceLastCorrection < 3s` → Mode 1 (undo auto)
   - Else if `hasSelection()` → Mode 3 (selection)
   - Else if `!buffer.isEmpty` → Mode 2 (buffer)
3. Each mode initializes appropriate `CyclingState`

**Pros:**
- Fixes all three bugs
- Single hotkey, simpler UX
- Context-aware behavior feels natural

**Cons:**
- Larger refactor
- Selection detection adds latency (~50ms for AX query)
- Edge cases: what if buffer has content AND text is selected?

**Risk:** Medium-High
**Effort:** Medium (4-6 hours)

---

### Strategy D: State Machine for Correction Flow

**Approach:** Implement explicit state machine to track correction state and determine hotkey behavior.

**Changes:**
1. Create `CorrectionFlowState` enum:
   ```swift
   enum CorrectionFlowState {
       case idle
       case afterAutoCorrection(original: String, corrected: String, timestamp: Date)
       case afterManualCorrection(alternatives: [String], currentIndex: Int)
       case cycling(state: CyclingState)
   }
   ```
2. Transitions:
   - `idle` + space → `afterAutoCorrection`
   - `afterAutoCorrection` + Alt → `cycling`
   - `idle` + Alt → `afterManualCorrection` → `cycling`
   - `cycling` + Alt → next alternative
   - `cycling` + any other key → `idle`
3. Single Alt handler queries state machine for action

**Pros:**
- Explicit, testable state transitions
- Easy to reason about behavior
- Handles edge cases explicitly

**Cons:**
- Significant refactor
- More code to maintain
- May be over-engineered for current needs

**Risk:** Medium
**Effort:** High (8-12 hours)

---

### Strategy E: Hybrid — Minimal Fix + Unified Hotkey

**Approach:** Combine Strategy A (quick fix for Bug 1) with Strategy C (unified hotkey).

**Changes:**
1. **Phase 1:** Add `cyclingState` initialization to `processBufferContent()` (Strategy A)
2. **Phase 2:** Remove Option+Shift, add context detection to Alt handler (Strategy C)
3. **Phase 3:** Adjust cycling order based on detected context (Strategy B elements)

**Pros:**
- Incremental approach — can ship Phase 1 quickly
- Fixes all bugs by Phase 3
- Lower risk than full refactor

**Cons:**
- Multiple phases means multiple PRs
- Intermediate states may have inconsistent behavior

**Risk:** Low-Medium
**Effort:** Medium (6-8 hours total, split across phases)

---

## Recommendation

**Recommended: Strategy E (Hybrid)**

Rationale:
1. **Phase 1** can be shipped immediately to fix the most critical bug (cycling after auto-correction)
2. **Phase 2** simplifies UX by removing Option+Shift
3. **Phase 3** polishes the cycling order

This approach aligns with best practices:
- Incremental delivery
- Low risk per phase
- Each phase is independently testable

---

## Implementation Plan

### Phase 1: Enable cycling after auto-correction (Bug 1)

1. Modify `CorrectionEngine.correctText()`:
   ```swift
   func correctText(_ text: String, expectedLayout: Language?) async -> String? {
       // ... existing correction logic ...
       
       // NEW: Initialize cycling state for undo capability
       if let corrected = correctedResult {
           let alternatives = [
               CyclingState.Alternative(text: text, hypothesis: nil),  // Original (undo)
               CyclingState.Alternative(text: corrected, hypothesis: targetHypothesis)
           ]
           // Add 3rd language alternative if available
           if let thirdLang = getThirdLanguage(excluding: [sourceLanguage, targetLanguage]) {
               if let thirdAlt = convertTo(text, language: thirdLang) {
                   alternatives.append(CyclingState.Alternative(text: thirdAlt, hypothesis: thirdLang.hypothesis))
               }
           }
           cyclingState = CyclingState(
               originalText: text,
               alternatives: alternatives,
               currentIndex: 1,  // Start at corrected (index 1), Alt goes to original (index 0)
               wasAutomatic: true,
               // ...
           )
       }
       return correctedResult
   }
   ```

2. Ensure `EventMonitor.processBufferContent()` sets `lastCorrectedLength` and `lastCorrectedText`

### Phase 2: Unify hotkey to single Alt

1. Remove Option+Shift handling:
   ```swift
   // REMOVE this branch:
   // if flags == [.option, .shift] { ... }
   ```

2. Update Alt handler with context detection:
   ```swift
   if flags == .option {
       let hasSelection = getSelectedTextViaAccessibility()?.isEmpty == false
       let hasRecentCorrection = hasCyclingState && timeSinceLastCorrection < 3.0
       
       if hasRecentCorrection {
           // Mode 1: Undo/cycle auto-correction
           await handleCycling()
       } else if hasSelection {
           // Mode 3: Correct selection
           await handleSelectionCorrection()
       } else if !buffer.isEmpty {
           // Mode 2: Correct buffer
           await handleBufferCorrection()
       }
   }
   ```

### Phase 3: Fix cycling order (Bug 2)

1. Adjust alternative ordering based on `wasAutomatic` flag in `CyclingState`
2. For auto-correction: [original, lang3, corrected]
3. For manual: [smart, lang1, lang2, original]

---

## Testing Requirements

### Unit Tests
- `CorrectionEngineTests.testCyclingStateAfterAutoCorrection()`
- `CorrectionEngineTests.testCyclingOrderForAutoCorrection()`
- `CorrectionEngineTests.testCyclingOrderForManualCorrection()`

### E2E Tests (Manual or Automated)
1. **Auto-correction + undo:**
   - Type `ghbdtn` + space → `привет `
   - Press Alt → `ghbdtn `
   - Press Alt → `גהבדתנ ` (if Hebrew enabled)
   - Press Alt → `ghbdtn `

2. **Manual buffer correction:**
   - Type `ghbdtn` (no space)
   - Press Alt → smart correction
   - Press Alt → next alternative
   - Press Alt x N → cycles back to original

3. **Selection correction:**
   - Type mixed text, select it
   - Press Alt → smart per-word correction
   - Press Alt → whole text to lang1
   - Press Alt x N → cycles back to original

4. **No Option+Shift:**
   - Press Option+Shift → nothing happens (or same as Option alone)

---

## Acceptance Criteria

- [ ] Alt works after auto-correction (space trigger)
- [ ] First Alt after auto-correction returns to original text (undo)
- [ ] Cycling order is predictable and user-friendly
- [ ] Option+Shift is removed or behaves same as Option
- [ ] All three modes work correctly
- [ ] No regression in existing correction functionality
- [ ] E2E tests pass

---

## References

- `EventMonitor.swift`: `processBufferContent()`, `handleHotkeyPress()`, `flagsChanged` handler
- `CorrectionEngine.swift`: `correctText()`, `correctLastWord()`, `CyclingState`
- `.sdd/architect.md`: Architecture decisions
- `.sdd/best_practices.md`: Testing and implementation guidelines

---

## Implementation Progress

### Completed Changes

1. **Added `lastCorrectionTime = Date()` in `processBufferContent()`** — Enables cycling detection after auto-correction
2. **Removed Option+Shift handling** — Unified to single Option hotkey
3. **Removed `shiftWasHeldWithOption` variable** — No longer needed
4. **Simplified `handleHotkeyPress()`** — Removed `convertPhrase` parameter, always uses selection/buffer

### Files Modified
- `OMFK/Sources/Engine/EventMonitor.swift`

### Build Status
- ✅ Compiles successfully

---

## Testing Progress

### Test Framework Created
- `scripts/omfk_test_framework.py` — Python framework with:
  - CGEvent-based keyboard input (keycode-based, layout-independent)
  - Accessibility API for reading text from UI elements
  - Screenshot capture
  - OMFK log parsing

### Test Execution Log

#### Attempt 1: AppleScript keystroke
- **Problem**: AppleScript `keystroke` uses current layout, typed `aaadaa` instead of `ghbdtn`
- **Result**: FAIL

#### Attempt 2: CGEvent keycodes
- **Problem**: Focus returned to Terminal after subprocess calls, text typed in Terminal
- **Result**: FAIL

#### Attempt 3: Added TextEdit activation before typing
- **Problem**: Text typed as `привет` (Russian layout active), not `ghbdtn`
- **Problem**: OMFK logs empty — events not captured
- **Result**: PARTIAL — text goes to TextEdit but wrong layout

#### Attempt 4: (NEXT)
- **TODO**: Enable OMFK debug logging with `OMFK_DEBUG_LOG=1`
- **TODO**: Fix layout switching (Ctrl+Space may not work)
- **TODO**: Screenshot only TextEdit window, not full screen

### Hypotheses to Test

| # | Hypothesis | Status | Result |
|---|------------|--------|--------|
| 1 | CGEvent not captured by OMFK when sent programmatically | TESTED | Works fine |
| 2 | Layout switch via Ctrl+Space not working | TESTED | Need Option+Space |
| 3 | Need to use `CGEventSourceCreate` with proper source state | NOT NEEDED | — |
| 4 | OMFK needs `OMFK_DEBUG_LOG=1` env var for logging | CONFIRMED | Required |
| 5 | Cycling state not created when no correction needed | FIXED | Added cycling state creation |
| 6 | lastCorrectedText not saved when no correction | FIXED | Now saved |

### Test Results (Latest)

**Test: Cycling after typing "correct" text (no auto-correction needed)**
- Input: `привет` (typed in Russian layout)
- Alt #1 → `ghbdtn` (English)
- Alt #2 → `גהבדתנ` (Hebrew)
- Alt #3 → `привет` (back to original)
- **Result: ✅ PASS**

### Next Steps

1. ~~Restart OMFK with `OMFK_DEBUG_LOG=1`~~ ✅
2. ~~Update screenshot to capture only TextEdit window~~ ✅
3. ~~Verify layout is English before typing~~ (not critical - works with any layout)
4. ~~Check if OMFK sees CGEvent events~~ ✅
5. ~~Fix cycling state creation for "correct" text~~ ✅
6. Test with actual wrong-layout input (ghbdtn → привет → cycling)
7. Commit and push changes

---

## Manual Test Checklist

If automated testing fails, use manual testing:

```
1. Open TextEdit, new document
2. Switch to English layout
3. Type: ghbdtn
4. Press Space → should auto-correct to "привет "
5. Press Option → should cycle to "ghbdtn "
6. Press Option → should cycle to next alternative
7. Check ~/.omfk/debug.log for entries
```
