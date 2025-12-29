# Ticket 30: Realistic User Behavior Tests

## Problem

Current E2E tests use "clean" inputs:
- Perfect typing speed
- No typos
- No backspaces
- No pauses
- Isolated words/phrases

Real users behave messily:
- Variable typing speed (fast bursts, slow thinking)
- Frequent typos and corrections
- Pauses mid-word while thinking
- Random Alt presses to "check" what OMFK did
- App switching mid-sentence
- Mouse/arrow navigation to edit earlier text

**Result:** Tests pass but real-world usage reveals bugs.

## User Story

As a developer, I want tests that simulate realistic human typing behavior, so that I can catch bugs that only appear in real-world usage patterns.

## Proposed Test Cases

### 1. Variable Speed Typing
```python
def test_variable_speed_typing():
    """Type with realistic human speed variations."""
    # Fast burst (experienced typist)
    type_word("ghbdtn", char_delay=0.01)  # 100 WPM
    type_space()
    
    # Slow, thinking
    type_word("rfr", char_delay=0.08)     # 15 WPM, thinking
    type_space()
    
    # Medium speed
    type_word("ltkf", char_delay=0.03)    # 50 WPM
    type_space()
    
    # Verify all words corrected despite speed variation
```

### 2. Typo and Backspace Flow
```python
def test_typo_backspace_flow():
    """Type with typos and corrections like real users."""
    type_word("ghbdtnn")  # Typo: extra 'n'
    press_backspace()
    type_space()
    
    type_word("rfkk")     # Typo: 'kk' instead of 'r'
    press_backspace(2)
    type_word("r")
    type_space()
    
    # Verify corrections work despite editing
```

### 3. Mid-Word Pause
```python
def test_mid_word_pause():
    """Pause in middle of word (user thinking)."""
    type_chars("ghb")
    time.sleep(2.0)       # Long pause - thinking
    type_chars("dtn")
    type_space()
    
    # Verify word still corrected after pause
```

### 4. Random Alt Checks
```python
def test_random_alt_checks():
    """User randomly presses Alt to verify corrections."""
    words = ["ghbdtn", "rfr", "ltkf", "e", "vtyz"]
    
    for i, word in enumerate(words):
        type_word(word)
        type_space()
        
        # 30% chance user checks with Alt
        if random.random() < 0.3:
            press_option()
            time.sleep(0.3)
            press_option()  # Undo check
    
    # Verify final result is correct
```

### 5. Burst Then Correct
```python
def test_burst_then_correct():
    """Type fast, then go back and fix."""
    # Fast burst with mistakes
    type_word("ghbdtn rfk ltka", char_delay=0.01)
    
    # Go back with arrows
    press_key("left", count=5)
    press_backspace()
    type_char("f")
    
    # Continue typing
    press_key("end")
    type_space()
    type_word("e vtyz")
    
    # Verify corrections handle navigation
```

### 6. Sustained Typing (Stress Test)
```python
def test_sustained_typing_5min():
    """Type continuously for 5 minutes."""
    words = load_russian_word_list()  # 1000+ words
    start = time.time()
    
    while time.time() - start < 300:  # 5 minutes
        word = random.choice(words)
        en_word = convert_to_en_layout(word)
        type_word(en_word, char_delay=random.uniform(0.01, 0.05))
        type_space()
        
        # Occasional Alt check
        if random.random() < 0.05:
            press_option()
            press_option()
    
    # Check memory usage, no crashes
```

### 7. App Switch Mid-Sentence
```python
def test_app_switch_mid_sentence():
    """Switch apps while typing."""
    type_word("ghbdtn")
    type_space()
    
    # Switch to another app
    switch_to_app("Safari")
    time.sleep(0.5)
    switch_to_app("TextEdit")
    
    # Continue typing
    type_word("rfr ltkf")
    type_space()
    
    # Verify context preserved or gracefully reset
```

### 8. Mixed Language Session
```python
def test_mixed_language_session():
    """Realistic multilingual typing session."""
    # Start in Russian
    type_phrase("ghbdtn rfr ltkf")  # привет как дела
    
    # Switch to English mid-thought
    type_phrase(" and then hello world ")
    
    # Back to Russian
    type_phrase("b gjnjv ghjljk;bv")  # и потом продолжим
    
    # Hebrew word
    switch_layout("Hebrew")
    type_phrase("שלום")
    switch_layout("US")
    
    # Verify each segment handled correctly
```

---

