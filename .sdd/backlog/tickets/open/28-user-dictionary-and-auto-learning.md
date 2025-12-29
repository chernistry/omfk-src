# Ticket 28: User Dictionary + Auto-Learning (Punto-style)

## Objective
Add a **user-controlled personalization layer** that reduces repeated false positives/false negatives by learning from:
- repeated **undo/rejects** of automatic corrections (2+ times → add "keep as-is" rule)
- repeated **manual corrections** of the same token (1+ times → add preference rule)

Also provide:
- **Auto-unlearning mechanism** to remove erroneously learned rules
- Small UI to **view / edit / add** dictionary rules manually

Must comply with `.sdd/architect.md`:
- local-only, privacy-first
- deterministic guardrails (still validate conversions)
- low latency (<50ms), small memory footprint

---

## User Problems This Solves

1. **Inherently ambiguous collisions** (especially Hebrew-QWERTY): the same visible token can be a valid word in the "wrong" script.
2. Users repeatedly correcting the same token manually is a strong signal that OMFK should "just do that next time".
3. Users repeatedly undoing auto-corrections is a strong signal that OMFK should stop touching that token in that context.
4. **Erroneously learned rules** can frustrate users if there's no way to automatically "forget" them.

---

## Core Learning Mechanisms

### Mechanism 1: Learn from Undo (Auto-Reject)

**Trigger:** User undoes an auto-correction 2+ times for the same token within a time window.

**Flow:**
1. OMFK auto-corrects token `T` → `C`
2. User presses Alt to undo (cycles back to original `T`)
3. OMFK records: `autoRejectCount[T]++`
4. If `autoRejectCount[T] >= 2` within last 14 days:
   - Add rule: `keepAsIs(T)` — never auto-correct this token
5. Next time OMFK sees `T`, it short-circuits and does NOT convert

**Why 2+ undos?**
- Single undo might be accidental or context-specific
- 2+ undos is a clear signal: "stop touching this word"

**Data stored:**
```swift
struct AutoRejectRecord {
    let token: String           // normalized (lowercased, trimmed)
    var count: Int              // number of undos
    var timestamps: [Date]      // for time-window filtering
    var lastSeen: Date          // for LRU eviction
}
```

### Mechanism 2: Learn from Manual Correction (Force-Apply)

**Trigger:** User manually corrects a token 1+ times using the same target hypothesis.

**Flow:**
1. User selects text or uses "convert last word" hotkey
2. User cycles through alternatives and applies correction `T` → `C` (hypothesis `H`)
3. OMFK records: `manualApplyCount[(T, H)]++`
4. If `manualApplyCount[(T, H)] >= 1`:
   - Add rule: `preferHypothesis(T, H)` — bias toward this conversion
5. Next time OMFK sees `T`, it strongly prefers hypothesis `H` (but still validates)

**Why 1+ manual correction?**
- Manual correction is explicit user intent
- User went out of their way to fix it — that's a strong signal
- Unlike auto-reject, there's no "accidental" manual correction

**Data stored:**
```swift
struct ManualApplyRecord {
    let token: String           // normalized
    let hypothesis: String      // e.g., "en_from_ru", "ru_from_he"
    var count: Int              // number of applications
    var timestamps: [Date]
    var lastSeen: Date
}
```

### Mechanism 3: Auto-Unlearning (Forgetting Erroneous Rules)

**Problem:** User might accidentally trigger learning, or context changes over time.

**Trigger:** User attempts to correct a token that has a `keepAsIs` or `preferHypothesis` rule.

