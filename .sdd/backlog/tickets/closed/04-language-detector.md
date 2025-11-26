# Ticket: 04 Language Detector with NLLanguageRecognizer

Spec version: v1.0 / ADR-006, Component LanguageDetector

## Context
- Links to `.sdd/architect.md`: ADR-006 (Character-Set Fallback), Component LanguageDetector
- Links to `.sdd/project.md`: Definition of Done item 3 (Language detection for RU/EN/HE)
- Core functionality for identifying typed language

## Objective & Definition of Done
Implement LanguageDetector with NLLanguageRecognizer, languageHints, and character-set fallback for short text.

- [ ] `LanguageDetector.swift` created with `detect(_:)` and `detectWithFallback(_:)` methods
- [ ] NLLanguageRecognizer configured with languageHints for RU/EN/HE
- [ ] Confidence threshold >0.6 enforced
- [ ] Character-set fallback for <3 word inputs (Cyrillic U+0400-04FF, Hebrew U+0590-05FF, Latin U+0000-007F)
- [ ] Returns tuple `(language: NLLanguage?, confidence: Double)`
- [ ] Unit tests with >90% accuracy on test corpus
- [ ] Sendable conformance for Swift 6 concurrency

## Steps
1. Create `OMFK/Core/LanguageDetector.swift`
2. Define `struct LanguageDetector: Sendable`
3. Implement `detect(_ text: String) -> (language: NLLanguage?, confidence: Double)`:
   - Create NLLanguageRecognizer
   - Set `languageHints = [.russian: 0.33, .english: 0.33, .hebrew: 0.34]`
   - Call `processString(text)`
   - Get `dominantLanguage` and confidence from `languageHypotheses(withMaximum: 1)`
4. Implement `detectWithFallback(_ text: String) -> (language: NLLanguage?, confidence: Double)`:
   - Call `detect(text)`
   - If confidence <0.6 or word count <3, check Unicode ranges
   - Return fallback language with confidence 0.8 if match found
5. Add helper: `private func wordCount(_ text: String) -> Int` (split by whitespace)
6. Add helper: `private func detectByCharacterSet(_ text: String) -> NLLanguage?` (Unicode range checks)
7. Create `Tests/CoreTests/LanguageDetectorTests.swift` with test cases

## Affected files/modules
- `OMFK/Core/LanguageDetector.swift` (new)
- `Tests/CoreTests/LanguageDetectorTests.swift` (new)

## Tests
- Run unit tests: `xcodebuild test -scheme OMFK -destination 'platform=macOS'`
- Test cases:
  - `testRussianDetection()`: "Привет мир как дела" → .russian, confidence >0.9
  - `testEnglishDetection()`: "Hello world how are you" → .english, confidence >0.9
  - `testHebrewDetection()`: "שלום עולם מה שלומך" → .hebrew, confidence >0.9
  - `testShortTextFallback()`: "Привет" → .russian, confidence 0.8 (fallback)
  - `testLowConfidence()`: Ambiguous text → nil or fallback
  - `testCorpusAccuracy()`: Load test corpus, verify >90% accuracy

## Risks & Edge Cases
- NLLanguageRecognizer may return unexpected languages (e.g., Serbian for Russian): languageHints mitigate this
- Mixed-script text (e.g., "Hello мир") may be ambiguous: document expected behavior
- Very short text (<3 characters) may fail even with fallback: acceptable trade-off

## Dependencies
- Upstream tickets: 01 (project setup), 02 (test corpus)
- Downstream tickets: 06 (EventMonitor), 08 (language detection tests)