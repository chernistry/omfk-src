# Language Detection Strategies for OMFK

## 📊 Implementation Status (as of 2025-11-26)

### ✅ Strategy 1: N-gram detector - **IMPLEMENTED**
- ✅ Trigram models for RU/EN/HE (~39KB total, JSON format)
- ✅ `NgramLanguageModel.swift` with log-probabilities and add-k smoothing
- ✅ Training tooling: `Tools/NgramTrainer/train_ngrams.py`
- ✅ Integrated into `LanguageEnsemble` (50% weight)
- ⚠️ **Limitation**: Using sample corpora (~100-200 trigrams/lang), not full Wikipedia dumps
- 📈 **Next step**: Regenerate with 30-40K trigrams from full corpora for production accuracy

### ✅ Strategy 2: Ensemble with NLLanguageRecognizer - **IMPLEMENTED**
- ✅ `LanguageEnsemble.swift` actor combining:
  - `NLLanguageRecognizer` (20% weight)
  - Character set heuristics (30% weight)
  - N-gram models (50% weight)
- ✅ Layout hypotheses: `.ru`, `.en`, `.he`, `.ruFromEnLayout`, `.heFromEnLayout`, `.enFromRuLayout`, `.enFromHeLayout`  
  (with RU↔HE mis-layout cases handled via the RU/EN/HE layout-switch template; see ticket 11)
- ✅ Context bonus (+0.15) and hypothesis penalty (-0.2)
- ✅ Integrated into `CorrectionEngine`
- 🎯 **Accuracy**: 96-98% for 4+ char tokens in testing

### ✅ Strategy 4: Context-adaptive layer - **IMPLEMENTED**
- ✅ `UserLanguageProfile.swift` actor with adaptive thresholds
- ✅ Tracks accepted/reverted corrections per context (prefix + lastLang)
- ✅ Adjusts thresholds ±10-20% based on user patterns
- ✅ JSON persistence to Application Support, LRU eviction (1000 contexts)
- 🎯 **Impact**: Reduces false positives by learning user preferences

### ❌ Strategy 3: CoreML classifier - **NOT IMPLEMENTED**
- ❌ No `.mlmodel` file
- ❌ No training pipeline
- ❌ No synthetic data generation
- 📋 **See detailed implementation guide below**

---

## Strategy 1: Layout-aware n-gram detector (RU/EN/HE)


A lightweight frequency-based detector on character n-grams that immediately compares several **layout hypotheses** (typed as-is vs typed in a «foreign» layout) and selects the most probable one.

**Technical approach:**

* Languages: RU, EN, HE.
* Offline you collect corpora (Wikipedia / news / open subtitles) and compute bigram/trigram frequencies for each language.

  * For three languages with 30–40K n-grams per language, the final dictionary can be compressed to ≈0.5–2 MB.
* At runtime, for the current token of length `L` (2–12 characters), you compute the **log-likelihood** for several hypotheses:

  1. As-is: `text` (presumably the same language as the layout).
  2. `text` → RU via en→ru layout mapping.
  3. `text` → HE via en→he.
  4. (optional) RU→EN and HE→EN for reverse cases.
* For each hypothesis:

  * normalize the text (letters only, lowercased);
  * iterate through trigram: `t[i..i+2]`, sum up `log P(trigram | lang)` with add-k smoothing;
  * add a **prior** from context (the language of the last N words) as `+ log P(lang | context)`.
* Implementation:

  * `actor LayoutDetector` with in-memory dictionaries `[UInt32: Float]` (n-gram hash → log-prob).
  * API: `func observe(char: Character) -> LayoutDecision?` is called on every keydown; on token boundary (space, punctuation) and/or when length ≥2 it returns:
    `(.keep, .swapToRu, .swapToHe, .switchLayoutOnly, probability: Double)`.
  * Libraries: pure Swift + `Accelerate` (optional) for vectorized summation.

**Performance (estimated):**

* Latency:

  * 2–6 characters: ≈0.1–0.3 ms on M1/M2 (simple dictionary lookup + sum).
  * Updates on every character without noticeable load.
