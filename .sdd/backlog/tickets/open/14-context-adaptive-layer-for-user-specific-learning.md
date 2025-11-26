# Ticket: 14 Context-adaptive layer for user-specific learning (Strategy 4)

Spec version: v1.0 / strategies.md#strategy-4

## Context
- Strategy 4 describes a **meta-layer** above any base detector:
  - uses sentence context, user’s history, and results of real corrections (accepted/reverted);
  - goal: reduce false positives and provide self-learning without retraining ML models.
  - must learn from all RU/EN/HE layout combinations, including RU↔HE, not only EN↔{RU,HE}.
- Architect spec: `.sdd/architect.md` — mentions event history and settings; this ticket extends that with adaptive behaviour.
- Tickets 10–13 introduce new detectors and pipeline.

## Objective & Definition of Done
- Implement `UserLanguageProfile` / context-adaptive layer that:
  - observes final outcomes of corrections (accepted vs reverted) and context;
  - maintains lightweight statistics (e.g. per-prefix/per-language acceptance rates);
  - adjusts effective thresholds for triggering autocorrection based on this history.

Acceptance criteria:
- New actor, e.g.:
  - `actor UserLanguageProfile { func record(decision: LayoutDecision, outcome: CorrectionOutcome, context: ProfileContext); func adjustThresholds(for token: String, baseConfidence: Double) -> Double }`.
- The meta-layer:
  - reduces autocorrection aggressiveness for patterns frequently rejected by the user;
  - allows slightly more aggressive correction for patterns consistently accepted.
- Stats storage:
  - in-memory cache with bounded size (e.g. LRU over prefix/context keys);
  - periodic flush to disk (small JSON/SQLite file) for persistence between sessions.

## Steps
1. **Design profile data model**
   - Decide key space:
     - e.g. `(prefix: String, lastLanguage: Language)` → counts `{accepted, rejected}`.
   - Define `CorrectionOutcome` enum (`accepted`, `revertedImmediately`, etc.).
2. **Implement actor**
   - Methods for:
     - recording an outcome at the end of a token;
     - computing adjusted confidence threshold for a future decision.
   - Implement simple policy:
     - if rejection rate for a key > X% → raise threshold for autocorrect;
     - if acceptance rate high → allow slightly lower threshold.
3. **Integrate with detector pipeline**
   - In the final decision step:
     - call `UserLanguageProfile.adjustThresholds` with base confidence;
     - compare against dynamic threshold.
   - On user action (e.g. undo, manual layout switch):
     - record as negative outcome for the corresponding key.
4. **Persistence**
   - Implement periodic save (e.g. on app exit or every N minutes).
   - On startup, load existing profile if available; handle migration/versioning minimalistically.
5. **Add tests**
   - Unit tests for:
     - threshold adjustment logic given synthetic counters;
     - persistence (save/load) not corrupting data.

## Affected files/modules
- New `UserLanguageProfile` actor/module.
- `LanguageDetector` / `EventMonitor` integration points.
- Settings/history modules if they expose controls for resetting/opt-out.

## Tests
- `swift test` with new tests for profile logic.

## Risks & Edge Cases
- Risk: polluted stats due to experimentation or atypical behaviour.
  - Mitigation: cap history horizon, allow reset from settings.
- Risk: increased complexity / non-determinism.
  - Mitigation: keep logic simple and well-documented; log profile decisions at debug level only.

## Dependencies
- Upstream:
  - 13-integrate-ngram-and-ensemble-into-language-detector-pipeline.md
- Downstream:
  - 15-validation-and-benchmarking-of-new-detection-pipeline.md
