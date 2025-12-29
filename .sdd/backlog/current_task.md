# Current Task: Real Typing E2E Tests for OMFK

## Goal
Create comprehensive end-to-end tests that simulate **real user typing** (character-by-character via keycodes + space) to verify OMFK auto-correction works correctly across different keyboard layout combinations.

## Test Results Summary

| Combo | Description | Passed | Failed | Rate |
|-------|-------------|--------|--------|------|
| 0 | Mac defaults (US + Russian Mac + Hebrew Mac) | 102 | 51 | 67% |
| 1 | US + RussianWin + Hebrew Mac | 98 | 55 | 64% |
| 2 | US + RussianWin + Hebrew-QWERTY | 85 | 68 | 56% |

## Recent Fixes

### Alt Cycling Bug - FIXED (2024-12-28)
**Problem:** After pressing Alt to cycle layouts, typing immediately produced garbage characters (e.g., Hebrew `מבה` instead of Russian `мир`).

**Root Cause:** `layoutBeforeCycling` was being reset to `nil` in the `defer` block of `handleHotkeyPress` before the time-based cycling window expired. This caused subsequent keystrokes to be processed normally instead of being translated using the saved layout.

**Fix:** Don't reset `layoutBeforeCycling` in the `defer` block - let the time-based window (0.5s) handle cleanup. The window now correctly captures fast typing after Alt and translates keycodes using the layout that was active before cycling.

---

## Bugs Found in Debug Log (2024-12-29)

### Bug A: "гугл" → Hebrew (False Positive)
**Severity: MEDIUM**
```
[09:12:25] Input: len=4 | Path: BASELINE_CORRECTION | Result: he (Conf: 1.00)
[09:12:26] HOTKEY: CYCLE RESULT: 'гугл' (delete 5, suffixLen=1)
```
Russian word "гугл" (Google) incorrectly converted to Hebrew with high confidence. User had to press Alt to restore.

**Hypothesis:** BASELINE_CORRECTION path doesn't check if source is a valid Russian word before converting.

### Bug B: "шзрщтуiphone" → "iphoneiphone" (Duplication)
**Severity: MEDIUM**
```
[08:46:25] VALIDATED_PRIMARY: шзрщтуiphone → iphoneiphone
```
Mixed input (Russian + Latin) produces duplicated output. "шзрщту" is "iphone" on Russian layout, but result contains "iphone" twice.

**Hypothesis:** Both the Russian part AND the Latin part are being converted/kept, resulting in duplication.

### Bug C: "грит" ↔ "grit" (False Correction of Slang)
**Severity: LOW**
```
[08:46] грит → grit (DEEP_CORRECTION)
[08:50] grit → грит (DEEP_CORRECTION)
```
Russian slang "грит" (short for "говорит" = "says") incorrectly converted to English "grit". User had to manually convert back.

**Hypothesis:** DEEP_CORRECTION finds valid English word "grit" and converts, not recognizing "грит" as valid Russian slang.

### Bug D: "ращрешит" instead of "разрешит" (Mapping Error)
**Severity: LOW**
```
[09:12:30] HOTKEY: CYCLE RESULT: 'ращрешит' (delete 9, suffixLen=1)
```
Hebrew→Russian conversion produces "ращрешит" instead of correct "разрешит" (typo: щ instead of з).

**Hypothesis:** Key mapping error in Hebrew→Russian table, or intermediate conversion through English loses information.

### Observation: Short Words Correctly Rejected
```
[09:07:20] VARIANT[russian]: ну → ye | tgtN=0.00
[09:07:20] REJECTED_VALIDATION: en_from_ru | no valid conversion found
```
Short Russian word "ну" correctly NOT converted to English "ye" (tgtN=0.00 means target is invalid).

---

