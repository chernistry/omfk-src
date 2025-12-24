# Ticket 22: Maximize Training Data Utilization

Spec version: v1.0

## Context

The current training pipeline has a critical inefficiency:

**Available Data:**
- `data/processed/ru.txt`: ~55 million words (from Wikipedia + Telegram)
- `data/processed/en.txt`: ~66 million words
- `data/processed/he.txt`: ~43 million words

**Currently Used:**
- `generate_data.py --count 100000` → only 100,000 training samples
- This means we're using **<0.1%** of available data!

## Objective

1. Maximize CoreML training data utilization
2. Ensure N-gram models are trained on full corpora
3. Improve data generation quality and diversity

## Definition of Done

### Phase 1: Increase Sample Count

- [ ] **Increase `--count` in `train_master.sh`**:
  - Current: 100,000 samples
  - Target: 1,000,000+ samples (memory permitting)
  - Or: Generate in batches if memory is an issue

- [ ] **Benchmark Training Time**:
  - Test with 100k, 500k, 1M, 5M samples
  - Find optimal count for accuracy vs. time tradeoff

### Phase 2: Smarter Sampling

- [ ] **Weighted Class Sampling**:
  - Current: 66% `_from_` classes, 34% pure language
  - Target: 50/50 balance or configurable

- [ ] **Diverse Phrase Lengths**:
  - Current: 1-2 words per sample
  - Target: 1-5 words with varied distribution

- [ ] **Include Punctuation and Numbers**:
  - Realistic text includes `hello!`, `привет?`, `123`

### Phase 3: N-gram Training Verification

- [ ] **Verify Full Corpus Usage**:
  - `train_ngrams.py` should process ALL lines in corpus files
  - Current implementation already does this ✓
  - But verify trigram coverage is comprehensive

- [ ] **Increase Trigram Vocabulary**:
  - Current: ~17k-44k unique trigrams per language
  - Consider: Higher-order n-grams (4-grams, 5-grams)?

### Phase 4: Data Augmentation

- [ ] **Typo Injection**:
  - Randomly insert typos (swap, delete, duplicate chars)
  - Train model to handle imperfect input

- [ ] **Case Variation**:
  - Mix uppercase, lowercase, title case

## Changes to `generate_data.py`

```python
# Current:
parser.add_argument('--count', type=int, default=10000)

# New:
parser.add_argument('--count', type=int, default=1000000)
parser.add_argument('--balance', type=float, default=0.5, help="Ratio of _from_ samples")
parser.add_argument('--max-phrase-len', type=int, default=5)
parser.add_argument('--typo-rate', type=float, default=0.1)
```

## Changes to `train_master.sh`

```bash
# Current:
python3 generate_data.py --count 100000 --output training_data_real.csv

# New:
python3 generate_data.py --count 1000000 --balance 0.5 --output training_data_real.csv
```

## Suggested External Datasets

For better Hebrew and Russian coverage, consider:

1. **OpenSubtitles**: Conversational text in multiple languages
   - https://opus.nlpl.eu/OpenSubtitles.php

2. **Tatoeba**: Short sentences for language learning
   - https://tatoeba.org/en/downloads

3. **Common Crawl**: Web text (needs filtering)
   - https://commoncrawl.org/

4. **Hebrew-specific**:
   - https://github.com/NLPH/NLPH_Resources

5. **Russian-specific**:
   - https://ruscorpora.ru/ (National Corpus of Russian)

## Files to Modify

- `Tools/CoreMLTrainer/generate_data.py`
- `train_master.sh`
- `Tools/CoreMLTrainer/train.py` (if memory optimizations needed)

## Dependencies

- Ticket 19 (testing to measure improvement)

## Priority

**P1 — HIGH** — Low-hanging fruit for significant accuracy improvement.
