# Ticket: 17 CoreML classifier for layout detection

Spec version: v1.0 / strategies.md#strategy-3

## Context

After validation (ticket 16), we add CoreML as the **Deep Path** in the Confidence Router for:
- Ambiguous cases where N-gram + Ensemble disagree
- Short tokens (2-3 chars) where statistical methods struggle
- "Dirty" input: slang, typos, transliteration

CoreML complements (not replaces) the existing N-gram + Ensemble pipeline.

## Architecture Integration

```
ConfidenceRouter
├── Fast Path (N-gram) ──────── conf > 0.95, 4+ chars
├── Standard Path (Ensemble) ── conf > 0.7
└── Deep Path (CoreML) ──────── ambiguous cases ← THIS TICKET
```

## Objective & Definition of Done

### Definition of Done

- [ ] **Training Pipeline** (`Tools/CoreMLTrainer/`):
  - [ ] `requirements.txt` — torch, coremltools, ollama, datasets
  - [ ] `download_corpus.py` — fetch Wikipedia dumps (RU/EN/HE)
  - [ ] `generate_data.py` — synthetic layout-switched data
  - [ ] `gen_hard_cases.py` — LLM-augmented hard examples (OLLAMA)
  - [ ] `train.py` — PyTorch 1D-CNN training
  - [ ] `export.py` — convert to CoreML (.mlmodel)
  - [ ] `validate_with_llm.py` — LLM judge for quality audit

- [ ] **Swift Integration**:
  - [ ] `CoreMLLayoutClassifier.swift` — wrapper for .mlmodel
  - [ ] Integration with ConfidenceRouter as Deep Path
  - [ ] Graceful fallback if model not loaded

- [ ] **Model Specs**:
  - [ ] Input: 12 characters (padded)
  - [ ] Output: 9 classes (all LanguageHypothesis values)
  - [ ] Size: <2MB
  - [ ] Latency: <5ms on M1/M2

## Training Data Classes

```python
classes = [
    'ru',              # Russian as-is
    'en',              # English as-is
    'he',              # Hebrew as-is
    'ru_from_en',      # Russian typed on EN layout (ghbdtn → привет)
    'he_from_en',      # Hebrew typed on EN layout
    'en_from_ru',      # English typed on RU layout (руддщ → hello)
    'en_from_he',      # English typed on HE layout
    'he_from_ru',      # Hebrew typed on RU layout (via composition)
    'ru_from_he',      # Russian typed on HE layout (via composition)
]
```

## Steps

### Phase 1: Training Pipeline (Python)
1. **Environment setup** (0.5 day)
2. **Corpus acquisition** (1 day)
3. **Data generation** (1 day)
4. **LLM augmentation** (1 day)
5. **Model training** (1 day)
6. **CoreML export** (0.5 day)

### Phase 2: Swift Integration
7. **CoreMLLayoutClassifier** (0.5 day)
8. **ConfidenceRouter integration** (0.5 day)
9. **Tests** (1 day)

## Affected Files/Modules

- `Tools/CoreMLTrainer/` — new Python pipeline
- `OMFK/Sources/Resources/LayoutClassifier.mlmodel` — trained model
- `OMFK/Sources/Core/CoreMLLayoutClassifier.swift` — new file
- `OMFK/Sources/Core/ConfidenceRouter.swift` — add Deep Path

## Reference Documentation

- **Strategies**: `.sdd/strategies.md` (Strategy 3 detailed guide)
- **Layout data**: `.sdd/layouts.json`

## Dependencies

- **Upstream**: Tickets 13, 14, 16 (validation identifies gaps)
- **Downstream**: Ticket 18 (final validation with CoreML)

## Requirements

- Python 3.9+
- PyTorch 2.0+
- coremltools 7.0+
- Local OLLAMA instance (for LLM augmentation)

## Priority

**P1 — HIGH** — Core feature for production-grade accuracy.
