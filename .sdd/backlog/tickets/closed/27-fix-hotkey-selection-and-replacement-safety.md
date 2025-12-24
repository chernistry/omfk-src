# Ticket 27: Fix Hotkey Selection & Replacement Safety (Option / Shift+Option)

## Objective
Make manual hotkey correction (Option tap and Shift+Option tap) **safe and predictable**:
- Never delete more text than intended.
- Correct only the **actual selection** when selection exists.
- If there is no selection, correct only the **explicitly targeted** fragment (last typed token / bounded phrase).
- Avoid UX regressions (latency, clipboard corruption, inconsistent behavior across apps).

This ticket is aligned with `.sdd/architect.md`:
- privacy-first (no keyboard logging, no clipboard abuse),
- deterministic guardrails (validate before replacing),
- low latency and predictable behavior.

## Current Symptoms (as reported)
1. **Uncontrolled deletion on Option hotkey**
   - Deletes more than the last word; sometimes multiple lines.
   - App-dependent behavior (e.g., Sublime Text can lose the entire last line).
   - Ctrl+Z often does not restore the deleted content.
2. **Selected-text bug**
   - With a selection, Option hotkey converts more than the selection (often the whole line).
3. **Loss of original text / length mismatch**
   - Undo/cycle does not restore exact original; whitespace and characters can be lost.

## Historical Root Causes (what was happening, now fixed)
The hotkey flow is centered in:
- `OMFK/Sources/Engine/EventMonitor.swift`

The core failure modes were:
1. Treating `Cmd+C` as a “selection detector”.
   - In some apps, `Cmd+C` with no selection copies the whole line → OMFK would operate on the wrong target.
2. Deleting by `Backspace × N` without being selection-aware.
   - If text is selected, the first backspace deletes the selection and remaining backspaces delete extra content before it.
3. Fallback selection (`Option+Shift+Left`) without a reliable “transaction end”.
   - If selection capture/replacement fails, leaving the selection highlighted creates a visible UX break and can cause subsequent presses to expand selection.

The current implementation fixes these by making manual hotkey corrections selection-only and using clipboard only after a selection is confirmed/created, with full restore and best-effort rollback.

## Why the Original Prompt Would Likely Make UX Worse
Original prompt proposes “intelligent tokenization” and “token history” as a primary fix.

This likely **does not address the root causes** and can degrade UX:
- The primary failures are **selection detection** and **selection-aware replacement**, not word boundary detection.
- Tokenization cannot guarantee safety across apps when the app’s own selection semantics and undo stack differ.
- Storing a long “token history” increases privacy surface area and complexity (risk of accidental retention), contradicting privacy-first constraints unless carefully bounded and cleared.
- “100% preservation” is not achievable via keystroke deletion + retyping across arbitrary apps unless replacement is selection-aware and bounded.

Conclusion: The prompt should be reframed around **safe selection acquisition** and **replacement transactions**, not tokenization.

---

## Hypotheses (ranked) + Fix Ideas

### H1 (Very likely): Clipboard probing copies entire line in some apps
**Mechanism**: `Cmd+C` with no selection copies line; OMFK then deletes `rawText.count`.
**Fix**:
- Do not use `Cmd+C` as a “selection detector” unless we have positive evidence that a selection exists.
- Prefer Accessibility selection APIs; otherwise fall back to “buffer-only safe mode”.

### H2 (Very likely): Replacement deletes selection + extra due to N-backspaces
**Mechanism**: Selected text is deleted by the first backspace, remaining backspaces delete before selection.
**Fix**:
- Make replacement **selection-aware**:
  - If selection exists: replace via `type` (over selection) or `paste`, with **0** repeated backspaces.
  - If no selection: delete only a known-safe backward count (from buffer or bounded capture).

### H3 (Likely): “Select word backward” uses app-dependent semantics
**Mechanism**: `Option+Shift+Left` can select more/less than expected depending on editor and caret context.
**Fix**:
- Treat this path as “best-effort” and still ensure replacement is selection-aware.
- If selection cannot be confirmed, fail safe (do nothing) rather than guess.

### H4 (Medium): Buffer != actual inserted text (dead keys, IME, app transforms)
**Mechanism**: Event-derived `characters` may not match what the app inserted.
**Fix**:
- Use buffer only if “fresh” and limited to conservative contexts (single word typed right before the hotkey).
- Optionally add a user-facing setting: “Hotkey without selection uses last typed word only (safe)”.