## Tests for Ticket 28: User Dictionary + Auto-Learning

### 9. Repeated Undo Triggers Learning
```python
def test_repeated_undo_triggers_keepasis():
    """After 2+ undos, word should stop being auto-corrected."""
    word = "vs"  # ambiguous: "vs" (EN) or "мы" (RU)
    
    # First occurrence: type, get corrected, undo
    clear_field()
    type_word("d 'njv ujle vs ", "us")  # "в этом году vs "
    result1 = get_result()
    assert "мы" in result1, "Should auto-correct to мы"
    
    press_option()  # Undo #1
    time.sleep(0.3)
    
    # Second occurrence: same word, undo again
    clear_field()
    type_word("vs ", "us")
    press_option()  # Undo #2
    time.sleep(0.3)
    
    # Third occurrence: should NOT auto-correct anymore
    clear_field()
    type_word("vs ", "us")
    result3 = get_result()
    assert "vs" in result3, "After 2 undos, should keep 'vs' as-is"
    assert "мы" not in result3, "Should NOT convert to мы anymore"
```

### 10. Manual Correction Triggers Preference
```python
def test_manual_correction_triggers_preference():
    """After 1+ manual correction, OMFK should prefer that hypothesis."""
    # Type Hebrew word that could be English
    clear_field()
    type_word("נאה", "hebrew")  # Could be "nah" in English
    type_space()
    
    # Manually correct to English
    press_option()  # Cycle to find English
    # Keep pressing until we get "nah"
    for _ in range(5):
        result = get_result()
        if "nah" in result:
            break
        press_option()
    
    time.sleep(0.5)
    
    # Second occurrence: should auto-prefer English now
    clear_field()
    type_word("נאה ", "hebrew")
    result2 = get_result()
    # Should either be "nah" or strongly biased toward English
    # (exact behavior depends on implementation)
```

### 11. Unlearning via Override
```python
def test_unlearning_via_override():
    """If user corrects a 'keepAsIs' word, rule should weaken/remove."""
    word = "api"  # Assume it was learned as keepAsIs
    
    # Setup: trigger keepAsIs learning (2 undos)
    for _ in range(2):
        clear_field()
        type_word("api ", "us")
        press_option()  # Undo
        time.sleep(0.3)
    
    # Now "api" should be keepAsIs
    clear_field()
    type_word("api ", "us")
    result1 = get_result()
    assert "api" in result1.lower(), "Should keep as-is after learning"
    
    # Override: manually correct it (user changed mind)
    press_option()  # Cycle to Russian "фзш"
    time.sleep(0.3)
    
    # Do it again (2nd override)
    clear_field()
    type_word("api ", "us")
    press_option()
    time.sleep(0.3)
    
    # Rule should be weakened/removed
    # Next occurrence may auto-correct again
    # (exact behavior depends on threshold settings)
```

### 12. Learning Persists Across Sessions
```python
def test_learning_persists_across_restart():
    """Learned rules should survive OMFK restart."""
    word = "grit"  # Will learn to keep as-is
    
    # Trigger learning
    for _ in range(2):
        clear_field()
        type_word("grit ", "us")
        press_option()
        time.sleep(0.3)
    
    # Restart OMFK
    stop_omfk()
    time.sleep(1)
    start_omfk()
    time.sleep(2)
    
    # Verify rule persisted
    clear_field()
    type_word("grit ", "us")
    result = get_result()
    assert "grit" in result.lower(), "Learned rule should persist after restart"
```

### 13. Learning with Context (Per-App)
```python
def test_learning_per_app_context():
    """Learning can be scoped to specific apps."""
    word = "test"
    
    # In TextEdit: learn to keep as-is
    switch_to_app("TextEdit")
    for _ in range(2):
        clear_field()
        type_word("test ", "us")
        press_option()
        time.sleep(0.3)
    
    # In another app: should still auto-correct (if per-app enabled)
    # Or should also be keepAsIs (if global)
    # This tests the scope behavior
    switch_to_app("Notes")
    clear_field()
    type_word("test ", "us")
    result = get_result()
    # Behavior depends on scope setting - document actual result
```

---

## Tests for Ticket 29: Extended Alt Cycling

