# Ticket 15: Auto-detect Keyboard Layout Variant

Spec version: v2.0 (rewritten from UI-based to auto-detect)

## Context

Different users use different keyboard layout variants:
- Russian: PC (ЙЦУКЕН) vs Phonetic (ЯШЕРТЫ)
- Hebrew: Standard vs QWERTY (phonetic) vs PC

The `LayoutMapper` needs to know which variant to use for correct conversion. Instead of manual UI selection, we can auto-detect via macOS API.

## Current State

- `LayoutMapper` hardcodes defaults: `ru_pc`, `he_standard`
- Users with `he_qwerty` or `ru_phonetic` get wrong conversions
- macOS API (`TISCopyCurrentKeyboardInputSource`) returns exact layout ID

## Objective

Auto-detect keyboard layout variants via macOS API and use them for conversion.

## Definition of Done

- [x] Map macOS layout IDs to our layout IDs
- [x] Detect current layout on app start
- [x] Update `SettingsManager.activeLayouts` automatically
- [x] No UI needed — fully automatic

## Implementation

### macOS ID → Our ID Mapping

| macOS ID | Our ID |
|----------|--------|
| `com.apple.keylayout.Russian` | `ru_pc` |
| `com.apple.keylayout.RussianWin` | `ru_pc` |
| `com.apple.keylayout.Russian-Phonetic` | `ru_phonetic_yasherty` |
| `com.apple.keylayout.Hebrew` | `he_standard` |
| `com.apple.keylayout.Hebrew-QWERTY` | `he_qwerty` |
| `com.apple.keylayout.Hebrew-PC` | `he_pc` |

## Files Modified

- `OMFK/Sources/Core/InputSourceManager.swift`
- `OMFK/Sources/Settings/SettingsManager.swift`

## Priority

**P3 — LOW** — Most users on standard layouts, works by default.
