# Ticket: 16 Validation and benchmarking of detection pipeline

Spec version: v1.0 / strategies.md#validation

## Context

Tickets 13-15 implement:
- Multi-layout support from JSON
- Confidence Router with N-gram + Ensemble
- Settings UI for layout selection

This ticket validates the pipeline before adding CoreML (ticket 17).

## Objective & Definition of Done

### Definition of Done

- [ ] **Benchmarks**:
  - [ ] Throughput tests (10k tokens per language)
  - [ ] Average and p95 latency per token
  - [ ] Memory footprint

- [ ] **Accuracy evaluation**:
  - [ ] Confusion matrix for all layout pairs (EN↔RU, EN↔HE, RU↔HE)
  - [ ] Accuracy by token length: 2-3, 4-6, 7+ chars
  - [ ] False positive rate

- [ ] **Test all layout variants**:
  - [ ] ru_pc, ru_phonetic_yasherty
  - [ ] he_standard, he_pc, he_qwerty

- [ ] **Documentation**:
  - [ ] Results in `IMPLEMENTATION_STATUS.md`
  - [ ] Identify gaps for CoreML to address

## Steps

1. **Prepare evaluation harness** (1 day)
2. **Collect labelled data** (0.5 day)
3. **Run benchmarks** (0.5 day)
4. **Compute accuracy metrics** (0.5 day)
5. **Document results** (0.5 day)

## Expected Results (targets)

| Metric | Target | Notes |
|--------|--------|-------|
| Latency (avg) | <10ms | Per token |
| Latency (p95) | <20ms | Per token |
| Accuracy 4+ chars | >95% | All layout pairs |
| Accuracy 2-3 chars | >85% | Short tokens harder |
| False positive rate | <3% | Unwanted corrections |

## Affected Files/Modules

- `Tools/Benchmark/` — new evaluation harness
- `IMPLEMENTATION_STATUS.md` — results documentation

## Reference Documentation

- **Layout data**: `.sdd/layouts.json`
- **Strategies**: `.sdd/strategies.md`

## Dependencies

- **Upstream**: Tickets 13, 14, 15
- **Downstream**: Ticket 17 (CoreML addresses gaps found here)

## Priority

**P1 — HIGH** — Must validate before adding CoreML.
