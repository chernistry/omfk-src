# Ticket: 13 Multi-layout support with JSON-driven configuration

Spec version: v1.0 / layouts.md, layouts.json

## Context

**Critical gap identified**: The current `LayoutMapper.swift` has hardcoded character tables supporting only:
- Russian PC (ЙЦУКЕН)
- Hebrew Standard (SI-1452)

However, users commonly use **different layout variants**:
- **Hebrew QWERTY** (phonetic) — letters positioned by sound similarity to Latin
- **Russian Phonetic** (ЯШЕРТЫ) — letters positioned by sound similarity to Latin
- **Hebrew PC** — slight differences from SI-1452 (e.g., `'` vs `׳`)

The comprehensive layout data already exists in:
- `.sdd/layouts.json` — full character mapping for all layouts with modifiers
- `.sdd/layouts.md` — documentation and CSV reference

This ticket refactors `LayoutMapper` to:
1. Load layout data from JSON at runtime
2. Support multiple layout variants per language
3. Allow user configuration of active layouts

## Objective & Definition of Done

### Primary Objective
Replace hardcoded layout tables with a data-driven approach that supports all documented layouts.

### Definition of Done

- [ ] **Data loading**:
  - [ ] Create `LayoutData.swift` model matching `.sdd/layouts.json` schema
  - [ ] Load layout data from bundled JSON resource at app startup
  - [ ] Fallback to embedded minimal tables if JSON load fails

- [ ] **LayoutMapper refactor**:
  - [ ] Replace hardcoded `ruToEn`, `heToEn` dictionaries with dynamic lookup
  - [ ] Support layout variants: `en_us`, `ru_pc`, `ru_phonetic_yasherty`, `he_standard`, `he_pc`, `he_qwerty`
  - [ ] Handle `layout_aliases` (e.g., `en_abc` → `en_us`)
  - [ ] Preserve existing API: `convert(_ text: String, from: Language, to: Language) -> String?`
  - [ ] Add new API: `convert(_ text: String, fromLayout: String, toLayout: String) -> String?`

- [ ] **Configuration**:
  - [ ] Add `activeLayouts` setting to `SettingsStore`: which layout variant to use per language
  - [ ] Default: `["en": "en_us", "ru": "ru_pc", "he": "he_standard"]`
  - [ ] User can change via Settings UI (ticket 15)

- [ ] **LanguageEnsemble update**:
  - [ ] Update hypothesis evaluation to use configured layout variants
  - [ ] For Hebrew: if user has `he_qwerty`, evaluate `heFromEnLayout` using QWERTY mapping, not Standard

- [ ] **Tests**:
  - [ ] Unit tests for JSON loading and parsing
  - [ ] Tests for each layout variant conversion
  - [ ] Tests for fallback behavior
  - [ ] Regression tests ensuring existing RU↔EN, HE↔EN still work

## Data Organization

### Resource Location
```
OMFK/
├── Sources/
│   └── Resources/
│       └── layouts.json    # Copy from .sdd/layouts.json
├── Core/
│   ├── LayoutMapper.swift  # Refactored
│   └── LayoutData.swift    # New: JSON model
```

### JSON Schema (from `.sdd/layouts.json`)
```swift
struct LayoutData: Codable {
    let schemaVersion: String
    let layouts: [String: LayoutInfo]
    let layoutAliases: [String: String]
    let keys: [KeyInfo]
    let map: [String: [String: KeyMapping]]  // keyCode -> layoutId -> modifiers -> char
}

struct LayoutInfo: Codable {
    let name: String
    let platform: String
    let note: String?
}

struct KeyInfo: Codable {
    let code: String
    let qwertyLabel: String
}

struct KeyMapping: Codable {
    let n: String?   // none (base)
    let s: String?   // shift
    let a: String?   // alt/option
    let sa: String?  // shift+alt
}
```

## Steps

1. **Create LayoutData model** (0.5 day)
2. **Copy layouts.json to Resources** (0.5 hour)
3. **Refactor LayoutMapper** (1 day)
4. **Update LanguageEnsemble** (0.5 day)
5. **Add settings** (0.5 day)
6. **Write tests** (1 day)

## Affected Files/Modules

- `OMFK/Sources/Core/LayoutMapper.swift` — major refactor
- `OMFK/Sources/Core/LayoutData.swift` — new file
- `OMFK/Sources/Core/LanguageEnsemble.swift` — minor update
- `OMFK/Sources/Settings/SettingsStore.swift` — add activeLayouts
- `OMFK/Sources/Resources/layouts.json` — copy from .sdd/
- `OMFK/Tests/LayoutMapperTests.swift` — expand significantly

## Reference Documentation

- **Layout data**: `.sdd/layouts.json` (full mapping with all modifiers)
- **Layout docs**: `.sdd/layouts.md` (CSV table, sources, edge cases)
- **Architecture**: `.sdd/architect.md` (ADR-005)

## Risks & Edge Cases

1. **Multi-character outputs** (e.g., `ײַ` on Hebrew QWERTY `]` key)
2. **Missing characters in some layouts**
3. **Performance of dynamic lookup vs hardcoded**
4. **JSON file missing or corrupted**

## Dependencies

- **Upstream**: None (foundational change)
- **Downstream**: Tickets 14, 15, 16, 17, 18

## Priority

**P0 — CRITICAL** — Without this, the app doesn't work correctly for users with non-standard layouts.
