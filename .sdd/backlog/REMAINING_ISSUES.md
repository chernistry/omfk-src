# OMFK Bug Fix - Critical Issue with "darling"

## 🎯 Previous Success

Your fixes worked great! Major improvements:
- ✅ `SCRIPT_LOCK_RU/HE` now working - pure Cyrillic/Hebrew correctly detected
- ✅ Punctuation triggers: 11/16 pass (was 3/16)
- ✅ Context boost improvements
- ✅ First-word prepositions: `r cj;fktyb.` → `к сожалению` ✅

## 🐛 New Critical Bug: "darling" Converts to Hebrew

### The Problem

When typing `darling` (English word) in a Russian sentence context, OMFK converts it to Hebrew `דארלינג`.

**Example from logs:**
```
🔍 DEBUG: text='вфкдштп' pending=nil currentTargetLang=he
🔍 DEBUG: text='דארלינג' pending=nil currentTargetLang=he
```

User typed: `darling` (English)  
OMFK converted to: `דארלינג` (Hebrew)  
Expected: `darling` (no conversion - it's a valid English word)

### Why This Happens

From validation logs:
```
VALID_CHECK: darling wordConf=1.00 srcWordConf=1.00 tgtNorm=0.91 srcNorm=0.87
VARIANT[us]: דארלינג → darling | src=-8.81 tgt=-7.19 tgtN=0.91
REJECTED_VALIDATION: en_from_he | no valid conversion found from 16 variants
Input: len=7 latin=0 cyr=0 heb=7 dig=0 ws=0 other=0 | Path: STANDARD | Result: he (Conf: 1.00)
```

**The flow:**
1. User types `darling` (English, on English keyboard)
2. Previous context was Russian (`вфкдштп` = some Russian word)
3. System sees `currentTargetLang=he` (why Hebrew??)
4. Converts `darling` → `דארלינג` (EN→HE)
5. User sees Hebrew instead of English ❌

### Root Cause

**Context contamination:** `currentTargetLang` is set to `he` from previous word, and this affects detection of the next word.

Look at the sequence:
```
text='дела' currentTargetLang=ru     ← Russian context
text='вфкдштп' currentTargetLang=he  ← Suddenly Hebrew?
text='דארלינג' currentTargetLang=he  ← Stays Hebrew
```

**Question:** Why does `вфкдштп` (Cyrillic text) set `currentTargetLang=he`?

From earlier log:
```
Input: len=7 latin=0 cyr=7 heb=0 dig=0 ws=0 other=0 | Path: BASELINE_CORRECTION | Result: he (Conf: 0.85)
LEARNING: token='вфкдштп' finalIndex=1 wasAutomatic=true hypothesis=he_from_ru
```

**Aha!** System thinks `вфкдштп` (pure Cyrillic) should be converted to Hebrew with 0.85 confidence. This is wrong!

### The Real Bug

**Pure Cyrillic text (`cyr=7, latin=0, heb=0`) is being classified as `Result: he`**

This violates the script-lock you added! Check your `SCRIPT_LOCK_RU` logic:
- It works for some words: `я`, `тебя`, `дела` → `Path: SCRIPT_LOCK_RU`
- But NOT for `вфкдштп` → `Path: BASELINE_CORRECTION | Result: he`

### What You Need to Fix

**In ConfidenceRouter.swift, strengthen the script-lock:**

```swift
// BEFORE any other logic (including BASELINE_CORRECTION):
let stats = analyzeCharacters(token)

// Hard constraint: pure script = that language, NO EXCEPTIONS
if stats.cyrillic > 0 && stats.latin == 0 && stats.hebrew == 0 {
    return LanguageDecision(language: .russian, hypothesis: .ru, confidence: 1.0, ...)
}
if stats.hebrew > 0 && stats.latin == 0 && stats.cyrillic == 0 {
    return LanguageDecision(language: .hebrew, hypothesis: .he, confidence: 1.0, ...)
}
if stats.latin > 0 && stats.cyrillic == 0 && stats.hebrew == 0 {
    // Pure Latin - continue with normal detection (could be EN/RU/HE typed wrong)
}
```

**The issue:** Your `SCRIPT_LOCK` is conditional or comes AFTER `BASELINE_CORRECTION`. It needs to be FIRST and ABSOLUTE.

### Why This Matters

1. **UX disaster:** English words randomly become Hebrew in Russian context
2. **Context pollution:** Wrong detection cascades to next words
3. **Learning corruption:** System learns wrong patterns

### Test Case

```bash
OMFK_DEBUG_LOG=1 swift run
# Type in Notes:
# "как дела вфкдштп"  (Russian sentence)
# Check log: ALL words should be Path: SCRIPT_LOCK_RU
# None should be Result: he

# Then type:
# "how are you darling"  (English sentence)
# Check log: ALL words should be Result: en
# None should convert to Hebrew
```

### Expected Log After Fix

```
Input: len=7 latin=0 cyr=7 heb=0 dig=0 ws=0 other=0 | Path: SCRIPT_LOCK_RU | Result: ru (Conf: 1.00)
```

NOT:
```
Input: len=7 latin=0 cyr=7 heb=0 dig=0 ws=0 other=0 | Path: BASELINE_CORRECTION | Result: he (Conf: 0.85)
```

## 🎯 Action Items

1. Find where `BASELINE_CORRECTION` runs in ConfidenceRouter.swift
2. Move `SCRIPT_LOCK` check to run BEFORE it
3. Make script-lock absolute: pure Cyrillic = Russian, pure Hebrew = Hebrew, no exceptions
4. Test with the sequences above
5. Verify `darling` stays English in all contexts

This should be a 10-minute fix - just reorder the checks!

