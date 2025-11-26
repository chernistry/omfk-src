# Ticket: 11 N-gram training tooling and model assets

Spec version: v1.0 / strategies.md#strategy-1

## Context
- Strategy 1 requires precomputed n-gram frequency tables for RU/EN/HE from external corpora.
- OMFK is a local macOS app; the heavy training/tooling can live in a separate CLI/utility (possibly another repo), but the **resulting tables** must be embedded in the app.
- Architect spec and DoD require:
  - offline operation (no network),
  - predictable memory footprint.

This ticket covers **offline tooling** and **asset format** for trigram tables used by `LayoutNgramDetector`.

## Objective & Definition of Done
- Provide a small, reproducible training pipeline that:
  - ingests corpora for RU/EN/HE (plain text),
  - computes normalised bigram/trigram frequencies,
  - exports **compressed trigram log-probability tables** for each language in a format consumable by OMFK (ticket 10).
- Integrate exported tables into the Xcode project as resources.

Acceptance criteria:
- A script or small tool exists (language flexible: Swift, Python, etc.) with:
  - CLI interface: `train-ngrams --lang ru --input <file> --output <file>`.
  - configurable n (ideally 3, but allow 2/4 for experimentation).
- Export format:
  - stable and documented (e.g. JSON with `"trigram": "abc", "logP": -x.xx` or compact binary).
  - includes simple header (version, language code, n, smoothing params).
- Documentation:
  - short `IMPLEMENTATION_NOTES.md` section or comment in the script describing:
    - corpus sources expected,
    - how to regenerate assets.

## Steps
1. **Define training spec**
   - Choose expected corpus format (one phrase per line, UTF-8).
   - Decide n-gram order (tri-grams) and smoothing method (e.g. add-k).
   - Document languages: `ru`, `en`, `he` codes and allowed alphabets.
2. **Implement training script/tool**
   - Parse input text; normalise to lowercased, letters-only.
   - Count trigrams per language; compute probabilities:
     - `P(trigram | lang) = (count + k) / (total + k * |V|)`.
   - Convert to log-probabilities and write to output.
3. **Design export format**
   - Start with JSON for clarity, e.g.:
     ```json
     {
       "lang": "ru",
       "n": 3,
       "version": 1,
       "trigrams": {
         "abc": -5.23,
         "bcd": -7.12
       }
     }
     ```
   - Optionally add a later path to a binary-packed format; keep JSON as the canonical reference for now.
4. **Integrate into OMFK project**
   - Decide on resource paths, e.g.:
     - `OMFK/Resources/LanguageModels/ru_trigrams.json`, etc.
   - Update project file / Package.swift to include them.
   - Provide a small loader stub used by `LayoutNgramDetector` (ticket 10).
5. **Add minimal validation tests**
   - Unit tests to:
     - load example tables and check expected fields present;
     - ensure there are non-zero counts and reasonable value ranges.

## Affected files/modules
- Tooling (new):
  - `Tools/NgramTrainer/*` (or similar).
- App:
  - `OMFK/Resources/LanguageModels/*.json` (or `.bin`).
- Docs:
  - `IMPLEMENTATION_NOTES.md` or `IMPLEMENTATION_STATUS.md` updated with a short section on n-gram assets.

## Tests
- Manual: run trainer script on small sample corpora and inspect output.
- Unit: loader tests for sample assets.

## Risks & Edge Cases
- Risk: corpora licensing / distribution.
  - Mitigation: use clearly permissive corpora or treat corpora as external to repo.
- Risk: JSON becomes too large / slow to load.
  - Mitigation: start with small tables; consider binary packing in a later ticket.

## Dependencies
- Upstream:
  - `.sdd/strategies.md` Strategy 1.
- Downstream:
  - Ticket 10 (detector consumes these assets).