## BUG GROUP 1: Single-Letter Russian Words Not Converted

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| а ты что думаешь | `f ns xnj levftim` | `f ты что думаешь` | `а ты что думаешь` | 0,1,2 |
| о чем вы говорите | `j xtv ds ujdjhbnt` | `j чем вы говорите` | `о чем вы говорите` | 0,1,2 |
| у меня есть идея | `e vtyz tcnm bltq` | `e меня есть идей` | `у меня есть идея` | 0,1,2 |
| к сожалению это невозможно | `r cj;fktyb. 'nj ytdjpvj;yj` | `r сожалению это невозможно` | `к сожалению это невозможно` | 0,1,2 |
| а это вообще нормально | `f 'nj djj,ot yjhvfkmyj` | `f это вообще нормально` | `а это вообще нормально` | 0,1,2 |
| у меня нет времени | `e vtyz ytn dhtvtyb` | `e меня нет времени` | `у меня нет времени` | 0,1,2 |

### Hypotheses

1. **Ambiguity threshold too high** - Single letters `f`, `j`, `e`, `r` are valid English letters, and OMFK's confidence threshold requires more characters to make a decision.

2. **No context propagation** - OMFK processes words independently without considering that subsequent words are clearly Russian, which should boost confidence for the first word.

3. **Builtin lexicon missing single-letter entries** - The Russian builtin lexicon may not include single-letter words like `а`, `о`, `у`, `к` as valid entries.

4. **Word length minimum** - There may be a hardcoded minimum word length (e.g., 2+ chars) before OMFK attempts conversion.

5. **Latin script priority** - When a character exists in both Latin and Cyrillic scripts, OMFK may default to Latin interpretation without sufficient evidence.

---

## BUG GROUP 2: `vs` → `мы` Not Converted

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| в этом году мы запустили проект | `d 'njv ujle vs pfgecnbkb ghjtrn` | `в этом году vs запустили проект` | `в этом году мы запустили проект` | 0,1,2 |
| в этой теме мы уже были | `d 'njq ntvt vs e;t ,skb` | `в этой теме vs уже были` | `в этой теме мы уже были` | 0,1,2 |

### Hypotheses

1. **`vs` is whitelisted as English** - "vs" (versus) is a common English abbreviation that may be in OMFK's English whitelist, preventing conversion.

2. **Short word collision** - At 2 characters, `vs` has high ambiguity and OMFK defaults to keeping it as-is when it's a valid English word.

3. **Frequency score favors English** - The English frequency model may score "vs" higher than the Russian "мы" conversion would score.

4. **No negative evidence from context** - Even though surrounding words are Russian, OMFK doesn't use this as negative evidence against the English interpretation.

5. **Abbreviation detection** - OMFK may have special handling for lowercase abbreviations that prevents conversion.

---

## BUG GROUP 3: Punctuation Converted Instead of Preserved

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Period without space | `ghbdtn.rfr ltkf` | `приветюкак дела` | `привет.как дела` | 0,1,2 |
| Comma without space | `ghbdtn,rfr ltkf` | `приветбкак дела` | `привет,как дела` | 0,1,2 |
| Ellipsis without space | `ghbdtn...rfr ltkf` | `приветюююкак дела` | `привет...как дела` | 0,1,2 |
| Date format | `lfnf 25.12.2024` | `дата 25ю12ю2024` | `дата 25.12.2024` | 0,1,2 |
| Time format | `dcnhtxf d 15:00` | `встреча в 15Ж00` | `встреча в 15:00` | 0,1,2 |
| Time range | `dcnhtxf c 15:00-16:30` | `встреча с 15Ж00-16Ж30` | `встреча с 15:00-16:30` | 0,1,2 |
| Word in quotes | `"ghbdtn"` | `ЭприветЭ` | `"привет"` | 0,1,2 |
| Word in brackets | `[ghbdtn]` | `хприветъ` | `[привет]` | 0,1,2 |
| Word in braces | `{ghbdtn}` | `ХприветЪ` | `{привет}` | 0,1,2 |

### Hypotheses

1. **Punctuation included in token** - OMFK tokenizes `ghbdtn.rfr` as a single token and converts the `.` along with letters using the Russian layout mapping (`.` → `ю` on Russian keyboard).

2. **No punctuation boundary detection** - The tokenizer doesn't recognize `.`, `,`, `:` as word boundaries when there's no space.

3. **Layout mapping applied blindly** - Once OMFK decides to convert, it maps ALL characters through the layout, including punctuation that should be preserved.