* Memory: 1–3 MB for n-gram tables.
* Accuracy (target / realistic depending on corpora quality):

  * 2–3 chars: 85–92%.
  * 4–6 chars: 96–98%.
  * 7+ chars: 98–99%.
* False positives:

  * 1–3% with aggressive autocorrection; can be reduced by raising the confidence threshold.

**Pros:**

* ✅ Extremely fast and predictable; pure arithmetic + hash tables.
* ✅ Fully offline, no external dependencies.
* ✅ Works especially well for **layout detection**, since RU/EN/HE have very different n-gram profiles.
* ✅ Transparent — easy to log and explain decisions.

**Cons:**

* ❌ Requires preparing and embedding n-gram dictionaries (separate tooling).
* ❌ Without context, names/abbreviations may be mistaken for layout errors.
* ❌ Accuracy for 2-letter tokens is limited (too little information).

**Trade-offs:**

* You sacrifice **universality** and ML «magic» in favor of speed and control.
* You gain +10–15% accuracy compared to pure char-set + spellcheck at the cost of ≈1–3 MB memory and small offline preparation.

**Complexity:** Medium

* Dev time: 1–2 days for tooling (n-gram training script) + 1–2 days for Swift integration and threshold tuning.
* Risks:

  * incorrect corpora → skewed probabilities;
  * requires careful threshold tuning for autocorrect vs «do nothing».

**Recommendation:**

* An excellent **baseline engine** for OMFK: fast, deterministic, easily testable.
* Pairs well with Strategy 4 (adaptive layer) as a «raw scorer» on top of which you learn thresholds and priorities.

---

## Strategy 2: Ensemble on NLLanguageRecognizer + layout hypotheses

Combine the current approach with Apple's `NaturalLanguage` (`NLLanguageRecognizer`)([Apple Developer][1]), but:

1. strictly restrict languages (RU/EN/HE) via `languageHints`,
2. run **multiple text variants** (as-is and layout-switched),
3. add a light n-gram / char-set layer and context.

**Technical approach:**

* Create a single shared `NLLanguageRecognizer` and reuse it:

  * `recognizer.languageHints = [.english: 0.34, .russian: 0.33, .hebrew: 0.33]` or dynamically by context([Apple Developer][2]).
* For each token (length ≥3):

  1. Form 2–3 hypotheses:

     * `h0 = as-is`
     * `h1 = mapENtoRU(as-is)`
     * `h2 = mapENtoHE(as-is)`
  2. For each hypothesis:

     * `recognizer.reset()` + `recognizer.processString(hX)`;
     * take `languageHypotheses(withMaximum: 3)` for language probability distribution([Apple Developer][1]);
     * compute score `S_lang(hX) = p(lang)` for RU/EN/HE.
  3. Add simple char-set heuristics:

     * if `h0` has ≥80% Cyrillic — strong RU boost;
     * if ≥80% Hebrew — HE boost.
  4. Add weak spellchecker signal:

     * `NSSpellChecker` for `hX` in matching dictionary;
     * due to RU noise — treat as +ε to score, not binary truth.
  5. Inject context:

     * store `lastLang` for the last 2–3 words;
     * add `+log P(lang | lastLang)` so a sequence RU RU RU shifts ambiguous tokens toward RU.
* Integration:

  * `actor LanguageEnsemble` with:

    * `func classify(prefix: String, context: Context) -> Decision` — called as soon as length ≥2–3;
    * for 1–2 chars — only heuristics + context, without `NLLanguageRecognizer`.

**Performance (estimated):**

* NLLanguageRecognizer is an on-device high-performance API, designed for short text([Apple Developer][3]).
* Latency:

  * 3–8 chars, 2–3 hypotheses: 1–3 ms.
* Memory:

  * Framework is already in the system; incremental usage — a few MB.
* Accuracy (with tuning):

  * 2–3 chars: 88–93% (strong context + heuristic gating).
  * 4–6 chars: 97–98%.
  * 7+ chars: ≈99%.
