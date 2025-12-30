# OMFK Bug Fixing Session - Active Work

## 🎯 Mission
Fix critical bugs in OMFK (keyboard layout auto-switcher for RU/EN/HE). **Current status: 60/161 tests passing (37%)**. Your goal: find elegant solutions that fix MULTIPLE issues at once, not just patch symptoms.

## 🔥 Critical Context

### What OMFK Does
Automatically detects when you type in the wrong keyboard layout and converts it in real-time:
- `ghbdtn` (EN keyboard, RU intended) → `привет` 
- `akuo` (EN keyboard, HE intended) → `שלום`
- Should work for: RU↔EN, HE↔EN, RU↔HE (via composition)

### The Problem
E2E tests reveal systematic failures. Users type real text, OMFK should auto-correct, but it doesn't.

## 📊 Test Results (2024-12-30)

| Category | Pass | Fail | % | Critical Issues |
|----------|------|------|---|----------------|
| single_words | 16 | 6 | 73% | `,tp` → `без` fails |
| context_boost_hard | 6 | 4 | 60% | `k.,k.` → `люблю` fails |
| punctuation_triggers | 3 | 13 | 19% | `?`, `;`, `()` don't trigger |
| typos_and_errors | 0 | 8 | 0% | All fail |
| numbers_and_special | 0 | 8 | 0% | Times, dates, phones fail |
| hebrew_cases | 7 | 20 | 26% | Poor HE support |

## 🐛 GitHub Issues (Priority Order)

### Issue #1: Comma/Period Inside Words 🔴 HIGH
**Problem:** `k.,k.` should become `люблю`, but stays `k.,k.`
- `.` = `ю` on RU layout, `,` = `б` on RU layout
- Also affects: `,tp` → `без`, `j,` → `об`, `epyf.n` → `узнают`

**What We Fixed:**
- ✅ LayoutMapper now converts `.` and `,` correctly (unit test passes!)
- ✅ `k.,k.` → `люблю` works in isolation

**What Still Fails:**
- ❌ E2E test: word not converted in real usage
- ❌ Detector rejects it or confidence too low
- ❌ From logs: `Path: USER_DICT_PREFER | Result: en (Conf: 1.00)` - thinks it's English!

**Root Cause Hypothesis:**
The detection pipeline rejects words with punctuation as "invalid" or classifies them as English with high confidence. The conversion works, but detection prevents it from running.

### Issue #2: Single-Letter Prepositions 🔴 HIGH
**Problem:** `e vtyz` should become `у меня`, but becomes `e меня`
- Single letters `e`, `r`, `k` should convert to `у`, `к` in context
- Also affects: `r cj;fktyb.` → `к сожалению`

**Pattern:** First word of phrase not converting when it's a single letter.

### Issue #3: Punctuation Word Boundaries 🟡 MEDIUM
**Problem:** `ghbdtn?rfr` should split into two words, but doesn't
- `?`, `;`, `:`, `()`, `[]`, `{}`, `«»`, `—`, `/`, `\` don't trigger word boundary
- Only space and newline trigger currently

## 🧠 Key Insights for You

### Architecture
```
User types → EventMonitor (buffers chars) → Word boundary? → 
  → ConfidenceRouter (detects language) → LayoutMapper (converts) → 
  → Validation (checks if valid word) → Apply or Reject
```

### The Detection Pipeline (ConfidenceRouter.swift)
1. **Character analysis**: counts latin/cyrillic/hebrew chars
2. **Whitelist check**: common words bypass detection
3. **N-gram scoring**: trigram models for RU/EN/HE
4. **Ensemble**: combines NLLanguageRecognizer + char sets + n-grams
5. **Validation**: checks if converted word is "valid"

### Current Bottlenecks
1. **Punctuation handling**: System doesn't know if `.` is end-of-sentence or part of word
2. **Validation too strict**: Rejects valid words with unusual patterns
3. **Context not used**: Single letters should use next word for context
4. **Word boundaries incomplete**: Many punctuation marks don't trigger

## 💡 Your Challenge

**Think like a UX designer + algorithms expert:**

1. **Find a unifying solution** that fixes Issues #1, #2, #3 together
   - Maybe: smarter word boundary detection?
   - Maybe: lookahead for context before rejecting?
   - Maybe: punctuation-aware validation?

2. **Consider the user's mental model:**
   - User types naturally, with punctuation, typos, mixed languages
   - User expects "it just works" - no manual intervention
   - False positives (wrong correction) worse than false negatives (no correction)

3. **Propose solutions with trade-offs:**
   - What's the simplest fix that solves 80% of issues?
   - What's the "perfect" solution (even if complex)?
   - What can we do in 1 hour vs 1 day?

## 📁 Key Files

- `OMFK/Sources/Engine/EventMonitor.swift` - Buffers input, detects word boundaries
- `OMFK/Sources/Core/ConfidenceRouter.swift` - Main detection logic
- `OMFK/Sources/Core/LayoutMapper.swift` - Character conversion (FIXED for Issue #1)
- `OMFK/Sources/Resources/language_data.json` - Punctuation config
- `tests/test_cases.json` - All test cases
- `.sdd/backlog/wrongs.md` - Detailed failure analysis

## 🎬 What to Do

1. **Read wrongs.md** - understand ALL failure patterns
2. **Analyze the root cause** - why does detection fail?
3. **Propose solutions** - think creatively, consider edge cases
4. **Implement & test** - fix it, run tests, iterate
5. **Document** - explain what you did and why

## 🚀 Success Criteria

- **Minimum:** Issue #1 fully working (E2E test passes)
- **Good:** Issues #1 + #2 working (70%+ tests pass)
- **Excellent:** Issues #1 + #2 + #3 working (85%+ tests pass)
- **Perfect:** All issues resolved, no UX regressions

## 💬 Communication Style

- Be direct, no fluff
- Show your reasoning
- Test hypotheses quickly
- Iterate based on results
- Ask questions if architecture unclear

**Remember:** You're not just fixing bugs, you're making OMFK work the way users expect. Think holistically!
