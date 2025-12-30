# OMFK — Status / Bugs / Test Notes (Single Source of Truth)

**Last updated:** 2025-12-30

This file replaces and supersedes:
- `.sdd/backlog/SESSION_NOTES.md` (obsolete)
- `.sdd/backlog/REMAINING_ISSUES.md` (obsolete)
- `.sdd/backlog/wrongs.md` (obsolete)

If you’re starting a new agent session, **use this file only**. Older docs contained contradictory “P0 failed” narratives that turned out to be **test-harness flakiness** (TextEdit readback/paste timing) rather than product behavior.

---

## TL;DR (Current Reality)

- Core conversions RU/EN/HE work; most of the previous “P0 broken” signal was caused by the E2E harness reading the target app too early.
- The E2E harness (`scripts/comprehensive_test.py`) was hardened to **wait for UI to settle** (polling/stabilization, focus checks, paste verification + retry).
- A real root cause for “manual hotkey alternatives missing” was fixed: `language_data.json` uses `english/russian/hebrew` while code expected `en/ru/he`, which made `languageConversions` parse empty.

---

## Verified Tests (Trustworthy)

These are the most recent runs that should be treated as reliable:

- `swift test -c debug --filter LayoutVariantFallbackTests` → ✅ pass  
  (Validates layout-variant fallback logic in unit tests.)

- `.venv/bin/python scripts/comprehensive_test.py single_words` → ✅ `21/21` pass
- `.venv/bin/python scripts/comprehensive_test.py --real-typing single_words` → ✅ `21/21` pass
- `.venv/bin/python scripts/comprehensive_test.py cycling` → ✅ `4/4` pass

Notes:
- Prefer the `.venv` Python environment if you use macOS UI automation dependencies (pyobjc).
- If you see intermittent failures, **don’t trust single-shot reads**; re-run after ensuring TextEdit is frontmost and the test waits for stabilization.

---

## What Was Actually Fixed (Root Causes)

### 1) `language_data.json` language key mismatch → empty conversions list

**Symptom:** manual hotkey/cycling produced no alternatives (or nonsense ordering), making P0 “Alt cycling” look broken in tests.  
**Cause:** config used `"english"/"russian"/"hebrew"`, but parsing expected `"en"/"ru"/"he"`, so `languageConversions` parsed empty.  
**Fix:** `OMFK/Sources/Core/LanguageDataConfig.swift` now accepts both forms and falls back to defaults if parsed conversions are empty.

### 2) Manual hotkey candidate ordering picked wrong “primary”

**Symptom:** manual hotkey could pick a surprising primary conversion (e.g. Hebrew variant winning against intended Russian).  
**Fix:** `OMFK/Sources/Engine/CorrectionEngine.swift` now chooses the **primary** conversion candidate by `fastTextScore` (plus a small bonus aligned with router hypothesis), then uses the rest for cycling.

### 3) E2E harness readback/paste flakiness (false negatives)

**Symptom:** tests reported “no change” even when UI visibly changed, especially for fast hotkey + immediate typing and for selection-based cycling.  
**Fix:** `scripts/comprehensive_test.py` now:
- waits for TextEdit to be focused before typing
- verifies paste actually happened and retries once
- polls for “changed text” and “expected result stabilized” instead of fixed sleeps
- applies the same strategy to cycling tests (don’t read too early)

---

## Known Remaining Work (Needs Re-Validation)

The items below were heavily discussed in older docs, but their *current* status may have changed after the harness + engine fixes. Treat these as **candidates to re-test**, not confirmed failures, until a fresh full-suite run is recorded here.

### P1 / UX correctness
- **Special characters passthrough**: emoji, guillemets, em-dash, currency symbols should not trigger `[no layout for: ...]` style errors; ideally convert only mappable segments.
- **Numeric contexts**: preserve punctuation inside times/dates/versions (`15:00`, `25.12.2024`, `v1.2.3`, `20%`) while still converting surrounding words.
- **Technical text protection**: avoid corrupting paths/UUIDs/filenames (`/Users/...`, `C:\\...`, `README.md`, UUID patterns).

### P2 / polish & robustness
- **Whitespace preservation**: don’t collapse/delete tabs/newlines/multiple spaces.
- **Long paragraphs**: multi-sentence text with mixed punctuation should remain stable and fully converted where appropriate.

---

## How To Run Tests (Recommended)

### Unit tests (fast, reliable)
```bash
swift test -c debug
```

### E2E (real typing) — preferred
```bash
.venv/bin/python scripts/comprehensive_test.py --real-typing
```

### Debugging logs
- Run with: `OMFK_DEBUG_LOG=1 swift run`
- Logs: `~/.omfk/debug.log`

---

## Historical Notes (Why Older Docs Were Misleading)

Older files (`SESSION_NOTES.md`, `REMAINING_ISSUES.md`, `wrongs.md`) captured real failure patterns at the time, but also included:
- “P0 fixes failed 0/10” conclusions driven by a harness that was **too fast** and sometimes read the document before the app applied conversion.
- contradictory pass rates across runs and categories, making it easy for agents to “fix” already-fixed problems or chase ghosts.

This file exists to prevent that loop: if you fix something, **record the exact command + result here**.



---

## Re-Validation Results (2025-12-30)

**Full E2E test run:** 100/161 passed (62.1%)

### ✅ FIXED Issues (Closed on GitHub)
- **Issue #1:** Comma/period inside words (k.,k. → люблю) ✅
- **Issue #4:** Alt/Option hotkey for single words ✅ (4/4 cycling tests pass)
- **Issue #5:** Layout variants (Russian Phonetic, Hebrew Mac/QWERTY) ✅ (21/21 single_words tests pass)

### ❌ CONFIRMED Bugs (Open on GitHub)

#### Issue #2: Word ending detection (9/10 context boost pass)
```
Test: у меня есть идея
Got: 'у меня есть идей'
Expected: 'у меня есть идея'
```
- `e → у` works ✅
- `bltq → идей` instead of `идея` ❌

#### Issue #3: Punctuation triggers (0/15 pass)
None of these trigger word boundary: `.` `,` `!` `?` `()` `[]` `{}` `""` `:` `;` `...` `«»` `—` `/`

#### Issue #6: File paths corrupted (0/5 pass)
- `/Users/.../omfk` → `/Users/.../щьал`
- `C:\Users\...` → `С:\Users\...`
- `README.md` → `README.צג`
- `v1.2.3` → `м1.2ю3`
- UUIDs: `d` → `в`

#### Issue #7: Punctuation in numbers (0/6 pass)
- `15:00` → `15Ж00`
- `25.12.2024` → `25ю12ю2024`
- `20%` → `20:`
- `v1.2.3` → `м1.2ю3`

#### Issue #8: Emoji and special chars (0/3 pass)
- `🙂 ghbdtn` → `[no layout for: 🙂 ghbdtn]`
- `😄` → `[no layout for: 😄]`
- `«ghbdtn»` → not converted

### Test Command for Failed Cases Only
```bash
.venv/bin/python scripts/test_failed_cases.py
```

This runs only the ~40 tests that failed in the full E2E run, saving time during development.