4. **Missing punctuation preservation logic** - There's no special case to preserve ASCII punctuation characters during conversion.

5. **Date/time pattern not recognized** - Patterns like `15:00` or `25.12.2024` aren't detected as special formats that should be left unchanged.

---

## BUG GROUP 4: Colon/Semicolon Stripped

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Colon as separator | `ghbdtn: rfr ltkf` | `привет как дела` | `привет: как дела` | 0,1,2 |
| Semicolon as separator | `ghbdtn; rfr ltkf` | `привет как дела` | `привет; как дела` | 0,1,2 |

### Hypotheses

1. **Punctuation stripped during tokenization** - The tokenizer removes `:` and `;` when they appear at word boundaries.

2. **Whitespace normalization** - OMFK normalizes `word: ` to `word ` as part of cleanup.

3. **Punctuation not re-inserted** - After conversion, the punctuation that was separated isn't added back.

4. **Different code path for spaced punctuation** - When punctuation has a space after it (`ghbdtn: `), it's handled differently than attached punctuation (`ghbdtn.`).

5. **Output reconstruction bug** - The final output assembly loses standalone punctuation tokens.

---

## BUG GROUP 5: Short English Words on Hebrew Layout

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| api typed on Hebrew layout → EN | `שפן` | `שפן` | `api` | 0,1,2 |
| github typed on Hebrew layout → EN | `עןאיונ` | `gןאיונ` | `github` | 0,1,2 |

### Hypotheses

1. **Hebrew script detected, wrong target** - OMFK detects Hebrew script but doesn't have high enough confidence to convert to English.

2. **Partial conversion bug** - `github` partially converts (`g` appears) but then fails, suggesting mid-word conversion failure.

3. **Hebrew word validator interference** - The Hebrew word validator may be finding partial matches that prevent English conversion.

4. **Short word threshold** - `api` (3 chars) may be below a minimum length threshold for Hebrew→English conversion.

5. **Layout mapping gaps** - Some Hebrew characters may not have proper mappings to English equivalents.

---

## BUG GROUP 6: Hebrew-QWERTY + RussianWin Partial Conversion

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| как дела on Hebrew QWERTY → RU | `רפר לתכפ` | `как לתכי` | `как дела` | 0,1,2 |
| Final form ך preserved (Hebrew QWERTY) | `mlK` | `mlK` | `מלך` | 1,2 |

### Hypotheses

1. **Layout mapping mismatch** - Hebrew-QWERTY and RussianWin have different physical key mappings that don't align properly.

2. **First word succeeds, second fails** - `רפר` → `как` works, but `לתכפ` → `дела` fails, suggesting word-specific issues.

3. **Final form handling** - Hebrew final forms (ך, ם, ץ, ף, ן) may have special handling that breaks in certain layout combinations.

4. **activeLayouts config mismatch** - The OMFK activeLayouts setting may not match the actual system layouts during the test.

5. **Ambiguous key mapping** - Some keys on Hebrew-QWERTY may map to multiple possible Russian characters.

---

## BUG GROUP 7: Paragraph Sentence Boundary Issues

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Casual chat | `ghbdtn! rfr ltkf? ...` | `привет! как дела? данно не видел теня?...` | `привет! как дела? давно не видел тебя....` | 0,1,2 |
| Work email | `gj;fkeqcnf? jnghfdmnt...` | `пожалуйста? отправьте...` | `пожалуйста, отправьте...` | 0,1,2 |
| Tech support | `z yt vjue gjyznm?...` | `я не могу понять?...` | `я не могу понять,...` | 0,1,2 |
| Casual invitation | `pfdhf vs blv...` | `завра мы иду...` | `завтра мы идем...` | 0,1,2 |
| Birthday greeting | `ljhjufz? c lytv...` | `дорогая? с днем...` | `дорогая, с днем...` | 0,1,2 |

### Hypotheses

1. **Question mark on Russian layout** - `?` on EN layout maps to `,` on Russian layout, but OMFK outputs `?` instead of `,`.

2. **Punctuation key mapping reversed** - The test expects `.` but input has `?` (or vice versa) due to layout differences.

3. **Test case input/expected mismatch** - The test cases may have incorrect expected values that don't match the actual Russian punctuation layout.

