# Current Task: Hebrew QWERTY Layout - FIXED

## Problem (RESOLVED)
OMFK не работал корректно когда у пользователя установлена раскладка Hebrew QWERTY (фонетическая).

## Root Cause
Код использовал `convertBest()` с активной раскладкой пользователя, но не пробовал все варианты target layouts.

Когда пользователь с `hebrew_qwerty` печатал "akuo" (паттерн Mac Hebrew):
1. `convertBest` конвертировал через `hebrew_qwerty` → `אכוו` (бессмыслица)
2. Правильный результат `שלום` был доступен через `hebrew` (Mac) layout

## Solution
Заменили `convertBest()` на `convertAllVariants()` в трёх местах:

### 1. ConfidenceRouter.swift - scoredDecision()
```swift
// OLD: 
guard let converted = LayoutMapper.shared.convertBest(token, from: source, to: target, activeLayouts: activeLayouts)

// NEW:
let variants = LayoutMapper.shared.convertAllVariants(token, from: source, to: target, activeLayouts: activeLayouts)
for (_, converted) in variants { ... }
```

### 2. ConfidenceRouter.swift - bestValidatedCandidate()
```swift
// OLD:
if let primary = LayoutMapper.shared.convertBest(...) { return cand }
let variants = LayoutMapper.shared.convertAllVariants(...)

// NEW:
let variants = LayoutMapper.shared.convertAllVariants(...)
// Always check all variants, pick best by quality
```

### 3. CorrectionEngine.swift - correctText()
```swift
// OLD:
if let corrected = LayoutMapper.shared.convertBest(...)

// NEW:
let variants = LayoutMapper.shared.convertAllVariants(...)
// Pick variant in builtin lexicon, or first one
```

## Files Modified
- `OMFK/Sources/Core/ConfidenceRouter.swift`
- `OMFK/Sources/Engine/CorrectionEngine.swift`
- `OMFK/Sources/Core/LayoutMapper.swift` (earlier - added `convertAllSourceVariants`)

## Test Results
Before fix: `akuo` → `אכוו` (wrong)
After fix: `akuo` → `שלום` (correct!)

Hebrew QWERTY test case now passes:
```
✓ שלום Mac-style on QWERTY system (should try all HE layouts)
```

## Remaining Issues (not related to this fix)
- Some Hebrew slang words not in lexicon (יאללה, סבבה)
- Multi-word phrases (בוקר טוב)
- Short English words from Hebrew (api, github)
- Hebrew with niqqud/dagesh (special Unicode handling)
