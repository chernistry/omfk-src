# Ticket: 10 Layout-aware n-gram detector baseline (Strategy 1)

Spec version: v1.0 / strategies.md#strategy-1

## Context
- Architecture: `.sdd/architect.md` — LanguageDetector, LayoutMapper, CorrectionEngine and performance/quality constraints (RU/EN/HE, <50ms correction, local-only).
- Strategies: `.sdd/strategies.md` — **Strategy 1: Layout-aware n-gram detector (RU/EN/HE)**.
- Existing implementation:
  - Current language/layout detection relies primarily on `NLLanguageRecognizer` + heuristics.
  - There is no dedicated n-gram probability engine specialised for layout hypotheses (as-is vs RU-from-EN vs HE-from-EN).

This ticket introduces a **deterministic, layout-aware n-gram detector** as a baseline scoring engine for RU/EN/HE.

## Objective & Definition of Done
- Implement a pure-Swift `LayoutNgramDetector` that:
  - Loads precomputed trigram log-probability tables for RU/EN/HE (and, optionally, layout-mapped hypotheses) into memory (≤3 MB total).
  - For each token/prefix (2–12 characters), computes log-likelihood scores for several layout hypotheses (as-is, EN→RU, EN→HE, optionally RU→EN / HE→EN).
  - Exposes a small, testable API that returns:
    - per-hypothesis scores (`score[lang/hypothesis]`),
    - the most probable hypothesis,
    - an approximate confidence value in [0, 1].
- Ensure the detector is **fast and deterministic**:
  - Average evaluation time per token (2–12 chars) ≤ 0.3 ms on M1/M2 in release build.
  - No dynamic allocation in the hot path beyond the input string.

Acceptance criteria:
- New type(s) added (names may be refined, but semantics preserved), for example:
  - `struct NgramLanguageModel { /* trigram tables + lookup */ }`
  - `actor LayoutNgramDetector { func score(token: String, context: LayoutContext) -> LayoutScores }`
- N-gram tables are stored in a compact format (e.g. `[UInt32: Float]` where key is trigram hash) and loaded once on startup.
- For a set of synthetic test tokens (e.g. `"ghbdtn"`, `"руддщ"`, `"shalom"`, `"шалом"`), unit tests show:
  - higher scores for the “correct layout” reconstruction than for as-is form;
  - confidence monotonically increases with token length (2→4→6 chars).
- Performance tests demonstrate:
  - ≤0.3 ms per evaluation for tokens of length 2–12;
  - memory footprint for tables in the expected range (≈1–3 MB).

## Steps
1. **Define data structures**
   - Design an internal representation for trigram tables:
     - key: 3-character trigram encoded as `UInt32` (e.g. simple hash or packed Unicode scalar IDs),
     - value: `Float` log-probability with add-k smoothing.
   - Define public API types:
     - `enum LanguageHypothesis { case ru, en, he, enFromRuLayout, enFromHeLayout /* etc. */ }`
     - `struct LayoutScores { var scores: [LanguageHypothesis: Float]; var best: LanguageHypothesis; var confidence: Double }`
     - `struct LayoutContext { var lastLanguage: LanguageHypothesis? }` (for later use; may be optional in this ticket).
2. **Integrate n-gram tables**
   - Decide where the offline-generated trigram tables will live (e.g. in `Resources/LanguageModels/` or embedded Swift arrays for now).
   - Implement a loader that:
     - reads compact binary/JSON representation into `[UInt32: Float]`,
     - validates basic invariants (non-empty, finite values).
3. **Implement scoring logic**
   - Implement normalization:
     - convert input token to a canonical form (letters only, lowercased, single “virtual layout”).
   - Implement trigram walk:
     - for each hypothesised mapping (as-is, EN→RU, EN→HE, …):
       - generate the mapped string;
       - iterate `i=0..L-3` and sum `log P(trigram | hypothesisLanguage)` using the table;
       - apply simple add-k smoothing fallback for missing trigrams.
   - Convert raw log-scores into:
     - a `best` hypothesis (argmax),
     - a normalised confidence value ∈ [0,1] (e.g. softmax or margin between top-1 and top-2 scores).
4. **Wire into a Swift actor**
   - Implement `actor LayoutNgramDetector` that:
     - owns the loaded tables,
     - exposes `func score(token: String, context: LayoutContext?) async -> LayoutScores`.
   - Ensure actor methods are `nonisolated` for read-only calls if possible (for performance), or minimise cross-actor overhead.
5. **Add tests**
   - Unit tests for:
     - consistent hashing of trigrams;
     - stable scores for fixed token + hypothesis combinations;
   - Scenario tests for:
     - typical “wrong layout” inputs (`ghbdtn`, `руддщ`, mixed examples);
     - verifying that with increasing length, confidence goes up.
   - Performance test that:
     - evaluates ≥1000 random tokens and asserts average time constraint.

## Affected files/modules
- Swift:
  - `OMFK/Sources/.../LanguageDetector` and/or a new `LanguageModels` module.
  - New resources (binary/JSON tables) under `Tests/Resources/LanguageModels` or similar.
- Tests:
  - `Tests/...` for unit/performance tests.
- SDD:
  - `.sdd/strategies.md` (read-only reference).

## Tests
- `swift test` (or `xcodebuild test`) with:
  - success for all new unit tests (functional + performance thresholds as assertions).

## Risks & Edge Cases
- Risk: trigram hashing collisions skew probabilities.
  - Mitigation: use a stable simple hash with low collision risk for the seen alphabet, or store raw UTF-32 code units for trigrams.
- Risk: corpora or tables incomplete → poor performance on real text.
  - Mitigation: start with synthetic tests, then iterate once real corpora/tables are available.
- Risk: premature optimisation in this ticket.
  - Mitigation: focus on clear, testable API; avoid overcomplicating the loader format initially.

## Dependencies
- Upstream:
  - `.sdd/strategies.md` Strategy 1.
- Downstream:
  - Ticket 11 (offline n-gram training and integration into LayoutDetector pipeline).

