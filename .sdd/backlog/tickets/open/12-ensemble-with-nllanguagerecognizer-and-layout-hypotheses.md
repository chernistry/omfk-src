# Ticket: 12 Ensemble with NLLanguageRecognizer and layout hypotheses (Strategy 2)

Spec version: v1.0 / strategies.md#strategy-2

## Context
- Strategy 2 in `.sdd/strategies.md` describes combining:
  - `NLLanguageRecognizer` (restricted to RU/EN/HE),
  - explicit layout hypotheses (as-is, EN→RU, EN→HE),
  - char-set heuristics and weak spellchecker signals,
  - short context (`lastLang`).
- Architecture: `.sdd/architect.md` — LanguageDetector component and DoD for language detection accuracy and latency.
- Ticket 10/11: introduce a layout-aware n-gram detector + assets.

This ticket builds a **LanguageEnsemble** that wraps Apple’s `NLLanguageRecognizer` and layout hypotheses into a unified decision engine.

## Objective & Definition of Done
- Implement a `LanguageEnsemble` actor (or similar) that:
  - holds a single `NLLanguageRecognizer` configured with RU/EN/HE hints;
  - for each token of length ≥3:
    - evaluates multiple hypotheses (`h0`: as-is, `h1`: EN→RU, `h2`: EN→HE, etc.);
    - obtains per-hypothesis language probabilities from `NLLanguageRecognizer`;
    - combines them with:
      - character-set heuristics,
      - optional spellchecker signals,
      - recent context (`lastLang`),
    - returns a ranked decision with confidence.
- This ensemble can later be combined with n-gram scores (ticket 13) but must already be usable standalone.

Acceptance criteria:
- New actor or service type, e.g.:
  - `actor LanguageEnsemble { func classify(token: String, context: Context) -> LanguageDecision }`.
- Context struct includes:
  - `lastLanguage: NLLanguage?` or internal enum;
  - optional flags for “current system layout”.
- Decision struct includes:
  - `primaryLanguage`, `layoutHypothesis`, `confidence`, plus raw intermediate scores (for logging).
- `NLLanguageRecognizer`:
  - configured with `languageHints = [.english, .russian, .hebrew]` or dynamic weights;
  - reused across calls (no repeated allocation).

## Steps
1. **Define types**
   - `enum LayoutHypothesis { case asIs, enToRu, enToHe }` (extendable).
   - `struct LanguageDecision { var language: NLLanguage; var layout: LayoutHypothesis; var confidence: Double }`.
   - `struct EnsembleContext { var lastLanguage: NLLanguage? }`.
2. **Integrate NLLanguageRecognizer**
   - Create a wrapper around `NLLanguageRecognizer` that:
     - sets `languageHints` once,
     - exposes `func score(text: String) -> [NLLanguage: Double]`.
3. **Implement hypothesis evaluation**
   - For each token ≥3 chars:
     - produce `h0`, `h1`, `h2` strings via layout mapping functions (existing or new).
     - run recognizer on each, capturing probabilities for RU/EN/HE.
   - Apply heuristics:
     - if ≥80% Cyrillic characters → strong RU bias;
     - if ≥80% Hebrew → HE bias;
     - integrate simple spellcheck validity flags if available.
   - Incorporate context:
     - bias toward `lastLanguage` by a small factor.
4. **Decision aggregation**
   - Combine scores into a single scalar per hypothesis (e.g. weighted sum).
   - Select best (`argmax`) and smoothed confidence.
   - Expose decision via `classify` method.
5. **Add tests**
   - Test classification behavior on synthetic tokens:
     - RU as-is vs EN→RU,
     - HE as-is vs EN→HE,
     - short tokens (2–3 chars) fallback behavior.
   - Ensure recognizer is reused and not recreated per call.

## Affected files/modules
- Swift:
  - Language detection module (`LanguageDetector` / `LanguageEnsemble`).
- Tests:
  - New unit tests for `LanguageEnsemble`.

## Tests
- `swift test` with new ensemble tests passing.

## Risks & Edge Cases
- Risk: `NLLanguageRecognizer` behaves unexpectedly on “ghbdtn”-type tokens.
  - Mitigation: rely on layout hypotheses + heuristics; treat recognizer output as one signal among several.
- Risk: extra latency from multiple hypotheses.
  - Mitigation: restrict to 2–3 hypotheses; benchmark latency and adjust.

## Dependencies
- Upstream:
  - `.sdd/strategies.md` Strategy 2.
- Downstream:
  - Ticket 13 (ensemble + n-gram fusion and integration into EventMonitor pipeline).