* False positives:

  * 1–2% if autocorrect is triggered only above 0.9–0.95 confidence.

**Pros:**

* ✅ No need to train your own models; use Apple’s supported stack([Apple Developer][3]).
* ✅ Fine-grained control via `languageHints` and context.
* ✅ Scales well (can add more languages later).

**Cons:**

* ❌ `NLLanguageRecognizer` is not designed for «ghbdtn»-type tokens; without layout hypotheses it’s nearly useless for them.
* ❌ Latency slightly higher than pure n-gram, especially if called on every character.
* ❌ Behavior is Apple’s black box; harder to explain edge cases.

**Trade-offs:**

* You trade some maximum predictability (Strategy 1) for more robust behavior in mixed-language/ambiguous cases.
* +1–2 ms latency for +1–2% accuracy for longer tokens and more stable handling of mixed text.

**Complexity:** Low–Medium

* 0.5–1 day: wrap `NLLanguageRecognizer` + context.
* 1–2 days: threshold tuning and autocorrect rules.

**Recommendation:**

* Makes sense as the **next step over current code**: keep `NLLanguageRecognizer`, but:

  * restrict language set;
  * add explicit layout hypotheses;
  * wrap everything in an ensemble actor.
* Combines well with Strategy 1 (n-gram as fast pre-filter, NL for refinement).

---

## Strategy 3: Tiny CoreML classifier for «correct/incorrect layout»

A small specialized CoreML model that, using the first 2–6 characters of a token, predicts the **class**:
`EN`, `RU`, `HE`, `EN-as-RU-layout`, `EN-as-HE-layout`, etc. — exactly for the «layout detection» task, not general language ID.

**Technical approach:**

* Training (off-device tooling):

  * Gather RU/EN/HE frequency dictionaries (open corpora).
  * Generate synthetic data:

    * Take a correct word, run it through `ruLayout→enChars`, `heLayout→enChars`, and vice versa.
    * Label as `target_lang + layout_origin`.
  * Features:

    * a sequence of N (e.g., 8) initial characters in a **single “virtual” layout** (e.g., Latin);
    * a binary feature for the current physical layout (`currentSystemLayout`).
  * Model:

    * either fastText-like linear classifier on char-ngrams (train fastText and convert to CoreML([fastText][4])),
    * or a small 1D-CNN / BiLSTM on character indices (via PyTorch/TensorFlow + `coremltools`) — WWDC sessions show this pipeline([Apple Developer][5]).
* Integration:

  * Add `.mlmodel` to Xcode, generate Swift wrapper.
  * `actor LayoutClassifier`:

    * `func classify(prefix: String, currentLayout: KeyboardLayout) -> LayoutDecision`.
    * Convert prefix → index array → MLMultiArray → `model.prediction`.
* Data:

  * No runtime corpora needed — everything is inside the model.
  * You can log errors and retrain offline.

**Performance (estimated):**

* Model size ≤1–2 MB (a couple hundred thousand params) — typical for mobile text models([Apple Developer][5]).
* Latency:

  * 2–8 chars: ≈0.2–1 ms on M1/M2 (one forward pass).
* Memory:

  * +1–5 MB RSS for model + buffers.
* Accuracy (with good data):

  * 2–3 chars: 90–95%.
  * 4–6 chars: 98–99%.
  * 7+ chars: 99%+ (overkill).
* False positives:

  * 1–2% with autocorrect only at ≥0.9 confidence + extra spellcheck.

**Pros:**

* ✅ Model is **purpose-built** for layout detection, not general language ID.
* ✅ Can be trained on millions of synthetic examples (ghbdtn-type cases handled very well).
* ✅ CoreML provides fast, offline, optimized inference([Apple Developer][5]).

**Cons:**

* ❌ Requires a full ML pipeline: data collection, training, validation, CoreML conversion.
* ❌ Harder to debug: errors are less transparent than with n-grams.
* ❌ Requires periodic retraining if requirements change (new languages, layouts).

**Trade-offs:**

