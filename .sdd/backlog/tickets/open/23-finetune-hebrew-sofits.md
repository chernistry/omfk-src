# Ticket 23: Fine-tune Model for Hebrew QWERTY Sofits

Spec version: v1.0

## Context

The current model was trained with incomplete `he_qwerty` layout data. The Hebrew final letters (sofits) were missing:
- ך (final kaf)
- ם (final mem)
- ן (final nun)
- ף (final pe)
- ץ (final tsadi)

This was fixed in `layouts.json` (commit 142f295), but the model needs fine-tuning to learn these patterns.

## Current State

- **Base model**: Trained on 5M samples, ~98.4% validation accuracy
- **Problem**: `he_qwerty` conversions with sofits don't work correctly
- **Example**: שלום should map to `wloM` (or `wlom`) but model wasn't trained on this

## Objective

Fine-tune the existing model to:
1. Learn `he_qwerty` patterns with sofits
2. Maintain existing ru↔en accuracy

## Definition of Done

- [ ] Generate focused `he_qwerty` training data (~100k-200k samples)
- [ ] Fine-tune model with low learning rate (0.0001)
- [ ] Verify `he_qwerty` accuracy ≥ 95%
- [ ] Verify ru↔en accuracy unchanged (≥ 98%)
- [ ] Export updated CoreML model

## Implementation Plan

### Step 1: Generate Focused Data

```bash
cd Tools/CoreMLTrainer
python3 generate_data.py \
  --count 200000 \
  --balance 0.3 \
  --output training_data_he_qwerty.csv \
  --corpus_dir ../../data/processed \
  --focus-layout he_qwerty  # New flag to generate only he-related samples
```

### Step 2: Fine-tune

```python
# Load existing model
model.load_state_dict(torch.load('model_ultimate.pth'))

# Lower learning rate to preserve existing knowledge
optimizer = Adam(model.parameters(), lr=0.0001)

# Train for 10-20 epochs on new data
```

### Step 3: Validate

Run `LayoutDetectionTests.swift` with focus on Hebrew pairs:
- Pure HE: should remain 100%
- HE from EN: should improve significantly
- HE from RU: should improve
- RU from HE: should improve
- EN from HE: should improve

## Files to Modify

- `Tools/CoreMLTrainer/generate_data.py` — add `--focus-layout` flag
- `Tools/CoreMLTrainer/train.py` — add `--finetune` mode
- `OMFK/Sources/Resources/LayoutClassifier.mlmodel` — updated model

## Technical Notes

### Why Fine-tune Instead of Retrain?

1. **Time**: Fine-tuning takes 10-15 min vs 1+ hour for full training
2. **Preservation**: Low LR prevents "catastrophic forgetting" of ru↔en patterns
3. **Efficiency**: Only need ~200k new samples vs 5M

### Data Already Includes

✅ Different cases (Hello, hello, HELLO)
✅ Punctuation (., ?, !, /)
✅ Numbers mixed with text
✅ Multi-word phrases

### Sofits Mapping (he_qwerty)

| Hebrew | Key | Normal | Shift |
|--------|-----|--------|-------|
| כ/ך | KeyK | כ | ך |
| מ/ם | KeyM | מ | ם |
| נ/ן | KeyN | נ | ן |
| פ/ף | KeyP | פ | ף |
| צ/ץ | KeyC | צ | ץ |

## Dependencies

- Ticket 22 completed (base model trained)
- `layouts.json` fix committed

## Priority

**P1 — HIGH** — Required for proper Hebrew support.

## Estimated Time

- Data generation: 2-3 minutes
- Fine-tuning: 10-15 minutes
- Testing: 5 minutes
