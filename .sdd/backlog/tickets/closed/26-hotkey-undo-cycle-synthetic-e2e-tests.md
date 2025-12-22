# Ticket 26: Synthetic E2E Tests for Hotkey Undo/Cycle + Forced Layout Switch (Text Integrity)

## Priority
CRITICAL — current hotkey flow can corrupt text: delete too much (including correctly typed text), insert garbage (`<0x7f>`), or apply wrong replacement lengths.

## Status
Open

## Summary
We need automated tests that simulate a user typing in different layouts, then:
1) applying **manual correction hotkey** (word mode and phrase mode),
2) repeatedly pressing the hotkey to **cycle/undo** alternatives,
3) verifying **forced input source switching** behavior,
4) verifying the final resulting text stream is correct and that **no extra deletions** or **control characters** (e.g. 0x7F DEL) appear.

Currently this is hard to test manually and regressions are frequent. This ticket adds a deterministic synthetic harness around the existing correction pipeline.

---

## Context / Symptoms

Observed issues:
- Repeated hotkey presses cause “barдак”:
  - deletion length exceeds the intended segment (deletes previously correct text),
  - inserts non-printable characters (e.g. `<0x7f>`),
  - corrupts whitespace or punctuation,
  - final text differs from expected “cycle” state.

Suspected sources:
- `EventMonitor.replaceText(with:originalLength:)` being fed a wrong `originalLength` (especially for phrase mode and/or when trailing space is present).
- Mismatch between “what was corrected” and “what we delete next” during cycling (`lastCorrectedLength` / `phraseBuffer.count` / buffer trimming).
- Timing/race between event capture buffers and main-actor correction tasks.
- Handling of delete/backspace events: if the replacement is implemented via posting key events, some apps may interpret them differently.

We must add tests that validate the *string-level side effects* without depending on OS event taps.

---

## Objective

Add **synthetic E2E tests** that:
- simulate typed text and hotkey presses,
- run through `CorrectionEngine` and cycling state,
- validate the produced **replacement operations** and resulting text,
- ensure no control characters are introduced and correct segments are replaced.

---

## Definition of Done (DoD)

### A) Test Harness
- [ ] Add a `TextBufferSimulator` (test-only) that models:
  - a current string buffer,
  - a cursor at end,
  - an operation `replaceLast(n: Int, with: String)` that mimics what the app does (`delete n chars then insert new`).
- [ ] Add a test-only “adapter” that exposes what `EventMonitor` *would* do:
  - When `CorrectionEngine.correctText` returns a correction, compute the expected `originalLength` and apply to simulator.
  - For hotkey correction: use the same alternative/cycling logic as `CorrectionEngine.correctLastWord` / `cycleCorrection`.

### B) Hotkey scenarios (word mode)
- [ ] For each language pair (EN/RU/HE), simulate:
  - correct word typed normally (should remain intact),
  - wrong-layout word typed, then hotkey correction applies,
  - repeated hotkey presses cycles to:
    1) next alternative
    2) undo (original)
    3) back to corrected
  - assert the simulator buffer after each press.

### C) Hotkey scenarios (phrase mode)
- [ ] Simulate phrase buffer of multiple words + punctuation, including mixed correct+wrong segments:
  - Example: `"ok " + <wrong-layout-word> + " test"` etc.
- [ ] Apply phrase hotkey correction and verify:
  - only the intended phrase segment is replaced,
  - text typed earlier “correctly” remains unchanged.

### D) Forced input source switching
- [ ] Verify that after manual correction the engine reports a target language suitable for switching.
- [ ] Do **not** call HIToolbox in tests; instead verify “intent to switch” via an injected interface:
  - Introduce a protocol (e.g. `InputSourceSwitching`) with `switchTo(language:)`.
  - In prod it uses `InputSourceManager.shared`, in tests a mock captures calls.
- [ ] Assert switch calls:
  - called for manual correction,
  - not called when no correction,
  - does not oscillate unexpectedly during cycling.

### E) Control character guardrail
- [ ] Add assertions that the resulting output string never contains:
  - ASCII DEL (0x7F)
  - other C0 controls except newline/tab if explicitly allowed.
- [ ] If any appear, test fails with a clear diff.

### F) Reliability
- [ ] Tests must be deterministic:
  - fixed seed for synthetic text selection,
  - no timing-based sleeps,
  - no dependence on OS keyboard layout availability.

---

## Proposed File Changes

### New files (tests)
- `OMFK/Tests/HotkeyTextIntegrityTests.swift`
  - main suite for the scenarios above.
- Optionally: `OMFK/Tests/Support/TextBufferSimulator.swift`
  - small deterministic helper.

### Production changes (minimal, to enable testing)
- `OMFK/Sources/Core/InputSourceManager.swift`
  - add protocol wrapper if not present.
- `OMFK/Sources/Engine/CorrectionEngine.swift`
  - expose cycling operations in a testable way (or keep internal but add small hooks).
- `OMFK/Sources/Engine/EventMonitor.swift`
  - avoid computing deletion lengths in multiple places; unify via a helper that can be unit-tested.

---

## Test Design Details

### 1) “Operation-based” validation (recommended)
Instead of trying to reproduce CGEventTap, validate the sequence of **text operations**:
- initial buffer content
- operation: delete N chars
- operation: insert string S
- resulting buffer string

This approach isolates correctness bugs:
- wrong deletion length,
- wrong inserted string,
- unexpected characters.

### 2) Coverage matrix
Languages: EN, RU, HE
Modes:
- word hotkey (Option)
- phrase hotkey (Shift+Option)
Actions:
- apply correction
- cycle 1
- cycle 2
- undo
Total:
- at least 3–5 representative cases per combination (seeded).

### 3) Regression examples to encode
Add explicit regression fixtures for:
- “deletes too much including prior correct word”
- “inserts <0x7f>”
- “trailing space double-count”

---

## Validation Commands
- `swift test --filter HotkeyTextIntegrityTests`
- full suite: `swift test`

---

## Risks / Notes
- Some corruption may be app-specific due to OS event posting; these tests validate the *string-level algorithmic contract* and replacement lengths, which is the most common root cause.
- If corruption persists in real apps despite passing tests, follow-up ticket should add a small integration harness around `replaceText` with an injectable “event sink” to capture posted events.