### 14. First Round Shows Two States
```python
def test_first_round_two_states():
    """First round of Alt cycling shows only 2 states."""
    clear_field()
    type_word("ghbdtn", "us")
    type_space()
    
    states = [get_result().strip()]
    
    # Press Alt twice - should cycle through 2 states
    press_option()
    states.append(get_result().strip())
    
    press_option()
    states.append(get_result().strip())
    
    # Third state should be same as first (cycle complete)
    assert states[2] == states[0], "First round should have only 2 states"
    assert len(set(states[:2])) == 2, "Should have 2 unique states"
```

### 15. Second Round Adds Third Language
```python
def test_second_round_three_states():
    """Second round of Alt cycling adds third language."""
    clear_field()
    type_word("ghbdtn", "us")  # привет
    type_space()
    
    states = []
    
    # Complete first round (2 states)
    for _ in range(3):
        press_option()
        states.append(get_result().strip())
    
    # Continue into second round
    for _ in range(3):
        press_option()
        states.append(get_result().strip())
    
    unique_states = set(states)
    
    # Should now have 3 unique states (RU, EN, HE)
    assert len(unique_states) >= 3, f"Second round should have 3 states, got {len(unique_states)}: {unique_states}"
```

### 16. Typing Resets Cycling Round
```python
def test_typing_resets_cycling_round():
    """Typing after Alt should reset to round 1."""
    clear_field()
    type_word("ghbdtn", "us")
    type_space()
    
    # Enter second round
    for _ in range(4):
        press_option()
    
    # Type something new
    type_word("vbh", "us")  # мир
    type_space()
    
    # Alt should be back to round 1 (2 states)
    states = [get_result().strip()]
    press_option()
    states.append(get_result().strip())
    press_option()
    states.append(get_result().strip())
    
    # Should cycle back to first state after 2 presses
    assert states[2] == states[0], "Should reset to round 1 after typing"
```

### 17. Third Language Validation
```python
def test_third_language_validated():
    """Third language alternative should be validated before showing."""
    clear_field()
    
    # Type word that has no valid Hebrew conversion
    type_word("xyz", "us")  # Gibberish
    type_space()
    
    # Try to reach third language
    states = set()
    for _ in range(6):
        press_option()
        states.add(get_result().strip())
    
    # Should NOT show invalid Hebrew gibberish
    # Only valid conversions should appear
    for state in states:
        # Each state should be either original or valid word
        assert len(state) > 0, "Should not show empty state"
```

### 18. Full Trilingual Cycle
```python
def test_full_trilingual_cycle():
    """Test complete RU→EN→HE cycle with realistic word."""
    clear_field()
    
    # Type Russian word on English layout
    type_word("ghbdtn", "us")  # привет
    type_space()
    
    initial = get_result().strip()
    
    # Collect all unique states through multiple rounds
    all_states = {initial}
    for _ in range(10):
        press_option()
        all_states.add(get_result().strip())
    
    # Should have representations in all 3 scripts
    has_cyrillic = any(any('\u0400' <= c <= '\u04FF' for c in s) for s in all_states)
    has_latin = any(any('a' <= c.lower() <= 'z' for c in s) for s in all_states)
    has_hebrew = any(any('\u0590' <= c <= '\u05FF' for c in s) for s in all_states)
    
    print(f"States found: {all_states}")
    print(f"Cyrillic: {has_cyrillic}, Latin: {has_latin}, Hebrew: {has_hebrew}")
    
    assert has_cyrillic, "Should have Cyrillic state"
    assert has_latin, "Should have Latin state"
    # Hebrew may or may not be present depending on validation
```

---

## Combined Integration Tests

### 19. Learning + Cycling Integration
```python
def test_learning_affects_cycling():
    """Learned preferences should affect cycling order/availability."""
    word = "ghbdtn"
    
    # Learn preference for original (English)
    for _ in range(2):
        clear_field()
        type_word(f"{word} ", "us")
        press_option()  # Undo to original
        time.sleep(0.3)
    
    # Now cycling should start from learned preference
    clear_field()
    type_word(f"{word} ", "us")
    
    # First state should be the learned preference (original)
    first_state = get_result().strip()
    # Behavior depends on implementation - document actual
```

### 20. Realistic Session with Learning
```python
def test_realistic_session_with_learning():
    """Full realistic session that triggers learning."""
    # Simulate 5-minute typing session with learning events
    
    problem_words = ["vs", "api", "grit"]  # Words user will undo
    
    for word in problem_words:
        # Type in context, undo twice
        for _ in range(2):
            clear_field()
            type_phrase(f"some text {word} more text", char_delay=0.02)
            
            # Find and undo the problem word
            # (simplified - in real test would need to locate word)
            press_option()
            time.sleep(0.3)
    
    # Verify all problem words are now keepAsIs
    for word in problem_words:
        clear_field()
        type_word(f"{word} ", "us")
        result = get_result()
        assert word in result.lower(), f"'{word}' should be keepAsIs after learning"
```

