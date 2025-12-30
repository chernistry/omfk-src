# Known Issues - Detailed Analysis

**Last Updated:** 2024-12-30  
**Test Results:** 60 passed / 101 failed (37% success rate)

## 🎯 Executive Summary

OMFK fails to convert text in 3 main scenarios:
1. **Punctuation inside words** - `.` and `,` block conversion
2. **Single-letter words** - Context not used for detection
3. **Punctuation boundaries** - Many punctuation marks don't trigger word processing

## 📊 Test Results by Category

| Category | Passed | Failed | % | Key Issues |
|-----------|--------|--------|---|------------|
| single_words | 16 | 6 | 73% | Punctuation in words |
| context_boost_hard | 6 | 4 | 60% | Single letters, punctuation |
| punctuation_triggers | 3 | 13 | 19% | Most punctuation ignored |
| hebrew_cases | 7 | 20 | 26% | Poor HE support |
| typos_and_errors | 0 | 8 | 0% | All typos fail |
| numbers_and_special | 0 | 8 | 0% | Times, dates, phones fail |
| real_paragraphs | 0 | 5 | 0% | Long text fails |
| multiline_realistic | 0 | 2 | 0% | Multi-line fails |
| mixed_language_real | 1 | 7 | 13% | Mixed lang fails |
| ambiguous_words | 23 | 0 | 100% | ✅ Works! |
| negative_should_not_change | 10 | 0 | 100% | ✅ Works! |
| special_symbols | 3 | 0 | 100% | ✅ Works! |
| edge_cases_system | 5 | 3 | 63% | Some edge cases |
| cycling | 1 | 3 | 25% | Alt cycling broken |
| performance | 0 | 2 | 0% | Slow detection |

---

## 🔴 Issue #1: Punctuation Inside Words (HIGH PRIORITY)

### Problem
Words containing `.` or `,` don't convert because system treats them as word separators.

### Examples
| Input | Expected | Actual | Why It Fails |
|-------|----------|--------|--------------|
| `k.,k.` | `люблю` | `k.,k.` | `.` = `ю`, `,` = `б` on RU, but treated as punctuation |
| `,tp` | `без` | `,tp` | `,` at start blocks conversion |
| `j,` | `об` | `j,` | `,` at end blocks conversion |
| `epyf.n` | `узнают` | `узна.т` | `.` in middle blocks conversion |
| `,ele` | `буду` | `,ele` | `,` at start blocks conversion |

### Root Cause
1. **EventMonitor**: `.` and `,` trigger word boundary → word processed prematurely
2. **LayoutMapper**: ✅ FIXED - now converts `.` and `,` correctly
3. **Detection**: Rejects words with punctuation as invalid or classifies as English

### Current Status
- ✅ Unit test passes: `k.,k.` → `люблю`
- ❌ E2E test fails: word not converted in real usage
- ❌ Detector thinks it's English with 100% confidence

### Solution Ideas
1. **Lookahead**: Before triggering boundary, check if next char would convert to letter
2. **Punctuation context**: Allow `.` and `,` inside words if surrounded by letters
3. **Validation fix**: Don't reject words with punctuation during validation
4. **Two-pass detection**: First pass accumulates word, second pass validates

---

## 🔴 Issue #2: Single-Letter Prepositions (HIGH PRIORITY)

### Problem
Single letters like `e`, `r`, `k` should convert to `у`, `к` in context, but don't.

### Examples
| Input | Expected | Actual | Why It Fails |
|-------|----------|--------|--------------|
| `e vtyz` | `у меня` | `e меня` | `e` not converted, but `vtyz` is |
| `r cj;fktyb.` | `к сожалению` | `r сожалении.` | `r` not converted |
| `e vtyz ytn dhtvtyb` | `у меня нет времени` | `e меня нет времени` | `e` ignored |

### Root Cause
Single-letter words processed independently without context. Next word should boost confidence.

### Current Behavior
- `vtyz` → `меня` ✅ (works alone)
- `e` → stays `e` ❌ (not converted)
- Context boost exists but doesn't apply to first word

### Solution Ideas
1. **Lookahead for single letters**: If word is 1 letter, check next word before deciding
2. **Preposition whitelist**: `e`, `r`, `k`, `d`, `j`, `z`, `b` → always try RU conversion
3. **Confidence boost**: If next word is RU, boost confidence for previous single letter
4. **Pending correction**: Store single letter, correct it when next word confirms language

---

## 🟡 Issue #3: Punctuation Word Boundaries (MEDIUM PRIORITY)

### Problem
Many punctuation marks don't trigger word boundary, so words aren't processed.

