# GitHub Issues E2E Test Results
**Date:** 2026-01-01  
**OMFK Version:** v1.4  
**Test Framework:** `.venv/bin/python tests/run_tests.py --real-typing`

## Summary
- **Total:** 27 test cases
- **Passed (Issues #2/#3/#6/#7):** 22/23
- **Failed (Issues #2/#3/#6/#7):** 1/23
- **Notes:** Issue #8 still flaky/unresolved (not included in the above counts).

## Results by Issue

### 🟡 Issue #8: Emoji and Unicode
Currently flaky/unresolved in the new OMFKTestHost-based harness.

### 🟡 Issue #2: Single-letter prepositions (3/4 passed)
- ✅ `e→у` and `r→к` now convert reliably
- ❌ One remaining mismatch in a longer phrase (word choice/lexicon scoring, not preposition handling)

### ✅ Issue #3: Punctuation boundaries (9/9 passed)
All boundary cases now pass in real-typing E2E.

### ✅ Issue #6: Technical text (5/5 passed)
Paths, filenames, UUIDs, versions preserved as-is.

### ✅ Issue #7: Numbers with punctuation (5/5 passed)
Times/dates/percents/versions preserved as-is.

## Key Findings

1. **E2E focus reliability improved** via dedicated `OMFKTestHost` (no more “typing into nowhere” for #3/#6/#7).
2. **Technical + numeric protection works** (Issues #6/#7 now stable and passing).
3. **Punctuation boundaries fixed** (Issue #3 now passing).
4. **Prepositions mostly fixed** (Issue #2 down to 1 remaining mismatch).

## Next Steps

Priority order for fixes:
1. **Issue #8** (Unicode/emoji) - currently flaky in E2E
2. **Issue #2** (remaining mismatch) - investigate lexicon/scoring for the last word choice

## Test Command
```bash
cd /Users/sasha/IdeaProjects/personal_projects/omfk
.venv/bin/python tests/run_tests.py issue_2 issue_3 issue_6 issue_7 --real-typing
```

Full results: `tests/archived/github_issues_results_2026_01_01.txt`