### H5 (Medium): Phrase mode can be unbounded and multi-line
**Mechanism**: `phraseBuffer` is appended continuously and not safely bounded.
**Fix**:
- Bound phrase buffer by:
  - resetting on newline/enter, app focus change, mouse click,
  - limiting to last N characters (e.g., 256–512),
  - or prefer “convert selected text / current line” via AX instead of raw buffer.

### H6 (Medium): Undo friendliness is poor with backspace loops
**Mechanism**: Many apps treat injected backspaces/typing as multiple operations; undo may not restore.
**Fix**:
- Prefer “replace by paste” (Cmd+V) when possible, because many apps group it as one undo step.
- Consider AX replacement as primary when supported (also often undoable as a single step), with fallback.

---

## Implemented Solution (current, safety-first hybrid)

Implemented primarily in:
- `OMFK/Sources/Engine/EventMonitor.swift`

### Manual hotkey now operates on confirmed selections only
- Manual mode never deletes by “`Backspace × N`” (this was the root cause of over-delete).
- Manual correction is a **selection transaction** when a selection exists, with a **fresh-buffer fallback** when no selection is available.

### WORD mode (`⌥ Option` tap)
Priority order (fail-safe at each step):
1. If there is a valid cycling state and we know the exact `lastInsertedText`, select it **behind the caret via AX** only if the text at that range matches exactly (self-check), then replace.
2. If there is an explicit user selection and AX can confirm it (range length > 0), replace selection via AX.
3. If no selection but a **fresh buffer** (<~2s, capped length) exists, replace it with a bounded backspace plan (`replaceRecentlyTyped` uses AX-behind-caret first, else capped backspace).
4. Otherwise:
   - create a selection via `Option+Shift+Left` (previous word),
   - read the selection:
     - prefer AX (range + selected text),
     - fallback to `Cmd+C` **only because a selection was just created** (never as a selection detector),
   - refuse “non-token” selections (whitespace/newlines) to prevent accidental line/phrase wipes,
   - replace selection:
     - prefer AX `kAXSelectedTextAttribute`,
     - fallback to paste (`Cmd+V`) with full pasteboard snapshot/restore,
   - best-effort verification + rollback (`Cmd+Z`) on mismatch,
   - collapse selection back to caret position.

### PHRASE mode (`⇧ Shift + ⌥ Option` tap)
- Safety-first: requires a real, AX-confirmed selection.
- If AX can’t confirm the selection, OMFK does **no-op** (prevents “convert whole line” style accidents).

### Auto-correction replacement path (space/word boundary)
- Prefer AX “select behind caret if it matches expected buffer content” → replace (self-check).
- Fallback remains: bounded `Backspace × N` + type Unicode (hard-capped budget).

### Why this fixes the bug class
- “Deletes too much” can only happen when we delete without a verified target range.
- Manual mode is now “replace selection” only: even if the selection boundary is imperfect, replacement can’t spill into previous lines/words.
- Clipboard is never used as a selection detector; it’s only used as a transport once a selection is confirmed/created, and it is restored.

## Remaining Follow-ups / Risks
- Some apps expose weak AX support; clipboard fallback is best-effort and may still no-op in secure fields.
- PHRASE mode in non-AX apps intentionally no-ops; extending it safely requires additional guards and is a separate, higher-risk change.

---

## Updated Prompt (for implementing/maintaining this subsystem)

### Task: Fix hotkey correction safety and UX (Option / Shift+Option)

**Problem**: Manual correction must never corrupt user text. Over-delete happens when we delete by length (backspace loops) or when we “detect selection” via clipboard in apps that copy a whole line with no selection.

**Goal**: Implement a selection-transaction approach with strict safety invariants:
1) Manual hotkey must replace **only a confirmed selection** (AX-confirmed selection, or a selection created by OMFK via keyboard).
2) Never use `Cmd+C` as a selection detector. Clipboard can only be used after we know a selection exists, and it must be fully restored.
3) If the target cannot be confirmed, **do nothing** and leave the user’s text untouched (but also don’t leave a dangling selection highlight).
4) Add best-effort self-check and rollback (`Cmd+Z`) when verification is possible.

**Implementation constraints**:
- Keep it <50ms typical.
- No persistent logging of user text.
- Prefer AX selection/range APIs; use pasteboard only as a scoped fallback.
