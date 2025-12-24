# Ticket 28: User Dictionary + Auto-Learning (Punto-style)

## Objective
Add a **user-controlled personalization layer** that reduces repeated false positives/false negatives by learning from:
- repeated **manual corrections** of the same token, and
- repeated **undo/rejects** of automatic corrections.

Also provide a small UI to **view / edit / add** dictionary rules manually.

Must comply with `.sdd/architect.md`:
- local-only, privacy-first,
- deterministic guardrails (still validate conversions),
- low latency (<50ms), small memory footprint.

---

## User Problems This Solves

1. **Inherently ambiguous collisions** (especially Hebrew-QWERTY): the same visible token can be a valid word in the “wrong” script.
2. Users repeatedly correcting the same token manually is a strong signal that OMFK should “just do that next time”.
3. Users repeatedly undoing auto-corrections is a strong signal that OMFK should stop touching that token in that context.

---

## Desired UX / Behavior (User Flows)

### Flow A — Auto-correction happens, user rejects it (undo)
1. User types; OMFK auto-corrects a token `T` → `C`.
2. User presses hotkey once to undo (cycling to “original”).
3. OMFK treats this as **rejection** of the auto decision for `(T, app?, mode=automatic)`.
4. If the same token is rejected again (threshold configurable; default `>= 2`):
   - Add a **user dictionary rule**: “KEEP token `T` as-is in automatic mode” (optionally scoped by app).
5. Next time OMFK sees `T` in automatic mode, it short-circuits early and **does not convert**.

UX expectations:
- No prompt/confirmation.
- A subtle, non-disruptive indicator is allowed (e.g., log-only or optional HUD): “Added to user dictionary: keep ‘T’”.
- Must be reversible in settings.

### Flow B — User triggers manual correction repeatedly for the same token
1. User selects text or uses “convert last word”.
2. User presses hotkey; OMFK produces correction alternatives and applies one (or cycles).
3. If the user ends up applying the same mapping repeatedly:
   - Example: `נאה` → `nah` (English intended on Hebrew-QWERTY),
   - Example: `руддщ` → `hello` (English intended on Russian layout),
4. After N repeats (default `>= 2`), OMFK learns a **preference rule**:
   - “When input token is `T` (dominant script = Hebrew), prefer hypothesis `en_from_he`.”
   - Or “Prefer target language = English” for this token.
5. Next time OMFK sees `T` (even if it looks like a valid word), it biases strongly toward the learned target, still passing validation gates.

UX expectations:
- Manual mode is recall-first; learning from manual corrections should be enabled by default (but can be toggled).
- If the learned preference later becomes wrong, user can remove it.

### Flow C — Manual add / edit
Settings → “User Dictionary”:
- Add a rule for a token (paste or type).
- Choose behavior:
  - **Keep as-is** (never auto-correct it)
  - **Prefer English / Russian / Hebrew** (bias router/scoring)
  - **Force conversion** (advanced): always convert using specific hypothesis (`en_from_he`, `ru_from_en`, …) if validation passes
- Optional scope:
  - Global (default)
  - Per-app (bundle id)
  - Only in automatic mode / only in manual mode / both
- Controls:
  - Enable/disable learning globally
  - Clear all learned rules
  - Export/import (optional, not required for v1)

---

## Core Design

### Rule types
`UserDictionaryRule` (conceptual):
- `id` (UUID)
- `token` (stored string OR privacy-preserving hash; see below)
- `matchMode`: `exact` | `caseInsensitive` (v1)
- `scope`:
  - `bundleId` optional
  - `modes`: `[automatic, manual]`
- `action`:
  - `keepAsIs`
  - `preferLanguage(Language)`
  - `preferHypothesis(LanguageHypothesis)` (advanced)
- `evidence`:
  - `manualAppliedCount`
  - `autoRejectedCount`
  - timestamps for decay/cleanup (optional)

### Where it plugs into the pipeline
1. **Before built-in whitelist**: check user dictionary.
2. If rule says `keepAsIs`: return language/script as-is and stop correction.
3. If rule says `preferLanguage`/`preferHypothesis`:
   - add a strong score boost in `ConfidenceRouter.scoredDecision(...)`
   - and/or adjust thresholds in `UserLanguageProfile` for that token/context
   - still require validation gates before applying a correction.

