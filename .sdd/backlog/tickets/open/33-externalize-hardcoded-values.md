# Ticket 33: Externalize Hardcoded Values

Move hardcoded magic numbers and mappings into config files. Minimize new files — extend existing configs where possible.

## Extend `thresholds.json` — add sections:

```json
{
  "detection": { /* existing */ },
  "validation": { /* existing */ },
  "scoring": { /* existing */ },
  "heuristic": { /* existing */ },
  
  "timing": {
    "pendingWordTimeout": 5.0,
    "pendingWordMinConfidence": 0.40,
    "prepositionMinConfidence": 0.10,
    "cyclingStateTimeout": 60.0,
    "cyclingMinDuration": 0.5,
    "bufferTimeout": 2.0,
    "lastCorrectionTimeout": 3.0,
    "layoutSwitchTimeout": 0.3,
    "clipboardDelayMs": 150,
    "pasteDelayMs": 100,
    "typingChunkSize": 20,
    "deletionDelayMs": 20,
    "accessibilityPollInterval": 2.0
  },
  
  "correction": {
    "contextBoostAmount": 0.20,
    "historyMaxSize": 50,
    "bufferReserveCapacity": 64,
    "visibleAlternativesRound1": 2,
    "visibleAlternativesRound2": 3
  }
}
```

## Create `language_mappings.json`:

```json
{
  "russianPrepositions": {
    "f": "а", "d": "в", "r": "к", "j": "о", "e": "у", "b": "и", "z": "я"
  },
  "languageConversions": [
    ["english", "russian"], ["english", "hebrew"],
    ["russian", "english"], ["russian", "hebrew"],
    ["hebrew", "english"], ["hebrew", "russian"]
  ]
}
```

## Create `punctuation_sets.json`:

```json
{
  "wordBoundary": [".", "!", "?", ":", ")", "]", "}", "\"", "»", """, "…"],
  "sentenceEnding": [".", "!", "?"],
  "leadingDelimiters": ["(", "[", "{", "\"", "«", """],
  "trailingDelimiters": [")", "]", "}", "\"", "»", """]
}
```

## Files to modify:

- `OMFK/Sources/Resources/thresholds.json` — add `timing`, `correction` sections
- `OMFK/Sources/Core/ThresholdsConfig.swift` — extend struct with new sections

## Files to create:

- `OMFK/Sources/Resources/language_mappings.json`
- `OMFK/Sources/Resources/punctuation_sets.json`
- `OMFK/Sources/Core/LanguageMappingsConfig.swift`
- `OMFK/Sources/Core/PunctuationConfig.swift`

## Files to update:

- `OMFK/Sources/Engine/CorrectionEngine.swift` — replace hardcoded values
- `OMFK/Sources/Engine/EventMonitor.swift` — replace hardcoded values

## Source mapping:

**CorrectionEngine.swift:**
- `5.0` → `timing.pendingWordTimeout`
- `60.0` → `timing.cyclingStateTimeout`
- `0.20` → `correction.contextBoostAmount`
- `0.40` → `timing.pendingWordMinConfidence`
- `0.10` → `timing.prepositionMinConfidence`
- `50` → `correction.historyMaxSize`
- `russianPrepositionMappings` → `language_mappings.json`
- `conversions` array → `language_mappings.json`

**EventMonitor.swift:**
- `0.5` → `timing.cyclingMinDuration`
- `2.0` (buffer) → `timing.bufferTimeout`
- `3.0` → `timing.lastCorrectionTimeout`
- `150_000_000` ns → `timing.clipboardDelayMs`
- `100_000_000` ns → `timing.pasteDelayMs`
- `0.3` → `timing.layoutSwitchTimeout`
- `20` → `timing.typingChunkSize`
- `20_000_000` ns → `timing.deletionDelayMs`
- `64` → `correction.bufferReserveCapacity`
- `2_000_000_000` ns → `timing.accessibilityPollInterval`
- `wordBoundaryPunctuation` → `punctuation_sets.json`
- `sentenceEndingPunctuation` → `punctuation_sets.json`
- `leadingDelimiters` → `punctuation_sets.json`
- `trailingDelimiters` → `punctuation_sets.json`

## Requirements:

- Structs similar to existing `ThresholdsConfig`
- Load once at startup
- Fallback to hardcoded defaults on error or missing field
- Convert ms ↔ nanoseconds in code (config stores ms for readability)

## Tests:

- `test_extended_thresholds_loading` — timing/correction sections
- `test_language_mappings_loading` — mappings load correctly
- `test_punctuation_sets_loading` — punctuation loads correctly
- `test_config_fallback` — fallback on error/missing