4. **Word-level errors compound** - Individual word errors (`данно` vs `давно`, `теня` vs `тебя`) suggest typo-like issues in test data or OMFK.

5. **Sentence boundary not preserved** - OMFK may be merging sentences or changing punctuation during multi-word processing.

---

## BUG GROUP 8: Multiline/Newline Handling

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Document with header | `pfujkjdjr\n\ngthdst...` | `заголовок первые строки...` (no newlines) | `заголовок\n\nпервые строки...` | 0,1,2 |
| Shopping list | `cgbcjr gjregr:\n- [kt,...` | `список покупкЖ - хлеб...` (no newlines) | `список покупок:\n- хлеб...` | 0,1,2 |
| Only newlines | `\n\n\n` | `` | `\n\n\n` | 0,1,2 |

### Hypotheses

1. **TextEdit strips newlines** - The test's TextEdit interaction may be collapsing multiple newlines.

2. **AppleScript keystroke newline issue** - `key code` for Return may not produce actual newlines in TextEdit.

3. **OMFK processes line-by-line** - OMFK may process each line separately and lose inter-line spacing.

4. **get_result() strips whitespace** - The result retrieval function may be stripping leading/trailing whitespace including newlines.

5. **Real typing mode doesn't support newlines** - The test infrastructure may not properly handle newline characters in real typing mode.

---

## BUG GROUP 9: Whitespace Preservation

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Only spaces | `   ` | `` | `   ` | 0,1,2 |
| Single tab | `\t` | `` | `\t` | 0,1,2 |
| Tabs between words | `ghbdtn\t\tvbh` | `привет мир` | `привет\t\tмир` | 0,1,2 |

### Hypotheses

1. **TextEdit normalizes whitespace** - TextEdit may convert tabs to spaces or strip whitespace-only content.

2. **OMFK ignores whitespace-only input** - OMFK may have early-exit logic for whitespace-only strings.

3. **Tab keycode not working** - The tab key code may not produce actual tab characters in the test environment.

4. **Whitespace collapsed during output** - Multiple whitespace characters may be collapsed to single space during result retrieval.

5. **Test infrastructure limitation** - The real typing test may not support non-printable characters properly.

---

## BUG GROUP 10: Typo Auto-Correction (Possibly Intentional)

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Extra letter | `ghbdtnn` | `привет` | `приветт` | 0,1,2 |
| Inserted wrong char | `ghbdetn` | `привет` | `привует` | 0,1,2 |
| Missing last letter | `ghbdt` | `привет` | `приве` | 0,1,2 |
| Extra char at end | `ghbdtnm` | `привет` | `приветь` | 0,1,2 |
| Double last letter | `cgfcb,jj` | `спасибо` | `спасибоо` | 0,1,2 |

### Hypotheses

1. **Spell-check feature** - OMFK intentionally corrects typos to the nearest valid word, which is the expected behavior.

2. **Fuzzy matching enabled** - OMFK uses fuzzy matching to find the best word match, correcting minor typos.

3. **Test expectations wrong** - The tests expect literal conversion, but OMFK is designed to produce valid words.

4. **Word validator override** - When the literal conversion isn't a valid word, OMFK finds the closest valid word.

5. **N-gram model influence** - The language model prefers common words over rare/invalid character sequences.

---

## BUG GROUP 11: Special Characters Not in Keycodes (TEST INFRA)

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| Word in guillemets | `«ghbdtn»` | `[no layout for: ...]` | `«привет»` | 0,1,2 |
| Em dash without spaces | `ghbdtn—vbh` | `[no layout for: ...]` | `привет—мир` | 0,1,2 |
| Currency + decimal | `wtyf ¢19/99` | `[no layout for: ...]` | `цена $19.99` | 0,1,2 |
| Semver with dots | `dthcbz √1/2/3` | `[no layout for: ...]` | `версия v1.2.3` | 0,1,2 |
| Emoji + word | `🙂 ghbdtn` | `[no layout for: ...]` | `🙂 привет` | 0,1,2 |
| Emoji only | `😄` | `[no layout for: ...]` | `😄` | 0,1,2 |
| Hebrew niqqud | `שָׁלוֹם` | `[no layout for: ...]` | `שָׁלוֹם` | 0,1,2 |