### Missing Triggers
Currently only space and newline trigger. Missing:
- `?` `!` `:` `;` - Sentence punctuation
- `(` `)` `[` `]` `{` `}` - Brackets
- `«` `»` `"` `"` - Quotes
- `—` `–` `-` - Dashes
- `/` `\` - Slashes
- `…` - Ellipsis

### Examples
| Input | Expected | Actual | Why It Fails |
|-------|----------|--------|--------------|
| `ghbdtn?rfr ltkf` | `привет?как дела` | `ghbdtn?rfr ltkf` | `?` doesn't trigger |
| `(ghbdtn)` | `(привет)` | `(ghbdtn)` | `()` don't trigger |
| `"ghbdtn"` | `"привет"` | `"ghbdtn"` | `""` don't trigger |
| `ghbdtn—vbh` | `привет—мир` | `ghbdtn—vbh` | `—` doesn't trigger |

### Solution
Add all these to `wordBoundary` in `language_data.json` and update `EventMonitor` logic.

---

## 🟠 Issue #4: Typos and Errors (MEDIUM PRIORITY)

### Problem
Words with typos don't convert because validation rejects them.

### Examples
| Input | Expected | Actual | Why It Fails |
|-------|----------|--------|--------------|
| `ghbdtn vbhh` | `привет мирр` | `ghbdtn vbhh` | Double letter rejected |
| `ghbdtnn` | `приветт` | `ghbdtnn` | Extra letter rejected |
| `ghbdetn` | `привует` | `ghbdetn` | Typo rejected |
| `cgfcboj` | `спасищо` | `cgfcboj` | Typo in спасибо rejected |

### Root Cause
Validation too strict - rejects words not in dictionary, even if they're close.

### Solution Ideas
1. **Fuzzy matching**: Allow 1-2 char difference from dictionary words
2. **Disable validation**: Just convert and let user decide
3. **Confidence penalty**: Lower confidence for typos but still convert

---

## 🟠 Issue #5: Numbers and Special Characters (MEDIUM PRIORITY)

### Problem
Text with numbers, times, dates, phones doesn't convert.

### Examples
| Input | Expected | Actual | Why It Fails |
|-------|----------|--------|--------------|
| `dcnhtxf d 15:00` | `встреча в 15:00` | `dcnhtxf d 15:00` | `:` in time blocks |
| `wtyf 1000 he,` | `цена 1000 руб` | `wtyf 1000 he,` | Numbers block |
| `lfnf 25.12.2024` | `дата 25.12.2024` | `lfnf 25.12.2024` | Date format blocks |

### Solution
Handle numbers and special formats separately, convert only letter parts.

---

## 🟢 What Works Well

### ✅ Ambiguous Words (100% pass rate)
System correctly handles words that could be multiple languages.

### ✅ Negative Cases (100% pass rate)
Correctly doesn't convert when it shouldn't (e.g., valid English words).

### ✅ Special Symbols (100% pass rate)
Handles special symbols correctly.

---

## 🎯 Recommended Fix Priority

1. **Issue #1 (Punctuation)** - Blocks 20+ test cases, affects UX heavily
2. **Issue #2 (Single letters)** - Blocks 10+ test cases, common in Russian
3. **Issue #3 (Boundaries)** - Blocks 13 test cases, easy fix
4. **Issue #4 (Typos)** - Blocks 8 test cases, UX improvement
5. **Issue #5 (Numbers)** - Blocks 8 test cases, less common

---

## 💡 Holistic Solution Ideas

### Idea 1: Smart Word Accumulation
Instead of triggering on first punctuation, accumulate until:
- Whitespace
- Punctuation followed by whitespace
- Punctuation followed by different language chars

### Idea 2: Two-Phase Detection
1. **Phase 1**: Accumulate entire phrase (until whitespace)
2. **Phase 2**: Split by punctuation, detect each part, convert

### Idea 3: Context-Aware Validation
- Single letters: use next word for validation
- Punctuation: allow if surrounded by same-language letters
- Typos: use fuzzy matching with confidence penalty

### Idea 4: Punctuation Classification
Classify punctuation as:
- **Word-internal**: `.` `,` in `k.,k.` → part of word
- **Word-boundary**: `.` `,` after space → end of sentence
- **Phrase-boundary**: `?` `!` `:` → always boundary

---

## 📝 Test Commands

```bash
# Run all tests
python3 scripts/comprehensive_test.py

# Run specific category
python3 scripts/comprehensive_test.py context_boost_hard --real-typing

# Run single test
python3 scripts/comprehensive_test.py single --real-typing

