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
