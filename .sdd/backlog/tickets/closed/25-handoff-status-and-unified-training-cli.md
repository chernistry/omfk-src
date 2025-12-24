# Ticket 25: Handoff Status + Unified Training/Release CLI (`omfk.sh`)

## Priority
HIGH — reduces day-to-day friction, prevents “what is trained vs stale?” confusion, and makes retraining/release reproducible for another agent.

## Status
Open

## Summary
The project currently has multiple overlapping entrypoints (`train_master.sh`, `train_all_models.sh`, `Tools/CoreMLTrainer/train_{quick,full}.sh`, `run_with_logs.sh`, `verify.sh`, `releases/build_release.sh`) and multiple model/data artifacts (processed corpora, generated CSVs, PyTorch checkpoints, exported CoreML, n-gram JSONs, unigram TSVs).  
Users (and future agents) get lost: what is already trained, what needs retraining, which dataset is authoritative, and what commands to run.

This ticket introduces:
1) A **single canonical CLI** script (proposed: `omfk.sh`) to manage corpus prep, n-grams, CoreML training/export, synthetic evaluation, and release build.  
2) A **status report command** that answers “what is current vs stale?” deterministically by reading file presence + timestamps + size + sanity checks.  
3) A **handoff snapshot** of current model/data status and known issues for another agent.

---

## Current Project State (Handoff Snapshot)

### 1) Processed corpora (authoritative text sources)
Location: `data/processed/`
- `ru.txt` (includes OpenSubtitles RU already merged earlier)
- `he.txt` (includes OpenSubtitles HE already merged earlier)
- `en.txt`
- `subtitles_ru.txt` / `subtitles_he.txt` were present historically but are now **expected to be merged** into `ru.txt`/`he.txt` and then deleted to avoid double-counting.

What “good” looks like:
- Only `ru.txt`, `he.txt`, `en.txt` exist (no `subtitles_*`), or if `subtitles_*` exist they are merged idempotently (no duplicate append).

### 2) N-gram language models (fast path + scoring)
Location: `OMFK/Sources/Resources/LanguageModels/`
- `ru_trigrams.json`, `en_trigrams.json`, `he_trigrams.json`

Notes:
- Current repo uses **trigrams**, not bigrams. Trigrams cannot score 2-letter tokens; those are handled via word validators/unigrams/heuristics.

### 3) Unigram word-frequency lexicons (word validity + disambiguation)
Location: `OMFK/Sources/Resources/LanguageModels/`
- `ru_unigrams.tsv`, `en_unigrams.tsv`, `he_unigrams.tsv`

Used for:
- disambiguation for ambiguous layouts (notably `hebrew_qwerty` letter duplicates)
- short token handling (2–3 letters)
- “is this a plausible word?” when macOS spellchecker dictionary is missing/weak (often Hebrew)

### 4) CoreML model (deep/layout-mismatch detector)
Location:
- `OMFK/Sources/Resources/LayoutClassifier.mlmodel`
- `Tools/CoreMLTrainer/LayoutClassifier.mlmodel` (should match when installed)

Architecture:
- Ensemble CNN + Transformer exported via TorchScript tracing.
- Export previously failed due to dynamic shape/control flow; the architecture has been made trace-compatible (fixed-length cropping + traceable transformer pieces).

### 5) CoreML training datasets / checkpoints
Location: `Tools/CoreMLTrainer/`
- `training_data_combined.csv` — **authoritative** combined training data (user merged “general + Hebrew”).
- `model_production.pth` — base checkpoint (may be stale or absent).
- `model_production_he_qwerty.pth` — optional fine-tuned checkpoint for Hebrew QWERTY sofits.

Important:
- Hebrew QWERTY sofits are present in the layout map. Whether fine-tuning is still needed depends on whether `training_data_combined.csv` already includes enough `he_qwerty` coverage. Fine-tune can remain as “insurance” but must be skippable.

### 6) Synthetic evaluation (program-level quality gate)
Location: `OMFK/Tests/SyntheticEvaluationTests.swift`
- Runs 9 combos (typed language/layout × intended language).
- Uses unigram lexicons for realistic word sampling.
- **Punctuation constraints**: only use punctuation that is layout-reversible across EN/RU/HE (e.g. `, . ! ? / ( )` depending on map) to avoid false negatives from non-stable characters.

Goal:
- `OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC` >= 98 (program-level output accuracy).

---

## Objective
Provide a single, simple, reproducible operational interface:
- “I just want to retrain everything and ship” → one command, minimal choices.
- “I want ultra mode / tweak sampling / skip finetune” → env/flags.
- “I want to know what’s stale” → `status` prints a clear answer.

---

## Definition of Done (DoD)

### A) Unified CLI (`omfk.sh`)
- [ ] Add `omfk.sh` at repo root as the canonical entrypoint.
- [ ] Subcommands (minimum):
  - [ ] `status` — prints state for corpora, n-grams, unigrams, CoreML model, datasets, checkpoints.
  - [ ] `corpus extract-wikipedia` — runs `Tools/Shared/extract_corpus.py` on dumps (if available).
  - [ ] `corpus download-subtitles` — downloads via `Tools/CoreMLTrainer/download_subtitles.py` and merges idempotently.
  - [ ] `train ngrams` — trains trigrams+unigrams from `data/processed/*.txt` by default.
  - [ ] `train coreml` — trains base CoreML model from dataset/corpus + exports + validates + installs into app resources.
  - [ ] `eval synthetic` — runs synthetic eval (with env knobs).
  - [ ] `test` — `swift test`
  - [ ] `release build` — builds `.app` + `.dmg` (delegating to `releases/build_release.sh` or re-implementing).
  - [ ] `run` / `logs` convenience (optional)
