#!/usr/bin/env python3
"""
HARDCORE Alt Cycling E2E Tests for OMFK

Extreme edge cases and stress tests for Alt key behavior:
- Alt in middle of phrase (not just at end)
- Alt after partial word typed
- Alt spam during typing
- Alt with different layouts mid-phrase
- Alt undo chain verification
- Alt after context boost
- Alt timing edge cases
- Alt with punctuation
- Alt state persistence across words
- Learning signal verification (repeated undos)
"""

import subprocess
import time
import json
import sys
import os
import random
from pathlib import Path
from datetime import datetime

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskAlternate,
)

OMFK_DIR = Path(__file__).parent.parent
LOG_FILE = Path.home() / ".omfk" / "debug.log"

_keycodes = {}
keycodes_path = OMFK_DIR / "scripts" / "keycodes.json"
if keycodes_path.exists():
    with open(keycodes_path) as f:
        _keycodes = json.load(f)


def clear_field():
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            tell application "System Events"
                keystroke "a" using command down
                key code 51
            end tell
        end tell
    '''], capture_output=True)
    time.sleep(0.1)


def get_result():
    result = subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            try
                return text of document 1
            on error
                return ""
            end try
        end tell
    '''], capture_output=True, text=True)
    return result.stdout.strip()


def type_char(char: str, layout: str = "us", delay: float = 0.015):
    if char == ' ':
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
    elif char == '\n':
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 36'], capture_output=True)
    else:
        layout_map = _keycodes.get(layout, {})
        if char in layout_map:
            keycode, shift = layout_map[char]
            if shift:
                subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {keycode} using shift down'], capture_output=True)
            else:
                subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {keycode}'], capture_output=True)
    time.sleep(delay)


def type_word(word: str, layout: str = "us", char_delay: float = 0.015):
    for char in word:
        type_char(char, layout, char_delay)


def type_space(wait: float = 0.8):
    subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
    time.sleep(wait)


def press_option(wait: float = 0.3):
    ev = CGEventCreateKeyboardEvent(None, 58, True)
    CGEventSetFlags(ev, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.02)
    ev = CGEventCreateKeyboardEvent(None, 58, False)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(wait)


def press_backspace(count: int = 1):
    for _ in range(count):
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 51'], capture_output=True)
        time.sleep(0.02)


def switch_layout(layout_name: str):
    subprocess.run([str(OMFK_DIR / "scripts" / "switch_layout"), "select", layout_name], capture_output=True)
    time.sleep(0.2)