### 21. Stress Test with Learning
```python
def test_stress_with_learning():
    """Sustained typing with learning events."""
    start = time.time()
    undo_count = 0
    
    while time.time() - start < 120:  # 2 minutes
        clear_field()
        
        # Type random phrase
        words = random.sample(["ghbdtn", "rfr", "ltkf", "vs", "api", "test"], 3)
        for word in words:
            type_word(word, "us", char_delay=random.uniform(0.01, 0.04))
            type_space()
        
        # 20% chance to undo last word
        if random.random() < 0.2:
            press_option()
            undo_count += 1
            time.sleep(0.2)
        
        time.sleep(0.1)
    
    print(f"Completed stress test with {undo_count} undos")
    
    # Verify no crashes, memory stable
    # Check that some learning occurred
```

## Implementation

### New Test File
Create `scripts/realistic_behavior_test.py` with:
- Helper functions for variable-speed typing
- Random delay generators
- Typo injection
- Navigation simulation

### Test Data
Create `tests/realistic_word_lists/`:
- `russian_common_1000.txt` — Common Russian words
- `english_common_1000.txt` — Common English words
- `mixed_phrases.txt` — Real chat/email snippets

### Metrics to Track
- Correction accuracy under realistic conditions
- Memory usage over time
- Latency distribution (p50, p95, p99)
- Crash count

## Definition of Done

### Core Realistic Behavior Tests (1-8)
- [ ] `test_variable_speed_typing` passes
- [ ] `test_typo_backspace_flow` passes
- [ ] `test_mid_word_pause` passes
- [ ] `test_random_alt_checks` passes
- [ ] `test_burst_then_correct` passes
- [ ] `test_sustained_typing_5min` completes without crash
- [ ] `test_app_switch_mid_sentence` passes
- [ ] `test_mixed_language_session` passes

### Ticket 28 (User Dictionary) Tests (9-13)
- [ ] `test_repeated_undo_triggers_keepasis` — 2 undos → keepAsIs rule
- [ ] `test_manual_correction_triggers_preference` — 1 manual → preferHypothesis
- [ ] `test_unlearning_via_override` — 2 overrides → rule removed
- [ ] `test_learning_persists_across_restart` — rules survive restart
- [ ] `test_learning_per_app_context` — per-app scope works

### Ticket 29 (Extended Cycling) Tests (14-18)
- [ ] `test_first_round_two_states` — round 1 has 2 states
- [ ] `test_second_round_three_states` — round 2 adds third language
- [ ] `test_typing_resets_cycling_round` — typing resets to round 1
- [ ] `test_third_language_validated` — invalid alternatives not shown
- [ ] `test_full_trilingual_cycle` — RU/EN/HE all accessible

### Integration Tests (19-21)
- [ ] `test_learning_affects_cycling` — learned prefs affect cycling
- [ ] `test_realistic_session_with_learning` — full session with learning
- [ ] `test_stress_with_learning` — 2-min stress test with learning

### Quality Gates
- [ ] Memory usage stable over 5-minute test (<150MB)
- [ ] No crashes during any test
- [ ] All learning rules persisted correctly
- [ ] Cycling state machine behaves correctly

## Files Affected

- New: `scripts/realistic_behavior_test.py`
- New: `tests/realistic_word_lists/`
- Update: `.sdd/backlog/current_task.md` — Document new tests

## Dependencies

- **Ticket 28** (User Dictionary) — Tests 9-13 require this to be implemented
- **Ticket 29** (Extended Cycling) — Tests 14-18 require this to be implemented

Tests 1-8 can run independently and should pass with current OMFK.
Tests 9-21 will initially fail until Tickets 28/29 are implemented.

## Blocked By

- None for tests 1-8
- Ticket 28 for tests 9-13
- Ticket 29 for tests 14-18

## Priority

Medium — Important for quality but not blocking features

## Execution Order

1. Implement tests 1-8 first (no dependencies)
2. Run tests 9-13 as Ticket 28 is implemented (expect failures → passes)
3. Run tests 14-18 as Ticket 29 is implemented (expect failures → passes)
4. Run tests 19-21 after both tickets complete (integration verification)
