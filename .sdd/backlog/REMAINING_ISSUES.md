# OMFK Bug Fix - Status Update (2025-12-30)

## ✅ ChatGPT's Fixes - VERIFIED

ChatGPT fixed the script-lock issues! Results:
- ✅ Pure Cyrillic text no longer detected as English
- ✅ Pure Hebrew text no longer detected as English
- ✅ `SCRIPT_LOCK_RU/HE` working correctly
- ✅ Context contamination fixed

**E2E Test: 114/161 passed (70.8%)**

## 🎯 Current State Analysis

### What's Working Great (90%+)
1. **Single word conversion RU↔EN**: 100% ✅
2. **Typos and errors**: 100% ✅
3. **Ambiguous words (negative tests)**: 92% ✅
4. **Context boost**: 90% ✅
5. **Punctuation triggers**: 88% ✅

### What Needs Work

#### 🔴 P0: Critical Bugs (Break Core UX)

**1. Alt Cycling Broken for Single Words**
```
Test: Type 'ghbdtn', press Alt
Expected: 'привет'
Actual: 'ghbdtn' (no change!)
```
- Multi-word cycling works ✅
- Single word cycling broken ❌
- This is a **major UX regression** - users can't manually trigger conversion!

**2. Layout Variant Detection Missing**
```
❌ hello on Russian Phonetic → челло (not converted)
❌ hello on Hebrew Mac → יקךךם (not converted)
❌ hello on Hebrew QWERTY → העללו (not converted)
❌ привет on Hebrew Mac → עינגאמ (not converted)
❌ привет on Hebrew QWERTY → גהבדתנ (not converted)
```

System only recognizes standard layouts:
- ✅ US, Russian, Hebrew (standard)
- ❌ Russian Phonetic, Hebrew-QWERTY, Hebrew Mac variants

#### 🟡 P1: High Priority (Major UX Issues)

**3. Special Characters Cause Errors**
```
❌ 🙂 ghbdtn → [no layout for: 🙂 ghbdtn]
❌ «ghbdtn» → [no layout for: «ghbdtn»]
❌ ghbdtn—vbh → [no layout for: ghbdtn—vbh]
```
Pattern: Any emoji, guillemets, em-dash, currency symbol → error

**4. Punctuation in Numbers Gets Converted**
```
❌ 15:00 → 15Ж00 (colon → Ж)
❌ 25.12.2024 → 25ю12ю2024 (dots → ю)
❌ 20% → 20: (% → :)
❌ v1.2.3 → м1.2ю3
```
Need: numeric context detection

**5. File Paths Corrupted**
```
❌ /Users/.../omfk/OMFK → /Users/.../щьал/ЩЬАЛ
❌ C:\Users\... → С:\Users\... (C→С)
❌ README.md → README.צג
❌ UUID: ...41d4... → ...41в4... (d→в)
```
Need: technical text detection (paths, UUIDs, filenames)

#### 🟢 P2: Medium Priority (Polish)

**6. Paragraph Punctuation Issues**
- Commas/periods wrong in multi-sentence text
- Some words not converted in long paragraphs
- Example: `lfyyj yt dbltk ntyz?` → `данно не видел ntyz?` (should be `давно не видел тебя.`)

**7. Whitespace Not Preserved**
```
❌ '   ' → '' (spaces deleted)
❌ '\n\n\n' → '' (newlines deleted)
❌ 'ghbdtn\t\tvbh' → 'привет мир' (tabs lost)
```

## 🔍 Root Cause Analysis

### Alt Cycling Issue
Likely causes:
1. Hotkey handler not detecting single-word selection
2. Buffer state incorrect when Alt pressed
3. Saved word length calculation wrong

**Debug needed:** Check EventMonitor.swift hotkey logic

### Layout Variants Issue
Current implementation hardcoded for specific layouts. Need:
1. Dynamic layout detection from system
2. Support for all installed keyboard layouts
3. Fallback to "try all variants" approach

### Special Characters Issue
Error message `[no layout for: ...]` suggests:
1. Character classification fails for non-ASCII
2. LayoutMapper doesn't handle Unicode properly
3. Need: passthrough for unmappable characters

### Numeric Context Issue
Punctuation converter doesn't check surrounding context:
1. `:` in `15:00` should stay `:`
2. `.` in `1.2.3` should stay `.`
3. Need: digit-aware punctuation logic

### File Path Issue
No technical text detection:
1. Paths: `/...` or `C:\...` patterns
2. UUIDs: `[0-9a-f-]{36}` pattern
3. Filenames: `*.ext` pattern
4. Need: regex-based protection

## 📊 Test Coverage Summary

| Category | Tests | Pass | Fail | Rate |
|----------|-------|------|------|------|
| Single words | 19 | 19 | 0 | 100% |
| Paragraphs | 5 | 0 | 5 | 0% |
| Multiline | 2 | 0 | 2 | 0% |
| Mixed language | 10 | 6 | 4 | 60% |
| Special symbols | 3 | 1 | 2 | 33% |
| Hebrew cases | 19 | 15 | 4 | 79% |
| Punctuation triggers | 16 | 14 | 2 | 88% |
| Typos | 8 | 8 | 0 | 100% |
| Numbers | 7 | 2 | 5 | 29% |
| Ambiguous words | 24 | 22 | 2 | 92% |
| Negative (no change) | 10 | 7 | 3 | 70% |
| Edge cases | 7 | 4 | 3 | 57% |
| Context boost | 10 | 9 | 1 | 90% |
| Alt cycling | 4 | 1 | 3 | 25% |
| Stress tests | 4 | 4 | 0 | 100% |
| Performance | 2 | 0 | 2 | 0% |
| **TOTAL** | **161** | **114** | **47** | **70.8%** |

## 🎯 Recommended Next Steps

### Immediate (1-2 hours)
1. **Fix Alt cycling** - debug EventMonitor.swift hotkey handler
2. **Add special char passthrough** - don't error on unmappable chars

### Short-term (1 day)
3. **Add layout variant support** - detect all system layouts
4. **Implement numeric context** - protect punctuation in numbers
5. **Add technical text detection** - protect paths/UUIDs/filenames

### Medium-term (2-3 days)
6. **Improve paragraph handling** - better multi-sentence logic
7. **Preserve whitespace** - don't delete tabs/spaces/newlines

## 💡 Key Insights

1. **Core detection is solid** - 100% on single words, 90% on context boost
2. **Edge cases need work** - special chars, numbers, technical text
3. **Alt cycling regression** - critical UX issue, needs immediate fix
4. **Layout support incomplete** - only works for standard layouts

## 📁 Files to Check

- `OMFK/Sources/Engine/EventMonitor.swift` - Alt cycling logic
- `OMFK/Sources/Core/LayoutMapper.swift` - Character mapping
- `OMFK/Sources/Core/ConfidenceRouter.swift` - Detection logic
- `OMFK/Sources/Resources/language_data.json` - Layout definitions

## 🚀 Success Metrics

- **Current:** 70.8% pass rate
- **Target (P0 fixed):** 80% pass rate
- **Target (P0+P1 fixed):** 90% pass rate
- **Target (all fixed):** 95%+ pass rate

