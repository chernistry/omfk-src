# Ticket: 15 Validation and benchmarking of new detection pipeline

Spec version: v1.0 / strategies.md#validation

## Context
- Tickets 10–14 introduce:
  - n-gram detector,
  - NLLanguageRecognizer ensemble,
  - unified LanguageDetector pipeline,
  - context-adaptive meta-layer.
- `.sdd/architect.md` and `.sdd/project.md` define DoD:
  - high accuracy for RU/EN/HE,
  - <50ms detection + correction latency,
  - low false positives.
- `.sdd/architect.md` also requires a **test corpus** and performance criteria.

## Objective & Definition of Done
- Validate the new detection pipeline against:
  - synthetic and real-world corpora (RU/EN/HE + mixed);
  - latency and memory constraints.
- Provide a short report/checklist in `IMPLEMENTATION_STATUS.md` or `DEBUGGING.md` summarising results and remaining gaps.

Acceptance criteria:
- Benchmarks:
  - throughput tests for the combined detector pipeline on representative workloads (e.g. 10k tokens per language).
  - measured:
    - average and p95 latency per token,
    - memory footprint changes.
- Accuracy evaluation:
  - metrics computed on a labelled corpus (correct layout vs wrong layout).
  - confusion matrix and key percentages (accuracy, false positive rate) for:
    - 2–3 chars,
    - 4–6 chars,
    - 7+ chars.
- Documentation:
  - a short section added to `IMPLEMENTATION_STATUS.md` or `DEBUGGING.md`:
    - summarising benchmark methodology and results;
    - stating whether DoD targets are met.

## Steps
1. **Prepare evaluation harness**
   - Add a small test target or CLI tool that:
     - loads the detection pipeline;
     - feeds sequences from corpora and records decisions and timings.
2. **Collect / prepare labelled data**
   - Use or extend the test corpus described in `.sdd/architect.md`:
     - RU/EN/HE phrase files,
     - synthetic “wrong layout” variants.
3. **Run benchmarks**
   - Measure:
     - detection + decision latency per token;
     - memory impact via Instruments / Xcode tools.
4. **Compute accuracy metrics**
   - For each language and token length bucket, compute:
     - correct classification rate;
     - false positive rate (unwanted corrections).
5. **Document results**
   - Add a succinct section to `IMPLEMENTATION_STATUS.md` (or `DEBUGGING.md`) with:
     - tables or bullet-point metrics;
     - notes on any remaining gaps relative to DoD.

## Affected files/modules
- Test harness (CLI or test target).
- `Tests/...` for evaluation helpers.
- Docs:
  - `IMPLEMENTATION_STATUS.md` or `DEBUGGING.md`.

## Tests
- The evaluation harness itself is run as part of manual validation.
- Existing unit and integration tests must continue to pass.

## Risks & Edge Cases
- Risk: evaluation corpus not representative.
  - Mitigation: include mixed-language, slang, and edge cases where possible.
- Risk: benchmarks introduce flaky tests.
  - Mitigation: keep heavy benchmarks outside normal CI and run them manually or under a separate flag.

## Dependencies
- Upstream:
  - 10-layout-aware-ngram-detector-baseline.md
  - 11-ngram-training-tooling-and-model-assets.md
  - 12-ensemble-with-nllanguagerecognizer-and-layout-hypotheses.md
  - 13-integrate-ngram-and-ensemble-into-language-detector-pipeline.md
  - 14-context-adaptive-layer-for-user-specific-learning.md

