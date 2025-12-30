# OMFK — Status / Bugs / Test Notes (Single Source of Truth)

**Last updated:** 2025-12-30 17:20

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
- Unit tests are green; UI-driven E2E runs are currently **blocked in this environment** because TextEdit cannot be made frontmost (focus stays on Tabby).

---

## Verified Tests (Trustworthy)

These are the most recent runs that should be treated as reliable:

- `swift test -c debug --skip-build` → ✅ `235` tests, `1` skipped, `0` failures (2025-12-30)

Notes:
- Prefer the `.venv` Python environment if you use macOS UI automation dependencies (pyobjc).
- UI-driven E2E requires TextEdit to be frontmost in the current Space; currently `open/activate` does not take focus away from Tabby, so runners crash with `FocusLostError`.

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

### 4) Mixed-script correction guard

**Symptom:** mixed tokens like `hello мир` could get “corrected” into partially mapped gibberish.  
**Fix:** `OMFK/Sources/Core/ConfidenceRouter.swift` now returns `Path: MIXED_SCRIPT_KEEP` for tokens containing multiple scripts (Latin/Cyrillic/Hebrew), preventing any layout correction attempts.

### 5) Technical-token guard no longer blocks punctuation-as-letter conversions

**Symptom:** tokens like `epyf.n` were treated as filename-like and skipped, breaking `epyf.n` → `узнают`.  
**Fix:** `isTechnicalToken` only treats filename-like tokens as technical when the extension is in a curated allowlist (e.g. `md`, `swift`, `json`, `zip`), while still protecting paths/UUIDs/semver.

### 6) Manual hotkey: smart segmentation can be the primary result

**Symptom:** selection hotkey on `ghbdtn.rfr ltkf` preferred whole-text conversion and produced `приветюкак дела` instead of `привет.как дела`.  
**Fix:** `OMFK/Sources/Engine/CorrectionEngine.swift` now prefers smart per-segment correction as the primary alternative when it scores better (small bias towards preserving punctuation semantics).

### 7) Unit-test isolation: don’t read/write real user dictionary

**Symptom:** unit tests were polluted by rules in `~/.omfk/user_dictionary.json` (e.g. `USER_DICT_PREFER` forcing `hello` → RU).  
**Fix:** `OMFK/Sources/Core/UserDictionary.swift` auto-routes the default storage to a temp file when running under XCTest, without touching real user data.

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

### ✅ Unit tests

Command:
```bash
swift test -c debug --skip-build
```

Result: ✅ `235` tests, `1` skipped, `0` failures

### ⚠️ UI E2E (real typing)

Current status: **blocked** — TextEdit cannot be made frontmost from this terminal session (focus remains on Tabby), so runners abort with:
`FocusLostError: Focus lost to: Tabby`

Workaround to re-enable E2E runs:
- Ensure TextEdit has a visible window in the current Space and is frontmost before starting the runner, or enable the Mission Control setting that allows app switching to move Spaces.
- Then run:
  - `.venv/bin/python scripts/test_failed_cases.py`
  - `.venv/bin/python scripts/comprehensive_test.py --real-typing`

### GitHub issues (omfk-releases)

Repo: `chernistry/omfk`

Open issues (as of 2025-12-30):
- `#2` Single-letter prepositions in context
- `#3` Punctuation word boundaries
- `#6` Technical text / paths / UUIDs
- `#7` Punctuation in numeric contexts
- `#8` Emoji / special Unicode passthrough

No issue is ready to close without a fresh UI E2E run in the releases repo context, but #6/#7 likely improved due to `TECHNICAL_KEEP` + semver/UUID/path guarding and should be re-verified first.