### Hypotheses

1. **Characters not in keycodes.json** - These characters require Option key or special input methods not mapped in keycodes.json.

2. **Test infrastructure limitation** - The real typing test can only type characters that have direct key codes.

3. **Unicode characters need IME** - Characters like `«»`, `—`, emoji require input method editor, not direct key codes.

4. **Not an OMFK bug** - These failures are test infrastructure issues, not OMFK functionality problems.

5. **Need separate test mode** - These cases should be tested with paste+Option method, not real typing.

---

## BUG GROUP 12: Mixed Language Partial Failures

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| RU with tech terms | `bcgjkmpez API jn Google...` | `используя ФЗШ от Google...` | `используя API от Google...` | 0,1,2 |
| Mixed scripts RU+EN | `привет руддщ` | `приветhello` | `привет hello` | 0 |

### Hypotheses

1. **API converted when shouldn't be** - `API` typed on Russian layout becomes `ФЗШ`, but it should be recognized as English and preserved.

2. **No space inserted** - `приветhello` missing space suggests word boundary detection issue.

3. **English word detection in Russian context** - OMFK doesn't recognize `API` as English when surrounded by Russian text.

4. **Whitelist not checked for mixed input** - English abbreviations in Russian sentences aren't checked against English whitelist.

5. **Script detection per-word missing** - OMFK may not be detecting script changes within a sentence.

---

## BUG GROUP 13: Hebrew Mac + RussianWin Layout Mismatch (Combo 2 Only)

### Failed Cases

| Test Name | Input | Got | Expected | Combo |
|-----------|-------|-----|----------|-------|
| שלום on EN layout (Hebrew Mac) | `akuo` | `אכלו` | `שלום` | 2 |
| תודה on EN layout (Hebrew Mac) | `,usv` | `,וסו` | `תודה` | 2 |
| בבקשה on EN layout (Hebrew Mac) | `cceav` | `cheap` | `בבקשה` | 2 |
| יאללה on EN layout (Hebrew Mac) | `htkkv` | `התכנו` | `יאללה` | 2 |
| סבבה on EN layout (Hebrew Mac) | `xccv` | `xccv` | `סבבה` | 2 |
| hello on Hebrew Mac → EN | `יקךךם` | `iqKKM` | `hello` | 2 |
| привет on Hebrew Mac → RU | `עינגאמ` | `уштпфь` | `привет` | 2 |
| שלום on Russian → HE | `флгщ` | `אכלו` | `שלום` | 2 |
| test on Hebrew → EN | `אקדא` | `aqda` | `test` | 2 |
| email on Hebrew → EN | `קצשןך` | `qcwNK` | `email` | 2 |
| תודה on RU → HE | `бгым` | `бгым` | `תודה` | 2 |
| בבקשה on RU → HE | `ссуфм` | `ссуфм` | `בבקשה` | 2 |
| как дела on Hebrew → RU | `רכר ךאלכ` | `שכר Лфдл` | `как дела` | 2 |
| привет как дела on Hebrew → RU | `עינגאמ רכר ךאלכ` | `уштпфь кчк Чфдч` | `привет как дела` | 2 |

### Hypotheses

1. **Wrong layout selected** - Combo 2 test may be using Hebrew Mac when it should use Hebrew-QWERTY, or vice versa.

2. **activeLayouts config not applied** - The OMFK config may not be updated to match the test's layout combination.

3. **Layout ID mismatch** - The layout IDs in the test (`hebrew` vs `hebrew_qwerty`) may not match OMFK's internal IDs.

4. **System layout vs OMFK layout desync** - The system keyboard layout may differ from what OMFK thinks is active.

5. **Test setup order issue** - The layout switching may not complete before typing begins.

---

## What Was Done

### 1. Keycode Mapping Infrastructure
- **`scripts/generate_keycodes.py`** - Generates reverse mapping `char → (keycode, shift)` from `layouts.json`
- **`scripts/keycodes.json`** - Generated mapping for 24 layouts

