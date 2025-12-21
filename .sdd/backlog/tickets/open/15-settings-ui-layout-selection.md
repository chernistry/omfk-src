# Ticket: 15 Settings UI for layout variant selection

Spec version: v1.0 / layouts.md

## Context

Ticket 13 adds support for multiple layout variants per language. This ticket adds the **UI** for users to select which layout variant they use.

Users need to configure:
- Which Russian layout: PC (ЙЦУКЕН) or Phonetic (ЯШЕРТЫ)
- Which Hebrew layout: Standard (SI-1452), PC, or QWERTY (phonetic)
- English is typically US QWERTY (no variants needed for MVP)

## Objective & Definition of Done

### Definition of Done

- [ ] **Settings UI**:
  - [ ] Add "Keyboard Layouts" section to SettingsView
  - [ ] Dropdown/picker for Russian layout variant
  - [ ] Dropdown/picker for Hebrew layout variant
  - [ ] Show layout name and brief description

- [ ] **Persistence**:
  - [ ] Save selection to UserDefaults via SettingsStore
  - [ ] Load on app startup
  - [ ] Apply immediately (no restart required)

- [ ] **UX**:
  - [ ] Default to most common layouts (ru_pc, he_standard)
  - [ ] Show "Recommended" badge for standard layouts
  - [ ] Tooltip explaining what each variant means

## UI Design

```
┌─────────────────────────────────────────┐
│ Keyboard Layouts                        │
├─────────────────────────────────────────┤
│ Russian:  [Russian PC (ЙЦУКЕН)     ▼]  │
│           ○ Russian PC (ЙЦУКЕН)         │
│           ○ Russian Phonetic (ЯШЕРТЫ)   │
│                                         │
│ Hebrew:   [Hebrew Standard (SI-1452) ▼]│
│           ○ Hebrew Standard (SI-1452)   │
│           ○ Hebrew PC                   │
│           ○ Hebrew QWERTY (phonetic)    │
│                                         │
│ ℹ️ Select the keyboard layouts you use  │
│    on your Mac for accurate correction. │
└─────────────────────────────────────────┘
```

## Steps

1. **Extend SettingsStore** (0.5 day)
2. **Create LayoutSettingsView** (0.5 day)
3. **Integrate into SettingsView** (0.5 hour)
4. **Test** (0.5 day)

## Affected Files/Modules

- `OMFK/Sources/Settings/SettingsStore.swift` — add layout settings
- `OMFK/Sources/UI/SettingsView.swift` — add layout section
- `OMFK/Sources/UI/LayoutSettingsView.swift` — new file (optional)

## Reference Documentation

- **Available layouts**: `.sdd/layouts.json` → `layouts` object
- **Layout descriptions**: `.sdd/layouts.md`

## Dependencies

- **Upstream**: Ticket 13 (multi-layout support)
- **Downstream**: Ticket 16 (validation)

## Priority

**P2 — MEDIUM** — App works with defaults, but users with non-standard layouts need this.
