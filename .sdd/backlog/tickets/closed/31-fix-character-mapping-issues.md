# Ticket 31: Fix Character Mapping Issues Found in E2E Tests

## Problem

E2E tests revealed 4 character mapping issues where certain ASCII characters are not being converted to their Cyrillic equivalents when they should be.

**Test Results:** 22/30 (73%) passing, 8 failures related to these issues.

## Issue 1: Semicolon `;` Not Converting to `ж`

**Severity:** HIGH — affects common Russian words

**Examples from tests:**
```
Input:  "gj;fkeqcnf"     → Got: "по;алуйста"   Expected: "пожалуйста"
Input:  "r cj;fktyb."    → Got: "к со;алению"  Expected: "к сожалению"  
Input:  "pfrf;b"         → Got: "зака;и"       Expected: "закажи"
```

**Root Cause:** 
In commit fixing punctuation preservation, `;` was added to `preserveChars` in `LayoutMapper.swift`:
```swift
// ASCII punctuation that should NOT be converted through layout mapping
".", ",", "!", "?", ":", ";", "-", "_",
```

But `;` on US keyboard maps to `ж` on Russian keyboard — it's a letter, not punctuation in this context.

**Fix:** Remove `;` from `preserveChars`. The semicolon should only be preserved when it's actually used as punctuation (after a word), not when it's part of a word being typed on wrong layout.

---

## Issue 2: Apostrophe `'` Not Converting to `э`

**Severity:** HIGH — affects common Russian words starting with `э`

**Examples from tests:**
```
Input:  "d 'njv ujle"    → Got: "в 'том году"  Expected: "в этом году"
```

**Root Cause:**
Same as Issue 1 — `'` was added to `preserveChars`:
```swift
"\"", "'", "/", "\\", "@", "#", "$", "%", "^", "&", "*", "+", "=",
```

But `'` on US keyboard maps to `э` on Russian keyboard.

**Fix:** Remove `'` from `preserveChars`.

---

## Issue 3: Hebrew `,` (Comma) Not Converting to `ת`

**Severity:** MEDIUM — affects Hebrew words starting with ת

**Examples from tests:**
```
Input:  ",usv"           → Got: ",ודה"         Expected: "תודה"
```

**Root Cause:**
`,` was added to `preserveChars`, but on Hebrew keyboard `,` maps to `ת` (tav).

**Fix:** Remove `,` from `preserveChars`, OR handle Hebrew layout specially.

---

## Issue 4: Test Input Typos

**Severity:** LOW — test data issues, not OMFK bugs

**Examples:**
```
Test: whatsapp_context
  Input:  "ckeim"        → Got: "слушь"        Expected: "слышь"
  Correct input should be: "cksim" (ы = s, not e)

Test: long_plan  
  Input:  "pfdhf"        → Got: "завра"        Expected: "завтра"
  Correct input should be: "pfднhf" or verify mapping
```

**Fix:** Correct the test inputs in `realistic_e2e_test.py`.

---

## Proposed Solution

### For Issues 1-3: Selective Punctuation Preservation

The problem is that `preserveChars` is too aggressive. We need to distinguish:
- **Punctuation at word boundaries** — should be preserved (e.g., `hello.` → `привет.`)
- **Characters inside words** — should be converted (e.g., `gj;fkeqcnf` → `пожалуйста`)

**Option A: Remove problematic chars from preserveChars**
```swift
// Only preserve punctuation that is NEVER a letter in any layout
private static let preserveChars: Set<Character> = [
    ".", "!", "?", ":", "-", "_",
    "(", ")", "[", "]", "{", "}",
    // Remove: ";", "'", ",", "\"" — these map to letters
]
```

**Option B: Context-aware preservation**
Only preserve punctuation when:
1. It's at the start or end of the token
2. It's surrounded by whitespace
3. The character before/after is also punctuation

### For Issue 4: Fix Test Data
Update `realistic_e2e_test.py` with correct input mappings.

---

## Files to Modify

1. `OMFK/Sources/Core/LayoutMapper.swift` — adjust `preserveChars`
2. `scripts/realistic_e2e_test.py` — fix test input typos

## Verification

After fix, these tests should pass:
- `email_request`: "пожалуйста отправьте отчет"
- `preposition_v`: "в этом году"
- `preposition_k`: "к сожалению"
- `mixed_brand`: "закажи на Amazon"
- `hebrew_toda`: "תודה"

Run: `python3 scripts/realistic_e2e_test.py`

## Definition of Done

- [ ] `;` converts to `ж` inside words
- [ ] `'` converts to `э` inside words
- [ ] `,` converts to `ת` for Hebrew
- [ ] Punctuation at word boundaries still preserved
- [ ] E2E tests pass at 90%+
- [ ] No regression in existing alt_cycling_test.py (19/19)