### 2. Test Runner Updates (`scripts/comprehensive_test.py`)
- Added `--real-typing` / `-r` flag for real typing mode
- Added `--combo` / `-c` flag to select layout combination (0-3)
- Changed from `keystroke` to `key code` for proper physical key simulation
- Added system layout management (enable/disable/switch)
- Added original layout save/restore

### 3. Critical Fix: keystroke vs key code
- **Problem:** AppleScript `keystroke "l"` sends Unicode character `l`, not physical key press
- **Result:** On Hebrew layout, `keystroke "ltkf"` produced `שששש` instead of `ךאלכ`
- **Solution:** Use `key code 37` (physical L key) instead of `keystroke "l"`

## Files Modified
- `scripts/comprehensive_test.py` - Real typing with key codes
- `scripts/generate_keycodes.py` - Keycode mapping generator
- `scripts/keycodes.json` - Generated keycode mappings

## Priority Order for Fixes

1. **HIGH: Punctuation conversion** (Bug Groups 3, 4) - Most visible user-facing issue
2. **HIGH: Single-letter words** (Bug Group 1) - Common Russian prepositions
3. **MEDIUM: `vs` → `мы`** (Bug Group 2) - Common word
4. **MEDIUM: Short English on Hebrew** (Bug Group 5) - Tech terms
5. **MEDIUM: Hebrew-QWERTY + RussianWin** (Bug Group 6) - Layout combo issue
6. **LOW: Multiline/whitespace** (Bug Groups 8, 9) - Edge cases
7. **LOW: Typo correction** (Bug Group 10) - May be intentional
8. **INFRA: Special characters** (Bug Group 11) - Test limitation, not OMFK bug

---

## Alt Cycling Tests (NEW)

Created `scripts/alt_cycling_test.py` - hardcore Alt key behavior tests.

### Test Results: 19/19 PASSED ✓

| Test | Description | Result |
|------|-------------|--------|
| `test_alt_full_cycle_verification` | Verify Alt cycles through states (RU→original→HE) | ✓ 2 unique states |
| `test_alt_mid_phrase_affects_only_last` | Type 5 words, Alt only affects last | ✓ First 4 preserved |
| `test_alt_after_partial_word` | Alt on incomplete word (no space) | ✓ Handled gracefully |
| `test_alt_spam_during_typing` | Alt spam while typing chars | ✓ Content preserved |
| `test_alt_layout_switch_mid_phrase` | Switch layout mid-phrase, then Alt | ✓ Mixed layout handled |
| `test_alt_undo_chain_10_words` | Type 10 words, Alt 10 times | ✓ 5 state changes |
| `test_alt_with_punctuation` | Word with punctuation + Alt | ✓ Punctuation preserved |
| `test_alt_rapid_100x` | Spam Alt 100 times | ✓ Survived in 4.74s |
| `test_alt_context_boost_then_undo` | Context boost correction, then undo | ✓ Works |
| `test_alt_backspace_then_alt` | Backspace chars, then Alt | ✓ Handled |
| `test_alt_newline_boundary` | Alt across newline | ✓ Works |
| `test_alt_empty_then_type` | Alt on empty field | ✓ No crash |
| `test_alt_same_word_5x_undo` | Repeated undo (learning signal) | ✓ 5/5 undos detected |
| `test_alt_hebrew_russian_english_cycle` | Trilingual cycle HE→RU→EN | ✓ 4 unique states |
| `test_alt_timing_edge_case` | Alt immediately after space | ✓ Works |
| `test_alt_long_word` | Alt on 17-char word | ✓ 16 chars handled |
| `test_alt_multiple_words_same_line` | Multiple Alt presses in phrase | ✓ Independence verified |
| `test_alt_with_numbers` | Word with numbers + Alt | ✓ Numbers preserved |
| `test_alt_state_persistence` | Alt state persists after typing more | ✓ State persisted |

### Key Findings

1. **Alt cycling works correctly** - cycles through RU→original→HE states
2. **Only last word affected** - previous words preserved
3. **100x rapid spam survived** - no crashes
4. **Trilingual cycle works** - 4 unique states (дела, ltkf, לתכפ, לתכי)
5. **Learning signal detected** - 5/5 undos registered (but UserDictionary not implemented yet)