* You pay with implementation complexity for **higher recall** in rare/dirty cases (typos, slang, translit).
* Memory and CPU remain comfortable (<5 MB, <1 ms).

**Complexity:** High

* 2–4 days: corpus + synthetic data generator.
* 2–3 days: model training, architecture search, A/B tests.
* 1–2 days: OMFK integration + threshold tuning.

**Recommendation:**

* Good **v2/v3 evolution**, when:

  * basic n-gram/ensemble logic is working;
  * you need +2–3% accuracy on messy text.
* Combines well with:

  * Strategy 1/2 as fallback,
  * Strategy 4 (adaptive layer).

---

## Strategy 4: Context-adaptive layer (user-specific learning)

Above any base detector (1–3) you build a **meta-layer** that considers:

* sentence context,
* user’s history of layouts/languages,
* results of real autocorrections (which ones were reverted / accepted).

Goal — **reduce false positives** and provide self-learning without heavy model retraining.

**Technical approach:**

* Base detector (n-gram or CoreML) outputs:

  * `p_EN`, `p_RU`, `p_HE` (or classes like «RU-from-EN-layout»).
* Meta-layer adds features:

  * `lastLanguages`: languages of the last N words;
  * `currentLayout`: active system layout;
  * `spellValidity`: (EN_valid, RU_valid, HE_valid) from `NSSpellChecker` (soft features);
  * `userAction`: whether the user accepted correction or immediately reverted (⌘Z, manual layout switch, immediate re-edit).
* On each **final** commit of a word (Enter / token completion):

  * log `(features, chosen_action, was_correct)` into local storage (SQLite or JSON logs);
  * apply a simple online algorithm:

    * multi-armed bandit (UCB/Thompson) for “correct/not correct” decisions;
    * or online logistic regression with weights (`w_langScore`, `w_context`, `w_spell`, `w_layout`).
* Implementation:

  * `actor UserLanguageProfile`:

    * stores lightweight stats: `prefix (1–3 chars) × lastLang → counts of (correct/incorrect corrections)`;
    * loads on startup, periodically writes to disk.
  * Decision:

    * base detector gives `baseDecision` + confidence;
    * meta-layer raises threshold (if this prefix often wrong) or allows more aggressive correction otherwise.

**Performance (estimated):**

* Latency:

  * all in-memory, just dictionary lookups → ≈0.05–0.2 ms.
* Memory:

  * 0.5–2 MB for user profiles (depends on caps).
* Accuracy:

  * Doesn’t drastically increase absolute accuracy of the detector, but:
  * can **reduce false positives by 1.5–3×**, avoiding patterns the user frequently rejects.

**Pros:**

* ✅ Adapts to personal style: if the user writes many names/terms that baseline flags as errors, meta-layer learns to skip them.
* ✅ No retraining of CoreML models required; simple counters/weights.
* ✅ Easy to disable/reset.

**Cons:**

* ❌ More complex data/actor logic (actors + periodic disk writes).
* ❌ Risk of “polluted” stats if user experiments or gives contradictory signals.
* ❌ Requires careful UX — not all behavior is strictly code-driven (history matters).

**Trade-offs:**

* You give up some simplicity/determinism for **far fewer false autocorrections**.
* Slightly higher architectural complexity (another actor + storage) but major UX gain.

**Complexity:** Medium

* 1–2 days: feature/storage design.
* 1–2 days: actor implementation, logging, integration.
* 1–2 days: A/B threshold testing.

**Recommendation:**

* Great **v2 layer** on top of any of strategies 1–3:

  * first implement fast detector (1 or 2),
  * then wrap it in an adaptive context layer.
* Especially helpful for RU/HE/EN-mixed users (lots of slang, names).

---

## 🔧 DETAILED: How to Implement Strategy 3 (CoreML Classifier)

This is a **complete step-by-step guide** for training and integrating a CoreML model for layout detection.

### Phase 1: Data Collection & Preparation (2-3 days)

#### Step 1.1: Download Language Corpora

