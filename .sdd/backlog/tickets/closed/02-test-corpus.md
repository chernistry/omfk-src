# Ticket: 02 Create Language Test Corpus

Spec version: v1.0 / Go/No-Go Preconditions

## Context
- Links to `.sdd/architect.md`: Go/No-Go Preconditions (Test data requirements)
- Links to `.sdd/project.md`: Definition of Done item 13 (>90% language detection accuracy)
- Required for validating language detection in ticket 04

## Objective & Definition of Done
Create test corpus with 50+ sample phrases per language (RU/EN/HE) to validate language detection accuracy.

- [ ] `Tests/Resources/LanguageCorpus/russian.txt` created with 50 phrases (3-10 words each)
- [ ] `Tests/Resources/LanguageCorpus/english.txt` created with 50 phrases
- [ ] `Tests/Resources/LanguageCorpus/hebrew.txt` created with 50 phrases (including RTL test cases)
- [ ] `Tests/Resources/LanguageCorpus/mixed.txt` created with 20 phrases with language switches
- [ ] All files added to test target resources
- [ ] README.md in LanguageCorpus/ documenting format and usage

## Steps
1. Create `Tests/Resources/LanguageCorpus/` directory
2. Create `russian.txt` with 50 common Russian phrases (e.g., "Привет мир", "Как дела сегодня", "Это тестовая фраза")
3. Create `english.txt` with 50 common English phrases (e.g., "Hello world", "How are you today", "This is a test phrase")
4. Create `hebrew.txt` with 50 common Hebrew phrases (e.g., "שלום עולם", "מה שלומך היום", "זה משפט בדיקה") including RTL edge cases
5. Create `mixed.txt` with 20 phrases that switch languages mid-sentence (e.g., "Hello мир", "Привет world")
6. Add all files to test target in Xcode (Build Phases → Copy Bundle Resources)
7. Create `README.md` documenting format: one phrase per line, UTF-8 encoding

## Affected files/modules
- `Tests/Resources/LanguageCorpus/russian.txt` (new)
- `Tests/Resources/LanguageCorpus/english.txt` (new)
- `Tests/Resources/LanguageCorpus/hebrew.txt` (new)
- `Tests/Resources/LanguageCorpus/mixed.txt` (new)
- `Tests/Resources/LanguageCorpus/README.md` (new)

## Tests
- Verify files are UTF-8 encoded: `file -I Tests/Resources/LanguageCorpus/*.txt`
- Verify files are accessible in test bundle: write simple XCTest to load each file
- Count lines: `wc -l Tests/Resources/LanguageCorpus/*.txt` (should be 50/50/50/20)

## Risks & Edge Cases
- Hebrew RTL rendering may not display correctly in text editors (use specialized editor or Xcode)
- Mixed-language phrases may be ambiguous (document expected detection behavior)
- UTF-8 encoding must be preserved (avoid editors that convert to ASCII)

## Dependencies
- Upstream tickets: 01 (project setup)
- Downstream tickets: 04 (language detector), 08 (language detection tests)