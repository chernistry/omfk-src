# OMFK Bug Fix - Remaining Issues

## 🎯 Status Update

Your previous fixes worked well! **Major progress:**
- ✅ Punctuation disambiguation: 11/16 tests now pass (was 3/16) - **69% improvement**
- ✅ Smart segmentation working
- ✅ Cmd+A+Delete context reset fixed
- ✅ Unit tests all passing

## 🐛 Remaining Critical Issue

**Problem:** `люблю` (Russian word) keeps getting detected as English with high confidence, causing auto-reject loop.

### Evidence from Logs

```
Input: len=5 latin=0 cyr=5 heb=0 dig=0 ws=0 other=0 | Path: SCORE | Result: en (Conf: 0.95)
LEARNING: recordAutoReject for 'люблю'
```

**What's happening:**
1. User types `люблю` (valid Russian word)
2. System detects it as **English** with 0.95 confidence ❌
3. Tries to convert EN→RU, fails (it's already Russian!)
4. Records as "auto-reject" and learns wrong pattern
5. Next time: `Path: USER_DICT_KEEP | Result: ru (Conf: 1.00)` - now it "knows" to keep it

**The bug:** Pure Cyrillic text (`cyr=5, latin=0`) should NEVER be detected as English. This is a fundamental logic error.

### Root Cause Hypothesis

In `ConfidenceRouter.swift`, the detection logic likely:
1. Checks character sets (sees Cyrillic)
2. But then some scoring/whitelist/learning overrides it to English
3. Possibly: `люблю` is in English whitelist? Or n-gram model confused?

### What You Need to Fix

**Add a sanity check BEFORE any detection logic:**

```swift
// In ConfidenceRouter.swift, at the START of detection:
if text is 100% Cyrillic → force Result: ru
if text is 100% Hebrew → force Result: he  
if text is 100% Latin → continue with normal detection
```

**Why this is critical:**
- Pure Cyrillic text being detected as English breaks the entire system
- It creates wrong learning patterns that persist
- Users will see Russian text "corrected" to gibberish

## 🔍 Debug Task

1. **Find where this happens:**
   - Search for `Path: SCORE` in ConfidenceRouter.swift
   - Find where `Result: en` is set despite `cyr=5, latin=0`
   - Check if there's a whitelist/learning override that ignores character analysis

2. **Add character-based sanity check:**
   ```swift
   let stats = analyzeCharacters(text)
   if stats.cyrillic > 0 && stats.latin == 0 && stats.hebrew == 0 {
       // Pure Cyrillic → must be Russian
       return LanguageDecision(language: .russian, ...)
   }
   if stats.hebrew > 0 && stats.latin == 0 && stats.cyrillic == 0 {
       // Pure Hebrew → must be Hebrew
       return LanguageDecision(language: .hebrew, ...)
   }
   // Otherwise continue with normal detection
   ```

3. **Test the fix:**
   - Type `люблю` in Notes
   - Check logs: should show `Result: ru` not `Result: en`
   - Type `hello` in Notes  
   - Check logs: should show `Result: en` (normal detection still works)

## 📊 Expected Outcome

After fix:
- Pure Cyrillic → always detected as Russian
- Pure Hebrew → always detected as Hebrew
- Mixed/Latin → normal detection logic
- No more auto-reject loops for valid Russian words

## 🎯 Success Criteria

Run this test:
```bash
OMFK_DEBUG_LOG=1 swift run
# Type: люблю [space]
# Check log: should see "Result: ru" NOT "Result: en"
```

If you see `Result: ru (Conf: 1.00)` for pure Cyrillic text → **FIXED** ✅

## 💡 Additional Context

The character analysis already exists (you can see `cyr=5, latin=0` in logs), so the data is there. You just need to **use it as a hard constraint** before any other detection logic runs.

Think of it as: "Character set analysis is ground truth, everything else is just refinement."

## 📁 Key File

- `OMFK/Sources/Core/ConfidenceRouter.swift` - Main detection logic, look for where `Result: en` is set

Good luck! This should be a quick fix once you find where the override happens.