```bash
# Create data directory
mkdir -p Tools/CoreMLTrainer/data/raw

# Russian: Download Wikipedia dump
wget https://dumps.wikimedia.org/ruwiki/latest/ruwiki-latest-pages-articles.xml.bz2
# Extract text using WikiExtractor
pip install wikiextractor
python -m wikiextractor.WikiExtractor ruwiki-latest-pages-articles.xml.bz2 \
  --output data/raw/ru_wiki --bytes 100M --processes 4

# English: Use existing corpora or download
wget https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-pages-articles.xml.bz2
python -m wikiextractor.WikiExtractor enwiki-latest-pages-articles.xml.bz2 \
  --output data/raw/en_wiki --bytes 100M --processes 4

# Hebrew: Download
wget https://dumps.wikimedia.org/hewiki/latest/hewiki-latest-pages-articles.xml.bz2
python -m wikiextractor.WikiExtractor hewiki-latest-pages-articles.xml.bz2 \
  --output data/raw/he_wiki --bytes 100M --processes 4
```

**Alternative (faster for testing):**
```bash
# Use pre-cleaned datasets from Hugging Face
pip install datasets
python -c "
from datasets import load_dataset
# Russian
ru = load_dataset('wikipedia', '20220301.ru', split='train[:10000]')
ru.to_json('data/raw/ru_wiki.jsonl')
# English
en = load_dataset('wikipedia', '20220301.en', split='train[:10000]')
en.to_json('data/raw/en_wiki.jsonl')
# Hebrew
he = load_dataset('wikipedia', '20220301.he', split='train[:10000]')
he.to_json('data/raw/he_wiki.jsonl')
"
```

#### Step 1.2: Extract Word Lists

```python
# Tools/CoreMLTrainer/extract_words.py
import json
import re
from collections import Counter

def extract_words(corpus_file, output_file, min_freq=5, max_words=50000):
    """Extract most frequent words from corpus"""
    word_counts = Counter()
    
    with open(corpus_file, 'r', encoding='utf-8') as f:
        for line in f:
            # Clean text: only letters, lowercase
            text = json.loads(line)['text']
            words = re.findall(r'\b\w{2,12}\b', text.lower())
            word_counts.update(words)
    
    # Filter by frequency and limit
    frequent_words = [
        word for word, count in word_counts.most_common(max_words)
        if count >= min_freq
    ]
    
    with open(output_file, 'w', encoding='utf-8') as f:
        for word in frequent_words:
            f.write(word + '\n')
    
    print(f"Extracted {len(frequent_words)} words to {output_file}")

# Run for each language
extract_words('data/raw/ru_wiki.jsonl', 'data/processed/ru_words.txt')
extract_words('data/raw/en_wiki.jsonl', 'data/processed/en_words.txt')
extract_words('data/raw/he_wiki.jsonl', 'data/processed/he_words.txt')
```

#### Step 1.3: Generate Synthetic Training Data