**Flow A — Unlearning `keepAsIs`:**
1. Token `T` has rule `keepAsIs` (OMFK doesn't auto-correct it)
2. User manually triggers correction on `T` and applies a conversion
3. OMFK interprets this as: "user WANTS this corrected after all"
4. Decrement `autoRejectCount[T]--` or remove rule if count reaches 0
5. If user does this 2+ times, rule is fully removed

**Flow B — Unlearning `preferHypothesis`:**
1. Token `T` has rule `preferHypothesis(T, H1)` (OMFK prefers hypothesis H1)
2. User manually corrects `T` using a DIFFERENT hypothesis `H2`
3. OMFK interprets this as: "user changed their mind"
4. Options:
   - Replace rule: `preferHypothesis(T, H2)` (most recent wins)
   - Or: decrement H1 count, increment H2 count (weighted preference)
5. Recommendation: **Replace with most recent** for simplicity in v1

**Flow C — Time-based decay (optional, v2):**
1. Rules not triggered for 90+ days get lower priority
2. Rules not triggered for 180+ days are auto-removed
3. Prevents dictionary bloat from old, irrelevant rules

**Data stored:**
```swift
struct UnlearnRecord {
    let token: String
    let ruleType: RuleType      // keepAsIs or preferHypothesis
    var overrideCount: Int      // times user overrode the rule
    var timestamps: [Date]
}
```

---

## Rule Types and Actions

### `UserDictionaryRule`
```swift
struct UserDictionaryRule: Codable, Identifiable {
    let id: UUID
    let token: String                    // normalized token
    let matchMode: MatchMode             // exact, caseInsensitive
    let scope: RuleScope                 // global, perApp, perMode
    let action: RuleAction               // keepAsIs, preferLanguage, preferHypothesis
    let source: RuleSource               // learned, manual
    var evidence: RuleEvidence           // counts, timestamps
    let createdAt: Date
    var updatedAt: Date
}

enum MatchMode: String, Codable {
    case exact
    case caseInsensitive
}

enum RuleScope: Codable {
    case global
    case perApp(bundleId: String)
    case perMode(modes: [CorrectionMode])  // automatic, manual
}

enum RuleAction: Codable {
    case keepAsIs                         // never auto-correct
    case preferLanguage(Language)         // bias toward language
    case preferHypothesis(String)         // bias toward specific hypothesis
}

enum RuleSource: String, Codable {
    case learned                          // auto-learned from behavior
    case manual                           // user added manually
}

struct RuleEvidence: Codable {
    var autoRejectCount: Int = 0
    var manualApplyCount: Int = 0
    var overrideCount: Int = 0            // for unlearning
    var timestamps: [Date] = []
}
```

---

## Pipeline Integration

### Where rules are checked

```
Input Token
    │
    ▼
┌─────────────────────────────────┐
│ 1. UserDictionary.lookup(token) │  ◄── NEW: Check user rules FIRST
└─────────────────────────────────┘
    │
    ├── Rule: keepAsIs → RETURN original (skip all processing)
    │
    ├── Rule: preferHypothesis(H) → Set bias, continue to validation
    │
    ▼
┌─────────────────────────────────┐
│ 2. Built-in Whitelist           │
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ 3. ConfidenceRouter.route()     │  ◄── Apply bias from preferHypothesis
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ 4. Validation Gates             │  ◄── Still validate even with bias
└─────────────────────────────────┘
    │
    ▼
Output
```

### Learning event hooks

**In `EventMonitor.handleHotkeyPress()`:**
```swift
// After user cycles to "original" (undo)
if cycleResult == .original && lastCorrectionWasAutomatic {
    await userDictionary.recordAutoReject(
        token: lastCorrectedOriginal,
        bundleId: currentApp?.bundleIdentifier
    )
}

// After user applies a manual correction
if cycleResult != .original {
    await userDictionary.recordManualApply(
        token: originalToken,
        hypothesis: appliedHypothesis,
        bundleId: currentApp?.bundleIdentifier
    )
}
```

**In `ConfidenceRouter.route()`:**
```swift
// Check for unlearning trigger
if let rule = userDictionary.lookup(token), rule.action == .keepAsIs {
    // User is manually correcting a "keepAsIs" token
    // This is an unlearning signal
    await userDictionary.recordOverride(token: token)
}
```

---

## Thresholds and Limits

### Learning thresholds (configurable in Settings)
| Parameter | Default | Description |
|-----------|---------|-------------|
| `autoRejectThreshold` | 2 | Undos needed to add `keepAsIs` rule |
| `manualApplyThreshold` | 1 | Manual corrections needed to add `preferHypothesis` |
| `unlearningThreshold` | 2 | Overrides needed to remove a learned rule |
| `timeWindow` | 14 days | Only count events within this window |

### Storage limits
| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxRules` | 500 | Maximum rules in dictionary (LRU eviction) |
| `maxTokenLength` | 48 | Maximum token length to store |
| `maxTimestamps` | 10 | Maximum timestamps per rule (rolling window) |

### Time-based decay (v2, optional)
| Parameter | Default | Description |
|-----------|---------|-------------|
| `lowPriorityAge` | 90 days | Rules older than this get lower priority |
| `autoRemoveAge` | 180 days | Rules older than this are auto-removed |

---

## Settings UI

### New tab: "User Dictionary"

```
┌─────────────────────────────────────────────────────────────┐
│ User Dictionary                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ ☑ Enable auto-learning                                       │
│   Learn from your corrections to improve accuracy            │
│                                                              │
│ ─────────────────────────────────────────────────────────── │
│                                                              │
│ Learned Rules (12)                              [Clear All]  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ "vs"        Keep as-is       Learned (3 undos)    [×]   │ │
│ │ "api"       Prefer English   Learned (2 applies)  [×]   │ │
│ │ "гугл"      Keep as-is       Learned (2 undos)    [×]   │ │
│ │ "נאה"       Prefer English   Learned (1 apply)    [×]   │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ Manual Rules (3)                                [Add Rule]   │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ "iPhone"    Keep as-is       Manual               [×]   │ │
│ │ "GitHub"    Keep as-is       Manual               [×]   │ │
│ │ "TODO"      Keep as-is       Manual               [×]   │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ ─────────────────────────────────────────────────────────── │
│                                                              │
│ Advanced                                                     │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Undos to learn "keep as-is":     [2] ▼                  │ │
│ │ Manual corrections to learn:      [1] ▼                  │ │
│ │ Overrides to unlearn:             [2] ▼                  │ │
│ │ Learning time window:             [14 days] ▼            │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                              │
│ [Export...]  [Import...]  [Reset to Defaults]                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Add Rule Dialog

```
┌─────────────────────────────────────────────────────────────┐
│ Add Dictionary Rule                                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Token:  [________________]                                   │
│                                                              │
│ Action: ○ Keep as-is (never auto-correct)                   │
│         ○ Prefer English                                     │
│         ○ Prefer Russian                                     │
│         ○ Prefer Hebrew                                      │
│                                                              │
│ Scope:  ○ Global (all apps)                                 │
│         ○ Current app only (com.brave.Browser)              │
│                                                              │
│ Match:  ○ Exact match                                       │
│         ○ Case-insensitive                                   │
│                                                              │
│                              [Cancel]  [Add Rule]            │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create `UserDictionary.swift` (actor)
   - JSON storage in `~/.omfk/user_dictionary.json`
   - CRUD operations: add, remove, update, list
   - Lookup with O(1) hash map
   - LRU eviction when limit reached

2. Create `UserDictionaryModels.swift`
   - `UserDictionaryRule` struct
   - `RuleAction`, `RuleScope`, `RuleSource` enums
   - `RuleEvidence` for tracking counts

### Phase 2: Learning Hooks
3. Add learning event recording
   - `recordAutoReject(token:bundleId:)` — called on undo
   - `recordManualApply(token:hypothesis:bundleId:)` — called on manual correction
   - `recordOverride(token:)` — called when user corrects a "protected" token

4. Integrate into `EventMonitor.handleHotkeyPress()`
   - Detect undo vs apply
   - Call appropriate recording method
   - Check thresholds and create rules

### Phase 3: Pipeline Integration
5. Add lookup in `ConfidenceRouter.route()`
   - Check user dictionary before built-in whitelist
   - Apply `keepAsIs` short-circuit
   - Apply `preferHypothesis` bias

6. Implement bias application
   - Boost score for preferred hypothesis
   - Still require validation gates

### Phase 4: Unlearning
7. Implement override detection
   - Detect when user corrects a "keepAsIs" token
   - Detect when user uses different hypothesis than preferred

8. Implement rule removal
   - Decrement counts on override
   - Remove rule when count reaches 0

### Phase 5: Settings UI
9. Add "User Dictionary" tab to Settings
   - List learned and manual rules
   - Delete individual rules
   - Clear all learned rules

10. Add "Add Rule" dialog
    - Token input
    - Action selection
    - Scope selection

### Phase 6: Testing
11. Unit tests
    - Rule matching (exact, case-insensitive)
    - Threshold logic
    - LRU eviction
    - Unlearning logic

12. Integration tests
    - 2 undos → keepAsIs rule created
    - 1 manual apply → preferHypothesis rule created
    - 2 overrides → rule removed
    - Bias affects routing but validation still applies

---

## Files Affected

### New files
- `OMFK/Sources/Core/UserDictionary.swift`
- `OMFK/Sources/Core/UserDictionaryModels.swift`
- `OMFK/Sources/UI/UserDictionaryView.swift`
- `OMFK/Sources/UI/AddRuleDialog.swift`
- `OMFK/Tests/UserDictionaryTests.swift`

### Modified files
- `OMFK/Sources/Core/ConfidenceRouter.swift` — add lookup and bias
- `OMFK/Sources/Engine/EventMonitor.swift` — add learning hooks
- `OMFK/Sources/UI/SettingsView.swift` — add new tab
- `OMFK/Sources/Settings/SettingsStore.swift` — add dictionary settings

---

## Definition of Done

### Functional
- [ ] After 2+ undos of same auto-correction, OMFK stops auto-correcting that token
- [ ] After 1+ manual corrections with same hypothesis, OMFK prefers that hypothesis
- [ ] After 2+ overrides of a learned rule, the rule is removed (unlearning)
- [ ] User can view all rules in Settings
- [ ] User can delete individual rules
- [ ] User can add manual rules
- [ ] User can clear all learned rules
- [ ] User can toggle learning on/off

### Technical
- [ ] Dictionary lookup is O(1) and adds <1ms to hot path
- [ ] Dictionary is bounded (max 500 rules, LRU eviction)
- [ ] Dictionary is local-only (`~/.omfk/user_dictionary.json`)
- [ ] Tokens >48 chars are not stored
- [ ] `swift test` passes with new coverage

### Privacy
- [ ] Learning can be disabled in Settings
- [ ] "Clear all" removes all learned data
- [ ] No tokens logged in plaintext (use hashes in logs)

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Learning wrong rules from accidental undos | Medium | Require 2+ undos, time window |
| Dictionary grows unbounded | Low | LRU eviction, max 500 rules |
| Unlearning too aggressive | Medium | Require 2+ overrides to remove |
| Performance impact from lookup | Low | O(1) hash map, <1ms |
| Privacy concerns about stored tokens | Medium | Local-only, clearable, toggleable |

---

## Dependencies

- None (self-contained feature)

## Blocked By

- None

## Blocks

- Ticket 29: Advanced learning (n-gram context, per-app profiles) — builds on this
