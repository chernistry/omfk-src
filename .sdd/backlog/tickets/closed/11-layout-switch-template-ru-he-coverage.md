# Ticket: 11 Layout-switch template and RU↔HE coverage

Spec version: v1.0 / omfk-layout-switching-v1

## Context
- Project spec:
  - `.sdd/project.md` — DoD now requires layout mapping to support **all pairs among RU/EN/HE**, including RU↔HE.
- Architect spec:
  - `.sdd/architect.md` — Goal 3 (“Real-time layout correction”) now calls for complete RU/EN/HE mapping, including a clear RU↔HE path (direct or via EN).
- Implemented components:
  - `LayoutMapper.swift` currently supports:
    - RU↔EN and HE↔EN character mappings,
    - but **explicitly returns nil** for RU→HE (see `testUnsupportedConversion`).
  - `LanguageHypothesis` and detectors:
    - n-gram and ensemble strategies use layout hypotheses like:
      - `.ru`, `.en`, `.he`, `.enFromRuLayout`, `.enFromHeLayout`, `.ruFromEnLayout`, `.heFromEnLayout`.
    - There is no explicit representation of RU↔HE mis-layout hypotheses.
- Strategies:
  - `.sdd/strategies.md` — Strategy 1 & 2 already describe EN↔RU and EN↔HE hypotheses and optional RU→EN/HE→EN; RU↔HE is only implied via composition.

Real-world requirement:
- Users frequently switch between RU and HE, not only via EN.
- OMFK must correctly detect and fix **all combinations**:
  - EN typed on RU layout (classic “ghbdtn”),
  - EN typed on HE layout,
  - RU typed on HE layout (via RU→EN→HE or direct mapping),
  - HE typed on RU layout (via HE→EN→RU or direct mapping),
  - plus their inverses where appropriate.

This ticket defines a canonical **layout-switch template** and updates the core mapping/detector design so that RU↔HE paths are first-class, not accidental.

## Objective & Definition of Done

Objective:
- Introduce a **single, explicit layout-switching model** for the triplet {RU, EN, HE} and wire it through:
  - `LayoutMapper` (character mapping),
  - `LanguageHypothesis` / n-gram & ensemble detectors,
  - tests and strategies documentation.

### Definition of Done

- Layout-switch template:
  - [ ] Define a conceptual layout-switch matrix for {RU, EN, HE}:
    - allowed primitive mappings:
      - RU↔EN
      - HE↔EN
    - derived RU↔HE mappings via composition (RU→EN→HE, HE→EN→RU) or explicit RU↔HE tables.
  - [ ] Document this matrix in `.sdd/architect.md` and/or `.sdd/strategies.md`, including which paths are implemented as direct tables vs composed conversions.
- `LayoutMapper`:
  - [ ] Extend `LayoutMapper.convert` so that:
    - RU→HE and HE→RU conversions succeed using the agreed template (either direct mapping or two-step RU→EN→HE and HE→EN→RU).
    - behaviour remains deterministic and reversible for all three languages.
  - [ ] Update tests:
    - `LayoutMapperTests`:
      - [ ] add positive tests for RU→HE and HE→RU conversions (even if via composition);
      - [ ] remove or adjust `testUnsupportedConversion` so RU→HE is no longer treated as unsupported.
- Detector hypotheses:
  - [ ] Extend `LanguageHypothesis` and detection strategy so RU↔HE cases are covered explicitly:
    - clarify how RU-typed-as-HE and HE-typed-as-RU are represented:
      - either via new hypotheses (e.g. `.heFromRuLayout`, `.ruFromHeLayout`),
      - or via explicit documentation that they are handled by composition through existing `.enFromRuLayout` / `.enFromHeLayout` paths.
  - [ ] Ensure `LanguageEnsemble` and n-gram scoring logic treat RU↔HE mis-layout scenarios as **first-class**:
    - add tests for tokens like RU words typed on HE layout and vice versa.
- SDD alignment:
  - [ ] `.sdd/project.md` and `.sdd/architect.md` remain consistent with the final design:
    - they explicitly mention RU↔HE support as part of the layout mapping requirements.

## Steps

1. **Design the layout-switch matrix**
   - [ ] Decide whether to:
     - implement direct RU↔HE tables in `LayoutMapper`, or
     - treat RU↔HE as composition of RU↔EN and HE↔EN with guarantees around reversibility.
   - [ ] Update `.sdd/architect.md` (and optionally `.sdd/strategies.md`) to describe this clearly.
2. **Update `LayoutMapper` and tests**
   - [ ] Implement RU→HE and HE→RU mapping according to the chosen template.
   - [ ] Extend `LayoutMapperTests` to cover:
     - simple RU word typed on HE layout → corrected HE,
     - simple HE word typed on RU layout → corrected RU,
     - round-trips where appropriate (RU→EN→HE vs RU→HE direct).
3. **Align detection hypotheses**
   - [ ] Update `LanguageHypothesis` and related logic so that:
     - all mis-layout patterns between RU/EN/HE have a representation;
     - detectors can reason about RU↔HE cases without ad-hoc hacks.
   - [ ] Add tests for ensemble/n-gram decisions on RU↔HE mis-layout tokens.
4. **Refresh SDD docs**
   - [ ] Ensure `.sdd/project.md` DoD and `.sdd/architect.md` goals remain valid and precise with the new mapping semantics.

## Affected files / modules
- `.sdd/project.md`
- `.sdd/architect.md`
- `.sdd/strategies.md` (layout hypotheses sections)
- `OMFK/Sources/Core/LayoutMapper.swift`
- `OMFK/Tests/LayoutMapperTests.swift`
- `OMFK/Sources/Core/NgramLanguageModel.swift` (LanguageHypothesis)
- `OMFK/Sources/Core/LanguageEnsemble.swift`

## Tests
- Unit tests:
  - LayoutMapper RU↔HE conversions.
  - Ensemble and n-gram behaviour on RU↔HE mis-layout tokens.
- Integration:
  - end-to-end test where RU text mistakenly typed with HE layout (and vice versa) is detected and corrected.

## Risks & Edge Cases
- RU↔HE mapping is less common than EN↔{RU,HE} and might not always be desired.
  - Mitigation: keep mapping explicit and configurable (future ticket), but design the template so OMFK “knows how” even if some cases are disabled at runtime.
- Two-step composition (RU→EN→HE) could introduce edge-case mismatches for symbols or punctuation.
  - Mitigation: define clear rules for non-letter characters and test common patterns.

## Dependencies
- Upstream:
  - 05-layout-mapper.md
- Downstream:
  - 12-ensemble-with-nllanguagerecognizer-and-layout-hypotheses.md
  - 13-integrate-ngram-and-ensemble-into-language-detector-pipeline.md
  - 15-validation-and-benchmarking-of-new-detection-pipeline.md

