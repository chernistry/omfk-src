# Ticket 19: Automated Layout Detection Testing Suite

Spec version: v2.0

## Context

The OMFK layout detection system now has a functional CoreML classifier integrated with N-gram validation. However, there is no automated way to test all 9 language pair scenarios systematically. Manual testing is time-consuming and error-prone.

**Debug logs location**: `~/.omfk/debug.log`

## Current State (as of 2024-12-21)

### What Works:
- EN → RU switching (e.g., `ghbdtn` → `привет`) works well
- CoreML correctly predicts `_from_` hypotheses
- N-gram validation prevents most false positives
- `LanguageHypothesis` rawValues now match Python class labels (snake_case)

### What Doesn't Work Well:
- RU → EN switching often fails validation
- HE → any language rarely triggers corrections
- Any → HE switching is problematic

### Root Causes Identified:
1. Training data imbalance: 66% `_from_` samples vs 34% pure language samples
2. Only 100,000 samples generated despite 160M+ words available
3. Hebrew layouts (`he_qwerty`, `he_standard`) not thoroughly tested
4. N-gram validation thresholds may need tuning per language pair

## Objective

Create an automated test suite that verifies all 9 language detection scenarios:

| # | Scenario | Example Input | Expected Output |
|---|----------|---------------|-----------------|
| 1 | RU intended, HE active | (TBD from layouts.json) | `ru_from_he` |
| 2 | EN intended, HE active | (TBD from layouts.json) | `en_from_he` |
| 3 | HE intended, HE active (correct) | `שלום` | `he` |
| 4 | RU intended, EN active | `ghbdtn` | `ru_from_en` |
| 5 | HE intended, EN active | `wlom` | `he_from_en` |
| 6 | EN intended, EN active (correct) | `hello` | `en` |
| 7 | HE intended, RU active | `ЛМПКРД` | `he_from_ru` |
| 8 | EN intended, RU active | `зщдшсн` | `en_from_ru` |
| 9 | RU intended, RU active (correct) | `привет` | `ru` |

## Definition of Done

- [ ] **Test Data Generator** (`Tools/Testing/generate_test_cases.py`):
  - Reads `layouts.json` to get accurate character mappings
  - Generates 20+ test cases per language pair (180+ total)
  - Outputs JSON with `input`, `expected_class`, `intended_text`

- [ ] **Swift Test Suite** (`Tests/OMFKTests/LayoutDetectionTests.swift`):
  - Parametrized tests for all 9 scenarios
  - Tests CoreML predictions directly
  - Tests full ConfidenceRouter pipeline
  - Reports accuracy per language pair

- [ ] **Benchmark Script** (`Tools/Testing/benchmark.py`):
  - Runs model against test cases
  - Reports confusion matrix
  - Generates accuracy report per class
  - Identifies worst-performing pairs

- [ ] **CI Integration**:
  - Add test suite to `swift test`
  - Fail build if accuracy drops below 80%

## Files to Create/Modify

- `Tools/Testing/generate_test_cases.py` — **NEW**
- `Tools/Testing/benchmark.py` — **NEW**
- `Tools/Testing/test_cases.json` — **NEW** (generated)
- `Tests/OMFKTests/LayoutDetectionTests.swift` — **NEW**

## Dependencies

- Tickets 13, 14, 17 (completed)
- `layouts.json` for accurate character mappings

## Priority

**P1 — HIGH** — Required for systematic improvement of detection quality.
