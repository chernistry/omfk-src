# Ticket: 05 Layout Mapper with Character Tables

Spec version: v1.0 / ADR-005, Component LayoutMapper

## Context
- Links to `.sdd/architect.md`: ADR-005 (Hardcoded Layout Mapping Tables), Data Schema (Layout Mapping Tables)
- Links to `.sdd/project.md`: Definition of Done item 4 (Layout mapping tables for RU↔EN, HE↔EN)
- Core functionality for converting text between keyboard layouts

## Objective & Definition of Done
Implement LayoutMapper with hardcoded RU↔EN and HE↔EN character mapping tables for O(1) lookup.

- [ ] `LayoutMapper.swift` created with character mapping dictionaries
- [ ] RU↔EN mapping complete (ЙЦУКЕН ↔ QWERTY, 33 letters + punctuation)
- [ ] HE↔EN mapping complete (Hebrew keyboard ↔ QWERTY, 22 letters + punctuation)
- [ ] `convert(_:from:to:)` method with O(1) character lookup
- [ ] Preserves case (uppercase/lowercase) for Latin/Cyrillic
- [ ] Unit tests for all character mappings
- [ ] Sendable conformance for Swift 6 concurrency

## Steps
1. Create `OMFK/Core/LayoutMapper.swift`
2. Define `struct LayoutMapper: Sendable`
3. Create `private let ruToEn: [Character: Character]` with full ЙЦУКЕН → QWERTY mapping:
   - й→q, ц→w, у→e, к→r, е→t, н→y, г→u, ш→i, щ→o, з→p, х→[, ъ→]
   - ф→a, ы→s, в→d, а→f, п→g, р→h, о→j, л→k, д→l, ж→;, э→', я→z, ч→x, с→c, м→v, и→b, т→n, ь→m, б→,, ю→.
   - Include uppercase mappings (Й→Q, etc.)
4. Create `private let enToRu: [Character: Character]` (inverse of ruToEn)
5. Create `private let heToEn: [Character: Character]` with Hebrew → QWERTY mapping:
   - ש→a, ד→s, ג→d, כ→f, ע→g, י→h, ח→j, ל→k, ך→l, ף→;, ז→z, ס→x, ב→c, ה→v, נ→b, מ→n, צ→m, ת→,, ץ→.
   - Include final forms (ך, ם, ן, ף, ץ)
6. Create `private let enToHe: [Character: Character]` (inverse of heToEn)
7. Implement `func convert(_ text: String, from: NLLanguage, to: NLLanguage) -> String`:
   - Select appropriate mapping dictionary
   - Map each character, preserve unmapped characters (spaces, numbers, punctuation)
   - Return converted string
8. Create `Tests/CoreTests/LayoutMapperTests.swift` with test cases

## Affected files/modules
- `OMFK/Core/LayoutMapper.swift` (new)
- `Tests/CoreTests/LayoutMapperTests.swift` (new)

## Tests
- Run unit tests: `xcodebuild test -scheme OMFK -destination 'platform=macOS'`
- Test cases:
  - `testRussianToEnglish()`: "Ghbdtn vbh" → "Привет мир"
  - `testEnglishToRussian()`: "Привет мир" → "Ghbdtn vbh"
  - `testHebrewToEnglish()`: "akuo okvg" → "שלום עולם"
  - `testEnglishToHebrew()`: "שלום עולם" → "akuo okvg"
  - `testPreservesCase()`: "Ghbdtn" → "Привет" (capital П)
  - `testPreservesUnmappedCharacters()`: "Hello 123!" → "Hello 123!"
  - `testAllCharactersMapped()`: Verify all 33 RU + 22 HE characters have mappings

## Risks & Edge Cases
- Case preservation for Hebrew (no uppercase): document as N/A
- Punctuation may differ between layouts: map common punctuation, preserve rest
- Final Hebrew forms (ך, ם, ן, ף, ץ) must be handled correctly

## Dependencies
- Upstream tickets: 01 (project setup)
- Downstream tickets: 06 (EventMonitor), 09 (layout mapper tests)