---

## CRITICAL BUGS FOUND (Alt Extreme Tests)

### BUG 1: Double Space Leaves Partial Character (100% repro)
**Severity: HIGH**

When user types word, double space, then Alt:
- Expected: `'привет'` → `'ghbdtn'` (full undo)
- Actual: `'привет'` → `'пghbdtn'` (first Cyrillic char remains!)

Reproduces at ANY interval between spaces (10ms-200ms tested).

**Root cause hypothesis:** OMFK processes first space, starts correction, second space interrupts, Alt undoes partial state.

---

### BUG 2: Alt + Immediate Typing Produces Garbage (PARTIALLY FIXED)
**Severity: MEDIUM** (was HIGH)
**Status: Improved but not fully fixed**

When user presses Alt and immediately starts typing next word:
- Delay < 100ms: `'ghbdtn мבה'` - Hebrew chars appear instead of Cyrillic!
- Delay >= 100ms: `'ghbdtn мир'` - correct

**MINIMUM SAFE DELAY: 100ms after Alt before typing**

**Root cause analysis:**
The fix added `cyclingActive` flag and `deferredInputs` queue to capture keystrokes during cycling.
However, `event.keyboardEventCharacters` captures characters according to the CURRENT system layout.
If user types immediately after Alt while system layout is still Hebrew (from cycling), 
the deferred characters are Hebrew instead of the intended Cyrillic.

**Race condition:**
1. Alt pressed → `cyclingActive = true`, cycling shows Hebrew alternative
2. User types `v`, `b`, `h` intending Russian `м`, `и`, `р`
3. System layout is still Hebrew → chars captured as `מ`, `ב`, `ה`
4. `flushDeferredInputs` types Hebrew chars

**Possible fix:** Store keycodes instead of characters in `deferredInputs`, 
then convert to characters using the layout that was active BEFORE cycling started.

---

### BUG 3: Backspace + Alt Shows Deleted Character (100% repro)
**Severity: MEDIUM**

When user types with typo, backspaces to fix, then Alt:
- Type: `ghbdtx` (typo)
- Backspace, type `n`
- Result after correction: `'привет'`
- After Alt: `'ghbdtxn'` - deleted `x` appears!

**Root cause hypothesis:** OMFK buffer stores all typed chars including deleted ones. Alt cycles through buffer history, not current text.

---

### BUG 4: Word Boundary Detection Broken
**Severity: MEDIUM**

Only SPACE triggers auto-correction. Other punctuation does NOT:
- `'ghbdtn '` → `'привет '` ✓
- `'ghbdtn.'` → `'ghbdtn.'` ✗ (no correction)
- `'ghbdtn,'` → `'ghbdtn,'` ✗
- `'ghbdtn!'` → `'ghbdtn!'` ✗
- `'ghbdtn?'` → `'ghbdtn?'` ✗
- `'ghbdtn\n'` → `'ghbdtn'` ✗

**Root cause hypothesis:** EventMonitor only checks for whitespace, not punctuation as word boundary.

---

## Test Files Created

- `scripts/alt_cycling_test.py` - Basic Alt cycling tests (19/19 passed)
- `scripts/alt_extreme_test.py` - Extreme timing tests (22/23 passed)
- `scripts/alt_bug_repro_test.py` - Bug reproduction tests (5 bugs found)

---

## Ticket 28 Status: NOT IMPLEMENTED

**User Dictionary + Auto-Learning** (Punto-style) is NOT implemented.

### What exists:
- `CorrectionLogger` - logs corrections to `~/.omfk/corrections.jsonl` (disabled by default)
- Logging infrastructure for learning signals

### What's missing:
- `UserDictionary` component
- Auto-learning from repeated undos (after 2+ undos → add "keep as-is" rule)
- Auto-learning from repeated manual corrections
- Settings UI for dictionary management
- Rule storage and lookup

### Evidence from tests:
- `test_alt_same_word_5x_undo` shows 5/5 undos detected
- But OMFK still auto-corrects "ghbdtn" → "привет" every time
- No learning happens - user must undo every single time
