# Comma/Period in Words Issue

## Problem
Words containing comma (`,`) or period (`.`) are not fully converted when typed as single words.

### Examples
| Input | Expected | Actual | Status |
|-------|----------|--------|--------|
| `hf,jnftn` | `работает` | `hf,отает` | ❌ Partial |
| `k.,k.` | `люблю` | `любл.` | ❌ Partial |
| `cj;fktyb.` | `сожалению` | `сожалени.` | ❌ Partial |
| `z nt,z k.,k.` | `я тебя люблю` | `я тебя люблю` | ✅ Works with context |

## Root Cause

### Layout Mapping
- Russian layout: `,` → `б`, `.` → `ю`
- LayoutMapper correctly handles these mappings (lines 260-264 in LayoutMapper.swift)
- Conversion logic is correct

### The Real Problem: Confidence Scoring
Words with comma/period have **low confidence** when processed alone:
1. Single word `k.,k.` → low confidence → not converted
2. Multi-word `z nt,z k.,k.` → context boost → high confidence → converted ✅

This is why Issue #1 was marked as "fixed" - it works with context boost, but fails for single words.

## What Was Tried

### Attempt 1: Fix splitBufferContent
```swift
// Added logic to preserve comma/period between letters
if (chars[end - 1] == "." || chars[end - 1] == ",") {
    let hasPrecedingLetter = end > 1 && chars[end - 2].isLetter
    let hasFollowingLetter = end < chars.count && chars[end].isLetter
    
    if hasPrecedingLetter && (end == chars.count || hasFollowingLetter) {
        break  // Don't strip
    }
}
```

**Result:** Didn't help - problem is not in token splitting, but in confidence scoring.

## Solution Options

### Option 1: Boost Confidence for б/ю Patterns
Detect when a word contains `,` or `.` that could map to `б` or `ю`, and boost confidence:

```swift
// In ConfidenceRouter or CorrectionEngine
if token.contains(",") || token.contains(".") {
    // Check if these could be Russian letters
    let potentialRussian = token.replacingOccurrences(of: ",", with: "б")
                                .replacingOccurrences(of: ".", with: "ю")
    // Check if result is valid Russian word
    if isValidRussianWord(potentialRussian) {
        confidence += 0.2  // Boost
    }
}
```

### Option 2: Pre-process Tokens
Before language detection, try converting `,` → `б` and `.` → `ю` and check if result is valid:

```swift
func preprocessToken(_ token: String) -> String {
    if token.contains(",") || token.contains(".") {
        let withRussianPunct = token
            .replacingOccurrences(of: ",", with: "б")
            .replacingOccurrences(of: ".", with: "ю")
        
        if isLikelyRussian(withRussianPunct) {
            return withRussianPunct
        }
    }
    return token
}
```

### Option 3: Special Case in LayoutMapper
Add special handling for single-word tokens with comma/period:

```swift
// In convert() function
if text.count <= 15 && (text.contains(",") || text.contains(".")) {
    // Force conversion even with low confidence
    // These are likely Russian words with б/ю
}
```

## Recommended Approach

**Option 1** (Confidence Boost) is cleanest:
1. Detect comma/period in token
2. Check if conversion would create valid Russian word
3. Boost confidence if yes
4. Let existing logic handle conversion

## Files to Modify

1. **OMFK/Sources/Core/ConfidenceRouter.swift** (line ~300)
   - Add confidence boost for tokens with comma/period
   - Check against Russian word frequency model

2. **OMFK/Sources/Engine/CorrectionEngine.swift** (line ~250)
   - Alternative: boost confidence before routing

## Test Cases

Add to `tests/test_cases.json`:
```json
{
  "comma_period_single_words": {
    "description": "Single words with comma/period (б/ю mapping)",
    "cases": [
      {"input": "hf,jnftn", "expected": "работает", "desc": "работает"},
      {"input": "k.,k.", "expected": "люблю", "desc": "люблю"},
      {"input": ",tp", "expected": "без", "desc": "без"},
      {"input": ",ele", "expected": "буду", "desc": "буду"},
      {"input": "j,", "expected": "об", "desc": "об"}
    ]
  }
}
```

## How to Test

```bash
cd /Users/sasha/IdeaProjects/personal_projects/omfk

# Build OMFK
swift build -c release

# Start OMFK
killall OMFK 2>/dev/null
.build/release/OMFK &
sleep 2

# Run comma/period tests
python3 tests/run_tests.py comma --real-typing

# Expected output:
# COMMA IN WORDS
# ✗ работает with comma: 'hf,jnftn' → 'hf,отает' (expected 'работает')
# ✗ люблю with periods: 'k.,k.' → 'любл.' (expected 'люблю')
# ✗ сожалению with period at end: 'cj;fktyb.' → 'сожалени.' (expected 'сожалению')
# TOTAL: 0 passed, 3 failed

# After fix, should show:
# TOTAL: 3 passed, 0 failed
```

## Related Issues

- **Issue #1:** Comma/period inside words (marked as fixed, but only works with context)
- Current status: Works with context boost, fails for single words

## Priority

🟡 **MEDIUM** - Affects common Russian words, but workaround exists (type multiple words for context boost)

## Next Steps

1. Implement Option 1 (confidence boost)
2. Test with single-word cases
3. Verify doesn't break existing tests
4. Re-open Issue #1 or create new issue for single-word case