# Check logs
tail -f ~/.omfk/debug.log
```

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| z nt,z k.,k. | я тебя люблю | я тебя k.,k. | OPEN | Запятая в k.,k. блокирует конверсию |
| e vtyz tcnm bltq | у меня есть идея | e меня есть идей | OPEN | "e" не конвертируется в "у" |
| r cj;fktyb. 'nj ytdjpvj;yj | к сожалению это невозможно | r сожалении. это невозможно | OPEN | "r" не конвертируется в "к" |
| e vtyz ytn dhtvtyb | у меня нет времени | e меня нет времени | OPEN | "e" не конвертируется в "у" |

### Punctuation Triggers (13 failed)

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| ghbdtn?rfr ltkf | привет?как дела | ghbdtn?rfr ltkf | OPEN | ? не триггерит коррекцию |
| (ghbdtn) | (привет) | не работает | OPEN | Скобки блокируют |
| "ghbdtn" | "привет" | не работает | OPEN | Кавычки блокируют |
| ghbdtn - vbh | привет - мир | не работает | OPEN | Дефис с пробелами |
| ghbdtn: rfr ltkf | привет: как дела | не работает | OPEN | Двоеточие |
| ghbdtn; rfr ltkf | привет; как дела | ghbdtn; rfr ltkf | OPEN | Точка с запятой |
| ghbdtn...rfr ltkf | привет...как дела | ghbdtn...rfr ltkf | OPEN | Многоточие |
| [ghbdtn] | [привет] | [ghbdtn] | OPEN | Квадратные скобки |
| {ghbdtn} | {привет} | {ghbdtn} | OPEN | Фигурные скобки |
| «ghbdtn» | «привет» | «ghbdtn» | OPEN | Кавычки-ёлочки |
| ghbdtn—vbh | привет—мир | ghbdtn—vbh | OPEN | Em dash |
| ghbdtn / vbh | привет / мир | ghbdtn / vbh | OPEN | Слэш |
| ghbdtn\\vbh | привет\\мир | ghbdtn\\vbh | OPEN | Бэкслэш |

### Typos and Errors (8 failed)

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| ghbdtn vbhh | привет мирр | ghbdtn vbhh | OPEN | Опечатка - двойная буква |
| ghbdtn vb | привет ми | ghbdtn vb | OPEN | Неполное слово |
| ghbdtnn | приветт | ghbdtnn | OPEN | Лишняя буква |
| ghbdetn | привует | ghbdetn | OPEN | Опечатка внутри |
| ghbdt | приве | ghbdt | OPEN | Неполное слово |
| ghbdtnm | приветь | ghbdtnm | OPEN | Лишний символ |
| cgfcboj | спасищо | cgfcboj | OPEN | Опечатка в спасибо |
| cgfcb,jj | спасибоо | cgfcb,jj | OPEN | Двойная буква |

### Numbers and Special (8 failed)

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| dcnhtxf d 15:00 | встреча в 15:00 | dcnhtxf d 15:00 | OPEN | Время с двоеточием |
| wtyf 1000 he, | цена 1000 руб | wtyf 1000 he, | OPEN | Цена |
| ntktajy +7-999-123-45-67 | телефон +7-999-123-45-67 | не работает | OPEN | Телефон |
| lfnf 25.12.2024 | дата 25.12.2024 | lfnf 25.12.2024 | OPEN | Дата с точками |
| dcnhtxf c 15:00-16:30 | встреча с 15:00-16:30 | не работает | OPEN | Диапазон времени |
| crblrf 20% | скидка 20% | crblrf 20% | OPEN | Процент |

### Alt Cycling (3 failed)

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| ghbdtn (1 Alt) | привет | ghbdtn | OPEN | Alt не триггерит коррекцию |
| ghbdtn (2 Alt) | привет | ghbdtn | OPEN | Cycling не работает |
| ghbdtn (5 Alt) | привет | ghbdtn | OPEN | Stress cycling |

### Edge Cases (3 failed)

| Input | Expected | Actual | Status | Notes |
|-------|----------|--------|--------|-------|
| "   " (3 spaces) | "   " | "" | OPEN | Пробелы удаляются |
| "\n\n\n" | "\n\n\n" | "" | OPEN | Переносы удаляются |
| "\t" | "\t" | "" | OPEN | Таб удаляется |

---

## Корневые причины

1. **Запятая/точка в середине слова** — символы `,` `.` на русской раскладке это `б` `ю`, но когда они внутри слова, конверсия не происходит
2. **Single-letter prepositions e/r** — буквы `e` и `r` не распознаются как русские предлоги `у` и `к` в контексте
3. **Alt cycling не работает** — возможно проблема с тестом или с обработкой Alt в select+option режиме
4. **Typos не конвертируются** — слова с опечатками не проходят валидацию по словарю

---

## Приоритеты исправления

1. 🔴 **HIGH**: Запятая/точка в словах (k.,k. → люблю, ,tp → без)
2. 🔴 **HIGH**: Single-letter prepositions e→у, r→к
3. 🟡 **MEDIUM**: Punctuation triggers (?, :, ;, скобки)
4. 🟡 **MEDIUM**: Alt cycling
5. 🟢 **LOW**: Typos (требует fuzzy matching)
6. 🟢 **LOW**: Edge cases с whitespace
