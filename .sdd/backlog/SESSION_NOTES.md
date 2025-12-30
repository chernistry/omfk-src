# Session Notes - OMFK Development (2025-12-30)

## 🎯 Current Status: Post-ChatGPT Fix

ChatGPT applied fixes for script-lock issues. Comprehensive E2E test completed.

**Result: 114 passed / 47 failed (70.8% pass rate)**

## 📊 E2E Test Results Summary

### ✅ Strong Areas (Working Well)
1. **Single words RU/EN**: 13/13 ✅ (100%)
2. **Hebrew basic words**: 15/19 ✅ (79%)
3. **Punctuation triggers**: 14/16 ✅ (88%)
4. **Typos and errors**: 8/8 ✅ (100%)
5. **Ambiguous words (negative)**: 22/24 ✅ (92%)
6. **Context boost**: 9/10 ✅ (90%)
7. **Mixed language**: 6/10 ✅ (60%)

### ❌ Problem Areas (Need Attention)

#### 1. **Layout Detection Failures** (Critical)
- ❌ `hello` on Russian Phonetic → `челло` (not converted)
- ❌ `hello` on Hebrew Mac → `יקךךם` (not converted)
- ❌ `hello` on Hebrew QWERTY → `העללו` (not converted)
- ❌ `привет` on Hebrew Mac → `עינגאמ` (not converted)
- ❌ `привет` on Hebrew QWERTY → `גהבדתנ` (not converted)

**Root cause:** System doesn't recognize all layout variants. Only works for:
- EN → RU (standard layouts)
- EN → HE (standard layouts)
- RU → HE (standard layouts)

But fails for:
- EN → RU Phonetic
- EN/RU → HE Mac/QWERTY variants

#### 2. **Alt Cycling Broken** (Critical)
- ❌ Single Alt press: `ghbdtn` → `ghbdtn` (no change!)
- ❌ Multiple Alt presses: stays unchanged
- ✅ Multi-word cycling works

**Expected:** `ghbdtn` + Alt → `привет`
**Actual:** Nothing happens

This is a **major UX regression** - hotkey doesn't work for single words!

#### 3. **Special Characters Handling** (High Priority)
- ❌ Emoji: `🙂 ghbdtn` → `[no layout for: 🙂 ghbdtn]`
- ❌ Guillemets: `«ghbdtn»` → `[no layout for: «ghbdtn»]`
- ❌ Em dash: `ghbdtn—vbh` → `[no layout for: ghbdtn—vbh]`
- ❌ Currency symbols: `¢19/99` → `[no layout for: wtyf ¢19/99]`

**Pattern:** Any non-ASCII special character causes `[no layout for: ...]` error

#### 4. **Punctuation in Numbers** (Medium Priority)
- ❌ Time: `15:00` → `15Ж00` (colon becomes Ж)
- ❌ Date: `25.12.2024` → `25ю12ю2024` (dots become ю)
- ❌ Time range: `15:00-16:30` → `15Ж00-16Ж30`
- ❌ Percent: `20%` → `20:` (% becomes :)
- ❌ Semver: `v1.2.3` → `м1.2ю3`

**Root cause:** Punctuation inside digit sequences gets converted

#### 5. **File Paths Corrupted** (Medium Priority)
- ❌ Unix path: `/Users/.../omfk/OMFK/...` → `/Users/.../щьал/ЩЬАЛ/...`
- ❌ Windows path: `C:\Users\...` → `С:\Users\...` (C→С)
- ❌ Filename: `README.md` → `README.צג`
- ❌ UUID: `550e8400-e29b-41d4-...` → `550e8400-e29b-41в4-...` (d→в)

**Pattern:** Latin text in technical contexts gets converted

#### 6. **Whitespace Handling** (Low Priority)
- ❌ Only spaces: `   ` → `` (deleted)
- ❌ Only newlines: `\n\n\n` → `` (deleted)
- ❌ Tabs between words: `ghbdtn\t\tvbh` → `привет мир` (tabs lost)
- ❌ Single tab: `\t` → `` (deleted)

#### 7. **Paragraph Punctuation** (Medium Priority)
- ❌ Casual chat: commas/periods wrong in multi-sentence text
- ❌ Work email: punctuation issues in formal text
- ❌ Tech support: punctuation errors in long paragraphs

**Example:**
```
Input:  'ghbdtn! rfr ltkf? lfyyj yt dbltk ntyz?'
Got:    'привет! как дела? данно не видел ntyz?'
Expect: 'привет! как дела? давно не видел тебя.'
```

## 🔍 Debug Log Analysis

From `~/.omfk/debug.log`:

### Good Patterns (Working)
```
Input: len=7 latin=7 cyr=0 heb=0 | Path: SCORE | Result: ru (Conf: 0.95)
Input: len=3 latin=3 cyr=0 heb=0 | Path: SCORE | Result: ru (Conf: 0.95)
```
✅ Pure Latin correctly detected as "typed on wrong layout"

### Problem Patterns
```
Input: len=2 latin=2 cyr=0 heb=0 | Path: WHITELIST | Result: en (Conf: 1.00)
```
⚠️ Short words hit whitelist, might block conversion

```
REJECTED_VALIDATION: ru_from_en | no valid conversion found from 5 variants
Input: len=3 latin=3 cyr=0 heb=0 | Path: HEURISTIC | Result: ru (Conf: 0.80)
```
⚠️ Validation rejects conversion, falls back to heuristic

## 🎯 Priority Fixes Needed

### P0 (Critical - Breaks Core Functionality)
1. **Fix Alt cycling for single words** - hotkey doesn't work!
2. **Add support for all layout variants** - Hebrew Mac/QWERTY, Russian Phonetic

### P1 (High - Major UX Issues)
3. **Handle special characters gracefully** - don't error on emoji/symbols
4. **Fix punctuation in numbers** - preserve `:` `.` `%` in numeric contexts
5. **Protect file paths** - detect and preserve paths/URLs/UUIDs

### P2 (Medium - Polish)
6. **Improve paragraph punctuation** - better comma/period handling in long text
7. **Preserve whitespace** - don't delete tabs/spaces/newlines

## 📈 Progress Tracking

| Category | Pass Rate | Status |
|----------|-----------|--------|
| Single words | 100% | ✅ Excellent |
| Punctuation triggers | 88% | ✅ Good |
| Typos | 100% | ✅ Excellent |
| Context boost | 90% | ✅ Good |
| Hebrew basic | 79% | ⚠️ Needs work |
| Mixed language | 60% | ⚠️ Needs work |
| Alt cycling | 25% | ❌ Broken |
| Paragraphs | 0% | ❌ Broken |
| Special chars | 20% | ❌ Broken |
| Numbers | 29% | ❌ Broken |

**Overall: 70.8% pass rate** (114/161 tests)

## 🔧 Technical Debt

1. **Layout mapper** needs to support all system layouts dynamically
2. **Character classification** needs special char handling (emoji, currency, etc.)
3. **Context detection** for technical text (paths, UUIDs, code)
4. **Punctuation logic** needs numeric context awareness
5. **Hotkey handler** broken for single-word selection

## 📝 Next Session TODO

1. Debug why Alt cycling doesn't work for single words
2. Add layout variant detection (Russian Phonetic, Hebrew QWERTY)
3. Implement special character passthrough (emoji, symbols)
4. Add numeric context detection for punctuation
5. Implement file path / technical text detection