### Learning signals (what counts as “manual applied” / “auto rejected”)
- **Auto rejected**:
  - When a token was auto-corrected and user cycles back to “original” as the first hotkey action (undo).
  - Must only count rejections where we can confidently link undo to that token (use existing `lastCorrectedText/length` + correction history record).
- **Manual applied**:
  - When user triggers hotkey on token `T` and ends up applying a correction whose target hypothesis is not “keep original”.
  - If user cycles multiple times and lands on a specific alternative, count that final applied mapping.

### Thresholds
Default suggestions (v1):
- Add `keepAsIs` after `autoRejectedCount >= 2` within last 14 days.
- Add `preferHypothesis` after `manualAppliedCount >= 2` within last 14 days.
- Cap learned rules (e.g., 500) with LRU eviction to avoid unbounded growth.

### Privacy considerations
User dictionary stores user-provided tokens; this is inherently sensitive.
Mitigations (v1):
- Make learning **toggleable** (on by default, but visible).
- Provide “Clear learned dictionary” and “Clear all dictionary”.
- Prefer storing only short tokens (e.g., max 48 chars) and never store multi-line content.
- Do not log stored tokens in plaintext.

Optional stronger privacy (v2):
- Store a keyed hash (HMAC) of normalized token for matching, and optionally store plaintext only for UI display (encrypted or behind an explicit “show”).

---

## Alternatives + Trade-offs (MCDM-style)

Criteria weights:
- Safety / no data loss: 5
- UX improvement: 5
- Privacy risk: 4
- Cross-app consistency: 3
- Complexity: 2
- Latency: 3

### Option A (Recommended): User dictionary overlay + simple learning thresholds
- Pros: big UX win, simple lookup, deterministic, fits current pipeline.
- Cons: stores tokens locally (privacy); needs good UX for cleanup.

### Option B: Context-only adaptive thresholds (no token storage)
- Pros: better privacy (no token list).
- Cons: weak for collision tokens (needs token identity); less “Punto-like”.

### Option C: Full per-user ML fine-tune
- Pros: can generalize.
- Cons: heavy, risky, not necessary for v1, harder to debug and validate.

Recommendation: **Option A**, with strict bounds and UI controls.

---

## Implementation Plan (v1)

1. Add `UserDictionary` component (actor or @MainActor depending on storage access patterns):
   - load/save JSON in Application Support (local only)
   - CRUD API: add/remove/list rules
   - counter update API: recordAutoReject(token,…), recordManualApply(token,…)
2. Integrate into detection:
   - consult dictionary at start of `ConfidenceRouter.route(...)`
   - apply bias actions in `scoredDecision(...)`
3. Wire learning events:
   - When auto-correction is undone (cycling to original) → record reject
   - When manual correction applied → record apply
4. Add Settings UI:
   - new tab “User Dictionary”
   - toggle learning
   - list rules + delete/disable
   - add rule dialog (token + action + scope)
5. Add tests:
   - unit tests for rule matching (matchMode, scope)
   - integration tests proving:
     - repeated auto rejects lead to keepAsIs short-circuit
     - repeated manual apply leads to preferHypothesis bias
   - ensure performance: dictionary lookup is O(1) and does not increase hot-path latency materially

---

## Files Likely Affected
- `OMFK/Sources/Core/ConfidenceRouter.swift`
- `OMFK/Sources/Core/UserLanguageProfile.swift` (optional synergy)
- `OMFK/Sources/Engine/CorrectionEngine.swift` (hook learning events)
- `OMFK/Sources/UI/SettingsView.swift` (new tab)
- New:
  - `OMFK/Sources/Core/UserDictionary.swift`
  - `OMFK/Sources/Core/UserDictionaryModels.swift` (optional split)
- Tests:
  - new `OMFK/Tests/UserDictionaryTests.swift`
  - extend `OMFK/Tests/RealUserBehaviorTests.swift` or `OMFK/Tests/HotkeyTextIntegrityTests.swift`

---

## Definition of Done
- User can add/remove rules from settings.
- After two rejections of the same auto-correction, OMFK stops auto-correcting that token (keepAsIs rule).
- After two manual applications of the same mapping, OMFK prefers that mapping next time (bias rule) while still passing validation gates.
- Dictionary is bounded, local-only, and can be fully cleared.
- `swift test` passes with new coverage for the above behaviors.