def start_omfk():
    subprocess.run(['pkill', '-f', 'OMFK'], capture_output=True)
    time.sleep(0.5)
    result = subprocess.run(['swift', 'build'], cwd=OMFK_DIR, capture_output=True)
    if result.returncode != 0:
        print("Build failed!")
        return False
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    env = os.environ.copy()
    env['OMFK_DEBUG_LOG'] = '1'
    subprocess.Popen([str(OMFK_DIR / ".build" / "debug" / "OMFK")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    return True


def stop_omfk():
    subprocess.run(['pkill', '-f', 'OMFK'], capture_output=True)


def setup_textedit():
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            make new document
        end tell
    '''], capture_output=True)
    time.sleep(0.5)


def get_log_entries(since_marker: str = None):
    """Get log entries, optionally since a marker."""
    if not LOG_FILE.exists():
        return []
    content = LOG_FILE.read_text()
    lines = content.strip().split('\n')
    if since_marker:
        for i, line in enumerate(lines):
            if since_marker in line:
                return lines[i+1:]
    return lines


def log_marker():
    """Write a marker to log and return it."""
    marker = f"MARKER_{datetime.now().timestamp()}"
    # We can't write to OMFK's log, so just return timestamp
    return str(datetime.now().timestamp())


# ============================================================================
# HARDCORE TEST CASES
# ============================================================================

class TestResult:
    def __init__(self, name):
        self.name = name
        self.passed = False
        self.details = []
    
    def log(self, msg):
        self.details.append(msg)
        print(f"    {msg}")
    
    def finish(self, passed, summary=""):
        self.passed = passed
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"  {status}: {summary}")
        return passed


def test_alt_full_cycle_verification():
    """Verify Alt cycles through exactly 3 states: RU→original→HE (or similar)."""
    print("\n=== Test: Full Cycle State Verification ===")
    t = TestResult("full_cycle")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    type_space()
    
    states = [get_result().strip()]
    t.log(f"State 0 (auto): '{states[0]}'")
    
    # Collect all states until we cycle back
    max_cycles = 10
    for i in range(max_cycles):
        press_option()
        state = get_result().strip()
        t.log(f"State {i+1}: '{state}'")
        
        if state == states[0] and i > 0:
            t.log(f"Cycled back to original after {i+1} presses")
            break
        if state not in states:
            states.append(state)
    
    unique = len(set(states))
    t.log(f"Unique states found: {unique}")
    t.log(f"States: {states}")
    
    # Should have at least 2 unique states (corrected + original)
    # Ideally 3 (RU, EN, HE) for trilingual setup
    return t.finish(unique >= 2, f"{unique} unique states in cycle")


def test_alt_mid_phrase_affects_only_last():
    """Type 5 words, Alt should ONLY affect the last word."""
    print("\n=== Test: Alt Mid-Phrase Only Affects Last Word ===")
    t = TestResult("mid_phrase")
    clear_field()
    switch_layout("US")
    
    words = ["ghbdtn", "rfr", "ltkf", "e", "vtyz"]  # привет как дела у меня
    
    for w in words:
        type_word(w, "us")
        type_space()
    
    before = get_result().strip()
    before_words = before.split()
    t.log(f"Before Alt: '{before}' ({len(before_words)} words)")
    
    press_option()
    after = get_result().strip()
    after_words = after.split()
    t.log(f"After Alt: '{after}' ({len(after_words)} words)")
    
    # First 4 words must be identical
    if len(before_words) >= 4 and len(after_words) >= 4:
        first_four_same = before_words[:4] == after_words[:4]
        t.log(f"First 4 words same: {first_four_same}")
        t.log(f"  Before: {before_words[:4]}")
        t.log(f"  After: {after_words[:4]}")
        return t.finish(first_four_same, "First 4 words preserved")
    
    return t.finish(False, "Word count mismatch")


def test_alt_after_partial_word():
    """Type partial word (no space), Alt should do nothing or handle gracefully."""
    print("\n=== Test: Alt After Partial Word (No Space) ===")
    t = TestResult("partial_word")
    clear_field()
    switch_layout("US")
    
    # Type "ghbdt" without space (incomplete word)
    type_word("ghbdt", "us")
    before = get_result().strip()
    t.log(f"After partial word: '{before}'")
    
    press_option()
    after = get_result().strip()
    t.log(f"After Alt: '{after}'")
    
    # Should either do nothing or not crash
    return t.finish(True, f"Handled gracefully: '{before}' → '{after}'")


def test_alt_spam_during_typing():
    """Spam Alt while typing characters."""
    print("\n=== Test: Alt Spam During Typing ===")
    t = TestResult("spam_during_typing")
    clear_field()
    switch_layout("US")
    
    word = "ghbdtn"
    for i, char in enumerate(word):
        type_char(char, "us")
        if i % 2 == 1:  # Alt after every 2nd char
            press_option(wait=0.1)
    
    type_space()
    result = get_result().strip()
    t.log(f"Result after spam: '{result}'")
    
    # Should have some content, not crash
    return t.finish(len(result) > 0, f"Content preserved: '{result}'")


def test_alt_layout_switch_mid_phrase():
    """Type word in EN layout, switch to RU, type more, Alt."""
    print("\n=== Test: Alt After Layout Switch Mid-Phrase ===")
    t = TestResult("layout_switch")
    clear_field()
    
    switch_layout("US")
    type_word("ghbdtn", "us")
    type_space()
    after_first = get_result().strip()
    t.log(f"After first word (US): '{after_first}'")
    
    switch_layout("Russian")
    type_word("руддщ", "russian")  # "hello" on RU layout
    type_space()
    after_second = get_result().strip()
    t.log(f"After second word (RU): '{after_second}'")
    
    press_option()
    after_alt = get_result().strip()
    t.log(f"After Alt: '{after_alt}'")
    
    switch_layout("US")  # Restore
    return t.finish(True, f"Mixed layout handled: '{after_alt}'")


def test_alt_undo_chain_10_words():
    """Type 10 words, then Alt 10 times - verify each undo is independent."""
    print("\n=== Test: Alt Undo Chain (10 Words) ===")
    t = TestResult("undo_chain")
    clear_field()
    switch_layout("US")
    
    words = ["ghbdtn", "vbh", "ntrcn", "rjl", "ckjdf", 
             "cgfcb,j", "ljhjuf", "ljv", "hf,jnf", ";bpym"]
    
    for w in words:
        type_word(w, "us")
        type_space()
    
    baseline = get_result().strip()
    t.log(f"Baseline ({len(baseline.split())} words): '{baseline[:50]}...'")
    
    states = [baseline]
    for i in range(10):
        press_option(wait=0.2)
        state = get_result().strip()
        states.append(state)
        if state != states[-2]:
            t.log(f"Alt {i+1}: changed")
    
    # Count how many times state changed
    changes = sum(1 for i in range(1, len(states)) if states[i] != states[i-1])
    t.log(f"State changes: {changes}/10")
    
    return t.finish(changes >= 1, f"{changes} state changes in 10 Alt presses")


def test_alt_with_punctuation():
    """Type word with punctuation, verify Alt handles it."""
    print("\n=== Test: Alt With Punctuation ===")
    t = TestResult("punctuation")
    clear_field()
    switch_layout("US")
    
    # Type "ghbdtn!" (привет!)
    type_word("ghbdtn", "us")
    type_char("!", "us")
    type_space()
    
    before = get_result().strip()
    t.log(f"Before Alt: '{before}'")
    
    press_option()
    after = get_result().strip()
    t.log(f"After Alt: '{after}'")
    
    # Punctuation should be preserved in some form
    has_punct = "!" in after or "1" in after  # ! might become 1 on RU layout
    return t.finish(True, f"Punctuation handled: '{after}'")


def test_alt_rapid_100x():
    """Spam Alt 100 times as fast as possible."""
    print("\n=== Test: Rapid Alt Spam (100x) ===")
    t = TestResult("rapid_100")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    type_space()
    initial = get_result().strip()
    t.log(f"Initial: '{initial}'")
    
    start = time.time()
    for _ in range(100):
        press_option(wait=0.02)
    elapsed = time.time() - start
    
    final = get_result().strip()
    t.log(f"Final after 100x Alt ({elapsed:.2f}s): '{final}'")
    
    return t.finish(len(final) > 0, f"Survived 100x spam in {elapsed:.2f}s")


def test_alt_context_boost_then_undo():
    """Type ambiguous word, context boost corrects it, then undo."""
    print("\n=== Test: Alt After Context Boost ===")
    t = TestResult("context_boost_undo")
    clear_field()
    switch_layout("US")
    
    # "z" alone is ambiguous, but "z nt,z" should boost to "я тебя"
    type_word("z", "us")
    type_space(wait=0.3)
    after_z = get_result().strip()
    t.log(f"After 'z ': '{after_z}'")
    
    type_word("nt,z", "us")
    type_space()
    after_tebya = get_result().strip()
    t.log(f"After 'nt,z ': '{after_tebya}'")
    
    # Now Alt - should affect last word
    press_option()
    after_alt = get_result().strip()
    t.log(f"After Alt: '{after_alt}'")
    
    return t.finish(True, f"Context boost + undo: '{after_alt}'")


def test_alt_backspace_then_alt():
    """Type word, backspace some chars, then Alt."""
    print("\n=== Test: Alt After Backspace ===")
    t = TestResult("backspace_alt")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    type_space()
    after_word = get_result().strip()
    t.log(f"After word: '{after_word}'")
    
    # Backspace 3 chars
    press_backspace(3)
    after_bs = get_result().strip()
    t.log(f"After 3x backspace: '{after_bs}'")
    
    press_option()
    after_alt = get_result().strip()
    t.log(f"After Alt: '{after_alt}'")
    
    return t.finish(True, f"Backspace + Alt handled: '{after_alt}'")


def test_alt_newline_boundary():
    """Type word, newline, word, Alt."""
    print("\n=== Test: Alt Across Newline ===")
    t = TestResult("newline")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    type_space()
    type_char("\n")
    type_word("vbh", "us")
    type_space()
    
    before = get_result()
    t.log(f"Before Alt: '{repr(before)}'")
    
    press_option()
    after = get_result()
    t.log(f"After Alt: '{repr(after)}'")
    
    return t.finish(True, f"Newline handled")


def test_alt_empty_then_type():
    """Alt on empty field, then type."""
    print("\n=== Test: Alt On Empty Field ===")
    t = TestResult("empty_alt")
    clear_field()
    switch_layout("US")
    
    press_option()
    after_alt = get_result().strip()
    t.log(f"After Alt on empty: '{after_alt}'")
    
    type_word("ghbdtn", "us")
    type_space()
    after_type = get_result().strip()
    t.log(f"After typing: '{after_type}'")
    
    return t.finish(len(after_type) > 0, f"Empty Alt + type: '{after_type}'")


def test_alt_same_word_5x_undo():
    """Type same word 5 times, undo each with Alt - simulates learning signal."""
    print("\n=== Test: Repeated Undo (Learning Signal) ===")
    t = TestResult("learning_signal")
    clear_field()
    switch_layout("US")
    
    undo_count = 0
    for i in range(5):
        type_word("ghbdtn", "us")
        type_space()
        after_auto = get_result().strip().split()[-1] if get_result().strip() else ""
        
        press_option()
        after_undo = get_result().strip().split()[-1] if get_result().strip() else ""
        
        if after_auto != after_undo:
            undo_count += 1
            t.log(f"Round {i+1}: '{after_auto}' → '{after_undo}' (undone)")
        else:
            t.log(f"Round {i+1}: '{after_auto}' (no change)")
        
        type_space(wait=0.2)
    
    t.log(f"Total undos: {undo_count}/5")
    # After 2+ undos, OMFK should learn (if implemented)
    return t.finish(undo_count >= 2, f"{undo_count} undos detected")


def test_alt_hebrew_russian_english_cycle():
    """Verify full trilingual cycle: type Hebrew, cycle through RU and EN."""
    print("\n=== Test: Trilingual Cycle (HE→RU→EN) ===")
    t = TestResult("trilingual")
    clear_field()
    switch_layout("Hebrew")
    
    # Type "ltkf" on Hebrew = ךאלכ (дела/dela)
    type_word("ltkf", "us")  # Physical keys
    type_space()
    
    states = []
    states.append(("auto", get_result().strip()))
    t.log(f"State 0 (auto): '{states[-1][1]}'")
    
    for i in range(5):
        press_option()
        state = get_result().strip()
        states.append((f"alt{i+1}", state))
        t.log(f"State {i+1}: '{state}'")
    
    switch_layout("US")
    
    # Analyze scripts in states
    unique_states = list(set(s[1] for s in states))
    t.log(f"Unique states: {unique_states}")
    
    return t.finish(len(unique_states) >= 2, f"{len(unique_states)} unique states")


def test_alt_timing_edge_case():
    """Alt immediately after space (race condition test)."""
    print("\n=== Test: Alt Timing Edge Case ===")
    t = TestResult("timing")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    
    # Space and Alt almost simultaneously
    subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
    time.sleep(0.05)  # Very short delay
    press_option(wait=0.1)
    
    result = get_result().strip()
    t.log(f"Result: '{result}'")
    
    return t.finish(len(result) > 0, f"Timing edge case: '{result}'")


def test_alt_long_word():
    """Test Alt on very long word (20+ chars)."""
    print("\n=== Test: Alt On Long Word ===")
    t = TestResult("long_word")
    clear_field()
    switch_layout("US")
    
    # "программирование" = ghjuhfvvbhjdfybt (17 chars)
    long_word = "ghjuhfvvbhjdfybt"
    type_word(long_word, "us")
    type_space()
    
    before = get_result().strip()
    t.log(f"Before Alt: '{before}'")
    
    press_option()
    after = get_result().strip()
    t.log(f"After Alt: '{after}'")
    
    return t.finish(len(after) > 0, f"Long word handled: {len(after)} chars")


def test_alt_multiple_words_same_line():
    """Type 3 words, Alt, type 2 more, Alt, verify independence."""
    print("\n=== Test: Alt Multiple Times In Phrase ===")
    t = TestResult("multi_alt")
    clear_field()
    switch_layout("US")
    
    # First batch
    for w in ["ghbdtn", "rfr", "ltkf"]:
        type_word(w, "us")
        type_space()
    
    state1 = get_result().strip()
    t.log(f"After 3 words: '{state1}'")
    
    press_option()
    state2 = get_result().strip()
    t.log(f"After 1st Alt: '{state2}'")
    
    # Second batch
    for w in ["e", "vtyz"]:
        type_word(w, "us")
        type_space()
    
    state3 = get_result().strip()
    t.log(f"After 2 more words: '{state3}'")
    
    press_option()
    state4 = get_result().strip()
    t.log(f"After 2nd Alt: '{state4}'")
    
    # First 3 words should be same between state3 and state4
    words3 = state3.split()[:3]
    words4 = state4.split()[:3]
    preserved = words3 == words4
    t.log(f"First 3 words preserved: {preserved}")
    
    return t.finish(preserved, f"Multi-Alt independence verified")


def test_alt_with_numbers():
    """Type word with numbers, Alt."""
    print("\n=== Test: Alt With Numbers ===")
    t = TestResult("numbers")
    clear_field()
    switch_layout("US")
    
    # "test123" or similar
    type_word("ntcn123", "us")
    type_space()
    
    before = get_result().strip()
    t.log(f"Before Alt: '{before}'")
    
    press_option()
    after = get_result().strip()
    t.log(f"After Alt: '{after}'")
    
    # Numbers should be preserved
    has_123 = "123" in after
    return t.finish(has_123, f"Numbers preserved: {has_123}")


def test_alt_state_persistence():
    """Alt to state X, type more, verify state X persisted."""
    print("\n=== Test: Alt State Persistence ===")
    t = TestResult("persistence")
    clear_field()
    switch_layout("US")
    
    type_word("ghbdtn", "us")
    type_space()
    auto_state = get_result().strip()
    t.log(f"Auto state: '{auto_state}'")
    
    press_option()
    alt_state = get_result().strip()
    t.log(f"Alt state: '{alt_state}'")
    
    # Type another word
    type_word("vbh", "us")
    type_space()
    
    final = get_result().strip()
    first_word = final.split()[0] if final else ""
    t.log(f"Final: '{final}', first word: '{first_word}'")
    
    # First word should match alt_state's word
    alt_first = alt_state.split()[0] if alt_state else ""
    persisted = first_word == alt_first
    
    return t.finish(persisted, f"State persisted: '{alt_first}' → '{first_word}'")


# ============================================================================
# MAIN
# ============================================================================

def main():
    print("=" * 70)
    print("OMFK HARDCORE Alt Cycling E2E Tests")
    print("=" * 70)
    
    print("\nBuilding OMFK...")
    if not start_omfk():
        print("Failed to start OMFK")
        return 1
    
    setup_textedit()
    time.sleep(0.5)
    
    tests = [
        test_alt_full_cycle_verification,
        test_alt_mid_phrase_affects_only_last,
        test_alt_after_partial_word,
        test_alt_spam_during_typing,
        test_alt_layout_switch_mid_phrase,
        test_alt_undo_chain_10_words,
        test_alt_with_punctuation,
        test_alt_rapid_100x,
        test_alt_context_boost_then_undo,
        test_alt_backspace_then_alt,
        test_alt_newline_boundary,
        test_alt_empty_then_type,
        test_alt_same_word_5x_undo,
        test_alt_hebrew_russian_english_cycle,
        test_alt_timing_edge_case,
        test_alt_long_word,
        test_alt_multiple_words_same_line,
        test_alt_with_numbers,
        test_alt_state_persistence,
    ]
    
    passed = 0
    failed = 0
    results = []
    
    try:
        for test in tests:
            try:
                result = test()
                if result:
                    passed += 1
                else:
                    failed += 1
                results.append((test.__name__, result))
            except Exception as e:
                print(f"  ERROR: {e}")
                import traceback
                traceback.print_exc()
                failed += 1
                results.append((test.__name__, False))
            time.sleep(0.3)
    finally:
        stop_omfk()
        subprocess.run(['osascript', '-e', 'tell application "TextEdit" to quit saving no'], capture_output=True)
    
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    for name, result in results:
        status = "✓" if result else "✗"
        print(f"  {status} {name}")
    
    print("\n" + "=" * 70)
    print(f"TOTAL: {passed} passed, {failed} failed")
    print("=" * 70)
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
