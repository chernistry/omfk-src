# Ticket: 13 Integrate n-gram and ensemble into LanguageDetector pipeline

Spec version: v1.0 / strategies.md#strategy-1-2

## Context
- Tickets 10–12 provide:
  - `LayoutNgramDetector` as fast layout-aware scorer.
  - `LanguageEnsemble` wrapping `NLLanguageRecognizer` + layout hypotheses.
- `.sdd/architect.md` defines `LanguageDetector`, `EventMonitor`, `LayoutMapper`, and their responsibilities.

This ticket wires the new detectors into the **runtime pipeline** so OMFK uses them for real-time decisions.

## Objective & Definition of Done
- Replace or augment the existing language/layout detection code so that:
  - `EventMonitor` / `LanguageDetector`:
    - on each token boundary (and possibly prefix length ≥2):
      - calls `LayoutNgramDetector` for fast scoring,
      - calls `LanguageEnsemble` when needed (e.g. for longer tokens or ambiguous cases),
      - produces a single `LayoutDecision` used by `LayoutMapper` / `CorrectionEngine`.
- Ensure:
  - latency budget is respected (<50ms end-to-end for detection + correction, with detectors using only a small fraction);
  - behaviour is logged for debugging (e.g. top hypotheses and scores at debug log level).

Acceptance criteria:
- `LanguageDetector` (or equivalent) updated to:
  - centralise layout/language decision logic;
  - incorporate both n-gram scores and ensemble output into a final decision.
- Existing public API of `LanguageDetector` stays stable (or updated in a clearly documented way) so the rest of the app continues to function.
- Debug logging can be enabled to inspect, for a sample key sequence, which detector components fired and how they decided.

## Steps
1. **Review existing pipeline**
   - Identify current call sites where:
     - `NLLanguageRecognizer` is used;
     - raw heuristics decide “wrong layout” vs “correct layout”.
2. **Introduce a unified `LanguageDetector` abstraction**
   - Ensure a single entry point, e.g.:
     - `func decide(token: String, context: DetectorContext) -> LayoutDecision`.
   - Inside:
     - call `LayoutNgramDetector` first for quick scoring;
     - if token length ≥3 or ambiguity high → call `LanguageEnsemble`.
3. **Decision fusion**
   - Define rules for combining scores:
     - e.g. if n-gram confidence high and ensemble agrees → accept;
     - if they conflict → prefer higher-confidence or context-aligned result.
   - Keep fusion logic simple and documented (no hidden magic).
4. **EventMonitor integration**
   - Ensure `EventMonitor`:
     - collects token text correctly for detectors;
     - respects new decision object (e.g. `keep`, `swapToRu`, `swapToHe`, `switchLayoutOnly`).
   - Avoid blocking the main thread; keep detection on appropriate queues/actors.
5. **Add scenario tests**
   - For key sequences representing:
     - typical RU/EN/HE words in correct layout;
     - classic “ghbdtn” / “руддщ” / Hebrew mixed cases;
     - ambiguous short tokens.
   - Assert:
     - correct final layout decision;
     - no regression vs previous behaviour on simple cases.

## Affected files/modules
- `LanguageDetector` / `EventMonitor` implementation.
- `LayoutMapper` / `CorrectionEngine` if decision type changes.
- Tests for high-level language/layout detection.

## Tests
- Existing tests continue to pass.
- New integration tests for the pipeline added and passing.

## Risks & Edge Cases
- Risk: behaviour change surprises existing users.
  - Mitigation: consider a feature flag or configuration for enabling the new pipeline.
- Risk: latency spike in worst-case scenarios.
  - Mitigation: benchmark and optimise hot paths; ensure asynchronous execution where necessary.

## Dependencies
- Upstream:
  - 10-layout-aware-ngram-detector-baseline.md
  - 11-ngram-training-tooling-and-model-assets.md
  - 12-ensemble-with-nllanguagerecognizer-and-layout-hypotheses.md
- Downstream:
  - 14-context-adaptive-layer-for-user-specific-learning.md