- [ ] Supports `--ultra` flag (or `OMFK_ULTRA=1`) to crank up samples/epochs and set “use all corpus words”.
- [ ] Supports `--yes` / non-interactive mode for CI-ish automation (no prompts).

### B) Deprecation / compatibility
- [ ] Existing scripts remain but become thin wrappers that call `omfk.sh`:
  - `train_master.sh`, `train_all_models.sh`, `Tools/CoreMLTrainer/train_{quick,full}.sh`, `verify.sh`, `run_with_logs.sh`, `view_logs.sh`, `test_logging.sh`, `releases/build_release.sh` (as applicable).
- [ ] `TRAINING.md` updated: clearly says “use `omfk.sh`”, keeps env knobs documented.

### C) Correctness + safety
- [ ] Idempotent subtitle merge (never double-appends).
- [ ] Training uses `training_data_combined.csv` by default if present.
- [ ] Hebrew QWERTY fine-tune is optional and can be skipped via env/flag.
- [ ] `bash -n` passes for all shell scripts touched.
- [ ] `swift test` passes.

---

## Implementation Notes / Design

### 1) Staleness rules (“do I need retrain?”)
`omfk.sh status` should compute:
- **Corpora status**:
  - Present: `data/processed/{ru,en,he}.txt`
  - Subtitles residual: `subtitles_{ru,he}.txt` present (warn)
- **N-grams/unigrams status**:
  - Present: all 6 model files
  - Stale if any model timestamp older than corresponding corpus file
- **CoreML status**:
  - Present: `OMFK/Sources/Resources/LayoutClassifier.mlmodel`
  - Stale if:
    - `Tools/CoreMLTrainer/train.py` or `export.py` newer than model, OR
    - layout spec (`OMFK/Sources/Resources/layouts.json`) newer than model, OR
    - user explicitly sets `OMFK_FORCE_RETRAIN=1`.
- **Dataset status**:
  - Present: `Tools/CoreMLTrainer/training_data_combined.csv`
  - If missing: generator must build from corpora and layout maps.

### 2) Data generation quality
`Tools/CoreMLTrainer/generate_data.py` now supports:
- `--max-corpus-words` (0 = load all words)
- `--corpus-sample-mode reservoir` to avoid biased “head-of-file” sampling

Guidance:
- For best quality, prefer reservoir sampling with a large cap (or 0).
- Ensure 2-letter words are included; they matter (e.g. Hebrew “מה”, “לא”).

### 3) CoreML fine-tune decision
If `training_data_combined.csv` already includes rich `he_qwerty` samples (including sofits), then:
- fine-tune is optional (insurance against class imbalance)
- allow skipping via `OMFK_SKIP_HE_QWERTY_FINETUNE=1`

If the combined dataset is “mostly general” and `he_qwerty` coverage is weak:
- fine-tune stays enabled by default to push Hebrew QWERTY conversions.

### 4) Why no bigrams?
Trigrams were chosen to reduce false positives and give stronger language signal for 3+ characters.  
2-letter tokens are handled via:
- unigram lexicons + word validators
- short-token heuristics

Adding bigrams is possible, but should be justified with:
- measurable improvement on short tokens *without* increasing false positives.

---

## Steps

1) Add `omfk.sh` with subcommand routing and env/flag parsing.
2) Move/copy logic from `train_master.sh` into `omfk.sh` (keep `train_master.sh` as wrapper).
3) Update wrappers:
   - `train_all_models.sh` calls `./omfk.sh train all` (or similar).
   - `Tools/CoreMLTrainer/train_{quick,full}.sh` calls `../../omfk.sh train coreml --quick/--full`.
   - `verify.sh` calls `./omfk.sh verify` (fix stale file path assumptions).
   - `run_with_logs.sh` / `view_logs.sh` call `./omfk.sh logs stream`.
   - `releases/build_release.sh` either called by `./omfk.sh release build` or becomes wrapper itself.
4) Update `TRAINING.md` and `README.md` to document the new canonical flow.
5) Add “status” section to docs: what files to expect and what indicates staleness.
6) Run validations:
   - `bash -n` on scripts
   - `swift test`
   - optionally `./omfk.sh eval synthetic` with `OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC=98`

---

## Tests / Validation Commands
- `bash -n omfk.sh`
- `bash -n train_master.sh train_all_models.sh releases/build_release.sh Tools/CoreMLTrainer/train_full.sh Tools/CoreMLTrainer/train_quick.sh`
- `swift test`
- `OMFK_RUN_SYNTH_EVAL=1 OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC=98 swift test --filter SyntheticEvaluationTests/testSyntheticEvaluationIfEnabled`

---

## Risks
- Script refactor can break “muscle memory” → mitigate with wrappers + clear docs.
- Release packaging might miss runtime resources → ensure `.app` bundle contains `Resources/` and models.
- Over-aggressive auto-retrain rules can waste time → implement clear, overridable staleness rules.
- Ultra mode can be very slow / memory heavy → document expected runtimes and default caps.

---

## Dependencies
- Relies on existing:
  - `Tools/NgramTrainer/train_ngrams.py`, `Tools/NgramTrainer/train_unigrams.py`
  - `Tools/CoreMLTrainer/train.py`, `generate_data.py`, `export.py`, `validate_export.py`
  - `releases/build_release.sh`
  - Swift tests in `OMFK/Tests/*`

