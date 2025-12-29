# Ticket 29: Extended Alt Cycling (Third Language on Second Round)

## Problem

Current Alt cycling only shows 2 alternatives:
1. Original text (as typed)
2. Primary conversion (e.g., RU→EN or EN→RU)

The third language (Hebrew) is **never shown** unless the user has a very specific layout configuration. This forces users who occasionally need Hebrew to manually switch layouts instead of using the convenient Alt cycling.

**Evidence from tests:**
```
test_alt_full_cycle_verification: ✓ 2 unique states
```
Expected: 3 states for trilingual setup (RU, EN, HE).

## Current Alt Behavior (for context)

Alt cycling works for the **last corrected word** within a **3-second window** after correction:
- After auto-correction OR after typing (even without correction), `lastCorrectedText` is saved
- User can press Alt within 3 seconds to cycle through alternatives
- Typing new characters resets the cycling state
- Works even after space/punctuation (as long as within 3-second window)

**This is good UX** — user can type a word, press space, see the correction, then press Alt to undo if needed.

## Known Bug: Sublime Text Cycling Issue

**BUG:** In Sublime Text, second Alt press sometimes **inserts** the alternative text instead of **replacing** the current word.

**Expected:** `привет` → Alt → `ghbdtn` (replaces)
**Actual:** `привет` → Alt → `приветghbdtn` (inserts after)

**Hypothesis:** Sublime Text handles text selection/deletion differently. The `replaceText` function may not be selecting the correct range before typing the replacement.

**To investigate:**
- Check if `lastCorrectedLength` matches actual text length in Sublime
- Check if Sublime has special handling for programmatic text replacement
- May need app-specific workaround

## User Story

As a trilingual user (RU/EN/HE), I want Alt cycling to eventually show all three language options, so that I can quickly access any language without switching system layouts.

## Current Behavior

```
Type: "ghbdtn" (привет on wrong layout)
Auto-correct: "привет"

Alt press 1: "ghbdtn" (original)
Alt press 2: "привет" (back to corrected)
Alt press 3: "ghbdtn" (original again)
...cycle repeats with only 2 states
```

Hebrew alternative is never shown.

## Proposed Behavior

**First round (quick access, 90% of cases):**
```
Alt press 1: "ghbdtn" (original)
Alt press 2: "привет" (primary conversion)
```

**Second round (if user keeps pressing Alt):**
```
Alt press 3: "פריבטנ" (Hebrew alternative) ← NEW
Alt press 4: "ghbdtn" (original)
Alt press 5: "привет" (primary)
Alt press 6: "פריבטנ" (Hebrew)
...full 3-state cycle
```

## Design Rationale

1. **First round is fast** — Most users only need original↔corrected toggle
2. **Second round adds depth** — Power users can access all languages
3. **No UI clutter** — Third language only appears if user explicitly asks for more options
4. **Discoverable** — Users naturally discover it by pressing Alt more times

## Implementation

### State Machine

```swift
enum CyclingState {
    case corrected      // Auto-corrected result
    case original       // As-typed text
    case alternative    // Third language conversion (added on round 2)
}

struct CyclingContext {
    var currentState: CyclingState
    var roundNumber: Int  // 1 = first round (2 states), 2+ = full round (3 states)
    var statesInRound: [CyclingState]
    
    mutating func advance() {
        let currentIndex = statesInRound.firstIndex(of: currentState) ?? 0
        let nextIndex = (currentIndex + 1) % statesInRound.count
        currentState = statesInRound[nextIndex]
        
        // If we completed a round and only had 2 states, expand to 3
        if nextIndex == 0 && roundNumber == 1 && statesInRound.count == 2 {
            roundNumber = 2
            statesInRound = [.corrected, .original, .alternative]
        }
    }
    
    mutating func reset() {
        currentState = .corrected
        roundNumber = 1
        statesInRound = [.corrected, .original]
    }
}
```

### Integration Points

1. **EventMonitor.handleHotkeyPress()** — Track cycling round, expand states on round 2
2. **CorrectionEngine** — Generate third-language alternative lazily (only when needed)
3. **LanguageEnsemble** — Provide hypothesis for third language

### Edge Cases

1. **Only 2 languages configured** — Never expand to round 2
2. **Third language conversion invalid** — Skip it, stay with 2 states
3. **User types after Alt** — Reset cycling context
4. **User switches apps** — Reset cycling context

## Files Affected

- `OMFK/Sources/Engine/EventMonitor.swift` — Cycling state machine
- `OMFK/Sources/Core/CorrectionEngine.swift` — Third-language generation
- `OMFK/Sources/Core/LanguageEnsemble.swift` — Alternative hypothesis

## Known Issues to Fix in This Ticket

### Issue 1: Sublime Text Insert Instead of Replace
**BUG:** In Sublime Text, second Alt press sometimes **inserts** the alternative text instead of **replacing** the current word.

**Expected:** `привет` → Alt → `ghbdtn` (replaces)
**Actual:** `привет` → Alt → `приветghbdtn` (inserts after)

**Hypothesis:** Sublime Text handles text selection/deletion differently. The `replaceText` function may not be selecting the correct range before typing the replacement.

**To investigate:**
- Check if `lastCorrectedLength` matches actual text length in Sublime
- Check if Sublime has special handling for programmatic text replacement
- May need app-specific workaround

**Test to add:** `test_sublime_text_cycling`

### Issue 2: Only 2 States in Cycle
Third language never shown — main focus of this ticket.

## Tests

1. `test_alt_first_round_two_states` — First round shows only 2 states
2. `test_alt_second_round_three_states` — Second round adds third language
3. `test_alt_round_reset_on_typing` — Typing resets to round 1
4. `test_alt_two_languages_no_expansion` — No expansion if only 2 languages
5. `test_sublime_text_cycling` — Verify cycling works in Sublime Text (no insert bug)

## Definition of Done

- [ ] First round of Alt cycling shows 2 states (original + primary)
- [ ] Second round of Alt cycling shows 3 states (+ third language)
- [ ] Cycling resets to round 1 when user types
- [ ] Third language alternative is validated before showing
- [ ] Works correctly with all layout combinations
- [ ] Tests pass for all scenarios

## Dependencies

- None

## Blocked By

- None (can be implemented independently)

## Priority

Medium — Nice UX improvement, not blocking core functionality