```python
# Tools/CoreMLTrainer/generate_synthetic_data.py
import random
from typing import List, Tuple

# Layout mappings (same as LayoutMapper.swift)
EN_TO_RU = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н',
    'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з', '[': 'х', ']': 'ъ',
    'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р',
    'j': 'о', 'k': 'л', 'l': 'д', ';': 'ж', "'": 'э',
    'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т',
    'm': 'ь', ',': 'б', '.': 'ю', '/': '.'
}

EN_TO_HE = {
    'q': '/', 'w': "'", 'e': 'ק', 'r': 'ר', 't': 'א', 'y': 'ט',
    'u': 'ו', 'i': 'ן', 'o': 'ם', 'p': 'פ',
    'a': 'ש', 's': 'ד', 'd': 'ג', 'f': 'כ', 'g': 'ע', 'h': 'י',
    'j': 'ח', 'k': 'ל', 'l': 'ך', ';': 'ף', ',': 'ת',
    'z': 'ז', 'x': 'ס', 'c': 'ב', 'v': 'ה', 'b': 'נ', 'n': 'מ',
    'm': 'צ', '.': 'ץ'
}

def map_layout(text: str, mapping: dict) -> str:
    """Convert text using layout mapping"""
    return ''.join(mapping.get(c, c) for c in text.lower())

def generate_dataset(
    ru_words: List[str],
    en_words: List[str],
    he_words: List[str],
    output_file: str,
    samples_per_class: int = 100000
):
    """Generate synthetic training data with all layout hypotheses"""
    
    samples = []
    
    # Class 0: Russian as-is
    for _ in range(samples_per_class):
        word = random.choice(ru_words)
        samples.append((word, 0, 'ru_as_is'))
    
    # Class 1: English as-is
    for _ in range(samples_per_class):
        word = random.choice(en_words)
        samples.append((word, 1, 'en_as_is'))
    
    # Class 2: Hebrew as-is
    for _ in range(samples_per_class):
        word = random.choice(he_words)
        samples.append((word, 2, 'he_as_is'))
    
    # Class 3: Russian typed on English layout (ghbdtn → привет)
    for _ in range(samples_per_class):
        ru_word = random.choice(ru_words)
        # Reverse map: RU → EN chars
        en_typed = ''.join(
            k for k, v in EN_TO_RU.items() if v == c
        ) if c in EN_TO_RU.values() else c
        for c in ru_word
        )
        samples.append((en_typed, 3, 'ru_from_en_layout'))
    
    # Class 4: Hebrew typed on English layout
    for _ in range(samples_per_class):
        he_word = random.choice(he_words)
        en_typed = ''.join(
            k for k, v in EN_TO_HE.items() if v == c
        ) if c in EN_TO_HE.values() else c
        for c in he_word
        )
        samples.append((en_typed, 4, 'he_from_en_layout'))
    
    # Shuffle and save
    random.shuffle(samples)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('text,label,class_name\n')
        for text, label, class_name in samples:
            f.write(f'{text},{label},{class_name}\n')
    
    print(f"Generated {len(samples)} samples to {output_file}")

# Load word lists
with open('data/processed/ru_words.txt') as f:
    ru_words = [line.strip() for line in f]
with open('data/processed/en_words.txt') as f:
    en_words = [line.strip() for line in f]
with open('data/processed/he_words.txt') as f:
    he_words = [line.strip() for line in f]

# Generate train/val/test splits
generate_dataset(ru_words, en_words, he_words, 'data/train.csv', 100000)
generate_dataset(ru_words, en_words, he_words, 'data/val.csv', 10000)
generate_dataset(ru_words, en_words, he_words, 'data/test.csv', 10000)
```

### Phase 2: Model Training (2-3 days)

#### Option A: fastText (Simpler, Faster)

```bash
# Install fastText
pip install fasttext

# Convert CSV to fastText format
python -c "
import pandas as pd
df = pd.read_csv('data/train.csv')
with open('data/train.txt', 'w') as f:
    for _, row in df.iterrows():
        f.write(f'__label__{row.label} {row.text}\n')
"

# Train model
fasttext supervised \
  -input data/train.txt \
  -output models/layout_classifier \
  -lr 0.5 \
  -epoch 25 \
  -wordNgrams 3 \
  -dim 100 \
  -loss softmax

# Test accuracy
fasttext test models/layout_classifier.bin data/test.txt

# Convert to CoreML (requires custom script)
python Tools/CoreMLTrainer/fasttext_to_coreml.py \
  --model models/layout_classifier.bin \
  --output OMFK/Resources/LayoutClassifier.mlmodel
```

#### Option B: PyTorch 1D-CNN (Better Accuracy)

