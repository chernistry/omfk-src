# Ticket: 18 Final validation with full detection pipeline

Spec version: v1.0

## Context

After implementing CoreML (ticket 17), we need final validation of the complete detection pipeline:
- N-gram (Fast Path)
- Ensemble (Standard Path)
- CoreML (Deep Path)
- Confidence Router orchestrating all three

## Objective & Definition of Done

### Definition of Done

- [ ] **Full pipeline benchmarks**:
  - [ ] Compare accuracy: N-gram only vs Ensemble vs CoreML vs Router
  - [ ] Measure routing distribution (% fast/standard/deep)
  - [ ] Verify latency targets met

- [ ] **Edge case testing**:
  - [ ] Mixed-language text
  - [ ] Slang and abbreviations
  - [ ] Transliteration (privet, shalom)
  - [ ] Very short tokens (2 chars)

- [ ] **All layout variants**:
  - [ ] Test with each Hebrew variant (standard, pc, qwerty)
  - [ ] Test with each Russian variant (pc, phonetic)

- [ ] **Production readiness**:
  - [ ] Memory usage stable (<100MB)
  - [ ] No crashes in 1+ hour continuous use
  - [ ] All DoD items from project.md verified

## Expected Results

| Metric | Target | With CoreML |
|--------|--------|-------------|
| Accuracy 4+ chars | >95% | >98% |
| Accuracy 2-3 chars | >85% | >92% |
| False positive rate | <3% | <1.5% |
| Latency (avg) | <10ms | <15ms |
| Routing: Fast Path | ~70% | — |
| Routing: Standard | ~25% | — |
| Routing: Deep | ~5% | — |

## Steps

1. **Run full benchmark suite** (1 day)
2. **Edge case testing** (1 day)
3. **Layout variant testing** (0.5 day)
4. **Production stability test** (0.5 day)
5. **Document final results** (0.5 day)

## Affected Files/Modules

- `IMPLEMENTATION_STATUS.md` — final results
- `README.md` — update with accuracy claims

## Dependencies

- **Upstream**: All tickets 13-17

## Priority

**P1 — HIGH** — Final validation before release.