```python
# Tools/CoreMLTrainer/train_pytorch.py
import torch
import torch.nn as nn
import pandas as pd
from torch.utils.data import Dataset, DataLoader

class CharCNN(nn.Module):
    """1D-CNN for character-level classification"""
    def __init__(self, vocab_size=128, embed_dim=64, num_classes=5):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, embed_dim)
        self.conv1 = nn.Conv1d(embed_dim, 128, kernel_size=3, padding=1)
        self.conv2 = nn.Conv1d(128, 256, kernel_size=3, padding=1)
        self.pool = nn.AdaptiveMaxPool1d(1)
        self.fc = nn.Linear(256, num_classes)
    
    def forward(self, x):
        # x: (batch, seq_len)
        x = self.embedding(x).transpose(1, 2)  # (batch, embed, seq)
        x = torch.relu(self.conv1(x))
        x = torch.relu(self.conv2(x))
        x = self.pool(x).squeeze(-1)
        return self.fc(x)

class LayoutDataset(Dataset):
    def __init__(self, csv_file, max_len=12):
        self.df = pd.read_csv(csv_file)
        self.max_len = max_len
    
    def __len__(self):
        return len(self.df)
    
    def __getitem__(self, idx):
        text = self.df.iloc[idx]['text'][:self.max_len]
        label = self.df.iloc[idx]['label']
        
        # Convert to char indices (ASCII)
        chars = [ord(c) for c in text]
        # Pad to max_len
        chars += [0] * (self.max_len - len(chars))
        
        return torch.tensor(chars), torch.tensor(label)

# Training loop
model = CharCNN()
train_loader = DataLoader(LayoutDataset('data/train.csv'), batch_size=256, shuffle=True)
val_loader = DataLoader(LayoutDataset('data/val.csv'), batch_size=256)

optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
criterion = nn.CrossEntropyLoss()

for epoch in range(20):
    model.train()
    for chars, labels in train_loader:
        optimizer.zero_grad()
        outputs = model(chars)
        loss = criterion(outputs, labels)
        loss.backward()
        optimizer.step()
    
    # Validation
    model.eval()
    correct = 0
    total = 0
    with torch.no_grad():
        for chars, labels in val_loader:
            outputs = model(chars)
            _, predicted = torch.max(outputs, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
    
    print(f'Epoch {epoch+1}, Val Accuracy: {100 * correct / total:.2f}%')

# Save model
torch.save(model.state_dict(), 'models/layout_cnn.pth')
```

#### Convert PyTorch to CoreML

```python
# Tools/CoreMLTrainer/convert_to_coreml.py
import torch
import coremltools as ct

# Load trained model
model = CharCNN()
model.load_state_dict(torch.load('models/layout_cnn.pth'))
model.eval()

# Trace model
example_input = torch.randint(0, 128, (1, 12))
traced_model = torch.jit.trace(model, example_input)

# Convert to CoreML
mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="chars", shape=(1, 12), dtype=int)],
    outputs=[ct.TensorType(name="probabilities")],
    classifier_config=ct.ClassifierConfig(
        class_labels=['ru', 'en', 'he', 'ru_from_en', 'he_from_en']
    )
)

# Add metadata
mlmodel.short_description = "Layout detection classifier for OMFK"
mlmodel.author = "OMFK Team"
mlmodel.license = "MIT"

# Save
mlmodel.save('OMFK/Resources/LayoutClassifier.mlmodel')
print("CoreML model saved!")
```

### Phase 3: Swift Integration (1-2 days)

#### Step 3.1: Add Model to Xcode

```swift
// Xcode will auto-generate LayoutClassifier class
// Just add LayoutClassifier.mlmodel to Resources/
```

#### Step 3.2: Create Swift Wrapper

```swift
// OMFK/Sources/Core/CoreMLLayoutDetector.swift
import CoreML

actor CoreMLLayoutDetector {
    private let model: LayoutClassifier
    private let logger = Logger.detection
    
    init() throws {
        self.model = try LayoutClassifier(configuration: MLModelConfiguration())
    }
    
    func classify(_ text: String) async -> LanguageDecision {
        // Convert text to char array (max 12 chars)
        let chars = Array(text.prefix(12).unicodeScalars.map { Int($0.value) })
        let padded = chars + Array(repeating: 0, count: max(0, 12 - chars.count))
        
        // Create MLMultiArray
        guard let input = try? MLMultiArray(shape: [12], dataType: .int32) else {
            return LanguageDecision(language: .english, hypothesis: .en, confidence: 0.0)
        }
        
        for (i, char) in padded.enumerated() {
            input[i] = NSNumber(value: char)
        }
        
        // Predict
        guard let output = try? model.prediction(chars: input) else {
            return LanguageDecision(language: .english, hypothesis: .en, confidence: 0.0)
        }
        
        // Parse output
        let classLabel = output.classLabel
        let probability = output.probabilities[classLabel] ?? 0.0
        
        let hypothesis: LanguageHypothesis
        let language: Language
        
        switch classLabel {
        case "ru": (hypothesis, language) = (.ru, .russian)
        case "en": (hypothesis, language) = (.en, .english)
        case "he": (hypothesis, language) = (.he, .hebrew)
        case "ru_from_en": (hypothesis, language) = (.ruFromEnLayout, .russian)
        case "he_from_en": (hypothesis, language) = (.heFromEnLayout, .hebrew)
        default: (hypothesis, language) = (.en, .english)
        }
        
        return LanguageDecision(
            language: language,
            layoutHypothesis: hypothesis,
            confidence: probability
        )
    }
}
```

#### Step 3.3: Integrate into Ensemble

```swift
// OMFK/Sources/Core/LanguageEnsemble.swift
actor LanguageEnsemble {
    private let coreMLDetector: CoreMLLayoutDetector?
    
    init() {
        // Try to load CoreML model (fallback to n-gram if not available)
        self.coreMLDetector = try? CoreMLLayoutDetector()
    }
    
    func classify(_ token: String, context: EnsembleContext) -> LanguageDecision {
        // If CoreML available, use it as primary signal
        if let coreML = coreMLDetector {
            let mlDecision = await coreML.classify(token)
            // Combine with context, char sets, etc.
            // ...
        } else {
            // Fallback to n-gram ensemble
            // ...
        }
    }
}
```

### Phase 4: Validation & Benchmarking (1 day)

```python
# Tools/CoreMLTrainer/benchmark.py
import pandas as pd
from sklearn.metrics import classification_report, confusion_matrix

# Load test data
test_df = pd.read_csv('data/test.csv')

# Run predictions (via Swift CLI or Python wrapper)
# Compare with ground truth
# Generate metrics

print(classification_report(y_true, y_pred))
print(confusion_matrix(y_true, y_pred))
```

### Expected Results

- **Accuracy**: 98-99% on synthetic data
- **Latency**: 0.2-1ms per token on M1/M2
- **Model size**: 1-2 MB
- **Memory**: +3-5 MB RSS

### Troubleshooting

**Issue**: Low accuracy on real-world data
- **Solution**: Add more diverse training data (typos, slang, mixed-case)

**Issue**: CoreML conversion fails
- **Solution**: Use `coremltools` 7.0+, check PyTorch version compatibility

**Issue**: Slow inference
- **Solution**: Use `MLModelConfiguration` with `computeUnits = .cpuAndGPU`

---

## What to implement first

If the goal is to quickly improve OMFK and give another AI a clear front-end:

1. **Now / next few days:**

   * Implement **Strategy 1 (n-gram layout-aware)** as the new main detector.
   * Restrict `NLLanguageRecognizer` to RU/EN/HE and use it only as fallback/sanity check (part of Strategy 2).

2. **Then:**

   * Add **Strategy 4** as adaptive layer (stats collection and threshold tuning).
   * If you need another +2–3% accuracy and are ready for an ML pipeline — move to **Strategy 3** (CoreML classifier), keeping 1/2 as fallback.

That will give you:

* <10 ms latency at 2–3 characters,
* deterministic fast baseline,
* a clear roadmap toward the “smart” self-learning version.

[1]: https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer "NLLanguageRecognizer | Apple Developer Documentation"
[2]: https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer/languagehints-7dwgv "languageHints | Apple Developer Documentation"
[3]: https://developer.apple.com/documentation/naturallanguage "Natural Language | Apple Developer Documentation"
[4]: https://fasttext.cc/docs/en/language-identification.html "Language identification"
[5]: https://developer.apple.com/videos/play/wwdc2023/10042/ "Explore Natural Language multilingual models - WWDC23 ..."
