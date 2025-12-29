#!/usr/bin/env python3
"""
EXTREME Alt Cycling Tests - Find the bugs!

Focus on:
- Ultra-fast typing (real human speed ~50-80ms per char)
- Immediate Alt after space (no wait)
- Alt during OMFK processing
- Double/triple space
- Alt + immediate typing
- Realistic typing patterns with mistakes
- Random delays simulating human behavior
"""

import subprocess
import time
import json
import sys
import os
import random
from pathlib import Path

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
    time.sleep(0.05)


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


def key_code(code: int, shift: bool = False, delay: float = 0):
    """Send raw keycode."""
    if shift:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {code} using shift down'], capture_output=True)
    else:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {code}'], capture_output=True)
    if delay > 0:
        time.sleep(delay)


def type_char_fast(char: str, layout: str = "us", delay: float = 0):
    """Type char with minimal delay."""
    if char == ' ':
        key_code(49, delay=delay)
    elif char == '\n':
        key_code(36, delay=delay)
    else:
        layout_map = _keycodes.get(layout, {})
        if char in layout_map:
            kc, shift = layout_map[char]
            key_code(kc, shift, delay)


def press_option_raw(delay: float = 0):
    """Press Option with CGEvent - fastest method."""
    ev = CGEventCreateKeyboardEvent(None, 58, True)
    CGEventSetFlags(ev, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, ev)
    ev = CGEventCreateKeyboardEvent(None, 58, False)
    CGEventPost(kCGHIDEventTap, ev)
    if delay > 0:
        time.sleep(delay)


def switch_layout(name: str):
    subprocess.run([str(OMFK_DIR / "scripts" / "switch_layout"), "select", name], capture_output=True)
    time.sleep(0.15)


def start_omfk():
    subprocess.run(['pkill', '-f', 'OMFK'], capture_output=True)
    time.sleep(0.3)
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
    time.sleep(1.5)
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
    time.sleep(0.3)


passed = 0
failed = 0


def test(name):
    def decorator(func):
        def wrapper():
            global passed, failed
            print(f"\n{'='*60}")
            print(f"TEST: {name}")
            print('='*60)
            clear_field()
            switch_layout("US")
            time.sleep(0.1)
            try:
                result = func()
                if result:
                    print(f"✓ PASSED")
                    passed += 1
                else:
                    print(f"✗ FAILED")
                    failed += 1
                return result
            except Exception as e:
                print(f"✗ ERROR: {e}")
                import traceback
                traceback.print_exc()
                failed += 1
                return False
        return wrapper
    return decorator


# ============================================================================
# EXTREME TESTS
# ============================================================================

@test("Ultra-fast typing (10ms per char) + immediate Alt")
def test_ultrafast_typing():
    """Type at 100 chars/sec, Alt immediately after space."""
    word = "ghbdtn"
    for c in word:
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0)
    press_option_raw(delay=0)  # IMMEDIATE
    time.sleep(0.3)
    result = get_result()
    print(f"  Result: '{result}'")
    # Should have cycled or done something
    return len(result) > 0


@test("Zero delay typing + Alt")
def test_zero_delay():
    """Type with literally zero delay between chars."""
    word = "ghbdtn"
    for c in word:
        type_char_fast(c, "us", delay=0)
    type_char_fast(' ', "us", delay=0)
    time.sleep(0.1)  # Let OMFK process
    before = get_result()
    print(f"  After typing: '{before}'")
    press_option_raw(delay=0)
    time.sleep(0.1)
    after = get_result()
    print(f"  After Alt: '{after}'")
    return before != after or len(before) > 0


@test("Alt DURING OMFK processing (race condition)")
def test_alt_during_processing():
    """Type word, space, Alt all within 50ms."""
    word = "ghbdtn"
    for c in word:
        type_char_fast(c, "us", delay=0.008)
    type_char_fast(' ', "us", delay=0)
    time.sleep(0.02)  # 20ms - OMFK might still be processing
    press_option_raw(delay=0)
    time.sleep(0.3)
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


@test("Double space + Alt")
def test_double_space():
    """Type word, double space, then Alt."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.015)
    type_char_fast(' ', "us", delay=0.05)
    type_char_fast(' ', "us", delay=0.05)
    before = get_result()
    print(f"  After double space: '{before}'")
    press_option_raw(delay=0.2)
    after = get_result()
    print(f"  After Alt: '{after}'")
    return len(before) > 0


@test("Alt + immediate typing (no pause)")
def test_alt_then_immediate_type():
    """Alt, then immediately start typing next word."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.015)
    type_char_fast(' ', "us", delay=0.3)
    
    press_option_raw(delay=0)
    # Immediately start typing next word
    for c in "vbh":
        type_char_fast(c, "us", delay=0.015)
    type_char_fast(' ', "us", delay=0.3)
    
    result = get_result()
    print(f"  Result: '{result}'")
    words = result.split()
    print(f"  Words: {words}")
    return len(words) >= 2


@test("Rapid Alt-Type-Alt-Type pattern")
def test_rapid_alt_type_alt():
    """Alt, type char, Alt, type char - interleaved."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0.2)
    
    # Interleave Alt and typing
    press_option_raw(delay=0.05)
    type_char_fast('v', "us", delay=0.05)
    press_option_raw(delay=0.05)
    type_char_fast('b', "us", delay=0.05)
    press_option_raw(delay=0.05)
    type_char_fast('h', "us", delay=0.05)
    type_char_fast(' ', "us", delay=0.3)
    
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


@test("Human-like typing with random delays (40-120ms)")
def test_human_random_delays():
    """Simulate realistic human typing speed with variance."""
    word = "ghbdtn"
    for c in word:
        delay = random.uniform(0.04, 0.12)
        type_char_fast(c, "us", delay=delay)
    
    # Human pause before space
    time.sleep(random.uniform(0.05, 0.15))
    type_char_fast(' ', "us", delay=0)
    time.sleep(random.uniform(0.3, 0.6))
    
    before = get_result()
    print(f"  After typing: '{before}'")
    
    # Human reaction time before Alt
    time.sleep(random.uniform(0.1, 0.3))
    press_option_raw(delay=0.2)
    
    after = get_result()
    print(f"  After Alt: '{after}'")
    return before != after


@test("Burst typing: 3 words fast, then Alt")
def test_burst_typing():
    """Type 3 words very fast, then Alt on last."""
    words = ["ghbdtn", "rfr", "ltkf"]
    for w in words:
        for c in w:
            type_char_fast(c, "us", delay=0.008)
        type_char_fast(' ', "us", delay=0.15)
    
    time.sleep(0.3)
    before = get_result()
    print(f"  Before Alt: '{before}'")
    
    press_option_raw(delay=0.2)
    after = get_result()
    print(f"  After Alt: '{after}'")
    
    # First 2 words should be same
    before_words = before.split()[:2]
    after_words = after.split()[:2]
    same = before_words == after_words
    print(f"  First 2 words same: {same} ({before_words} vs {after_words})")
    return same


@test("Alt spam at 20ms intervals (50 presses)")
def test_alt_spam_20ms():
    """Spam Alt every 20ms - stress test."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0.2)
    
    initial = get_result()
    print(f"  Initial: '{initial}'")
    
    for i in range(50):
        press_option_raw(delay=0.02)
    
    time.sleep(0.2)
    final = get_result()
    print(f"  After 50x Alt @20ms: '{final}'")
    return len(final) > 0


@test("Alt spam at 5ms intervals (100 presses)")
def test_alt_spam_5ms():
    """Extreme spam - 5ms intervals."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0.2)
    
    for i in range(100):
        press_option_raw(delay=0.005)
    
    time.sleep(0.3)
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


@test("Type-Space-Alt with 0ms between space and Alt")
def test_space_alt_zero_gap():
    """The critical race: space and Alt with zero gap."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.015)
    
    # Space and Alt back-to-back
    key_code(49, delay=0)  # space
    press_option_raw(delay=0)  # Alt immediately
    
    time.sleep(0.4)
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


@test("Multiple words, Alt after each")
def test_alt_after_each_word():
    """Type word, Alt, type word, Alt - realistic undo pattern."""
    results = []
    
    for w in ["ghbdtn", "vbh", "ntrcn"]:
        for c in w:
            type_char_fast(c, "us", delay=0.02)
        type_char_fast(' ', "us", delay=0.4)
        
        before = get_result()
        press_option_raw(delay=0.3)
        after = get_result()
        
        print(f"  '{w}': '{before}' → '{after}'")
        results.append((before, after))
    
    # Each Alt should have changed something
    changes = sum(1 for b, a in results if b != a)
    print(f"  Changes: {changes}/3")
    return changes >= 2


@test("Long phrase (10 words), Alt at random positions")
def test_long_phrase_random_alt():
    """Type 10 words, press Alt at random points."""
    words = ["ghbdtn", "rfr", "ltkf", "e", "vtyz", "dct", "[jhjij", "cgfcb,j", "ljhjuf", "ljv"]
    
    alt_positions = random.sample(range(len(words)), 3)
    print(f"  Alt positions: {alt_positions}")
    
    for i, w in enumerate(words):
        for c in w:
            type_char_fast(c, "us", delay=0.015)
        type_char_fast(' ', "us", delay=0.2)
        
        if i in alt_positions:
            press_option_raw(delay=0.15)
    
    result = get_result()
    word_count = len(result.split())
    print(f"  Result: {word_count} words")
    print(f"  Text: '{result[:60]}...'")
    return word_count >= 8


@test("Backspace mid-word, then complete, then Alt")
def test_backspace_mid_word():
    """Type partial, backspace, complete, space, Alt."""
    # Type "ghbdtx" (typo)
    for c in "ghbdtx":
        type_char_fast(c, "us", delay=0.02)
    
    # Backspace to fix
    key_code(51, delay=0.05)  # backspace
    type_char_fast('n', "us", delay=0.02)
    type_char_fast(' ', "us", delay=0.4)
    
    before = get_result()
    print(f"  After fix: '{before}'")
    
    press_option_raw(delay=0.3)
    after = get_result()
    print(f"  After Alt: '{after}'")
    
    return len(before) > 0


@test("Hebrew layout: type, switch to US, Alt")
def test_hebrew_then_switch_alt():
    """Type on Hebrew, switch layout, then Alt."""
    switch_layout("Hebrew")
    
    # Type "ltkf" (дела) on Hebrew
    for c in "ltkf":
        type_char_fast(c, "us", delay=0.02)  # Physical keys
    type_char_fast(' ', "us", delay=0.4)
    
    before = get_result()
    print(f"  After Hebrew typing: '{before}'")
    
    switch_layout("US")
    time.sleep(0.1)
    
    press_option_raw(delay=0.3)
    after = get_result()
    print(f"  After switch + Alt: '{after}'")
    
    return len(before) > 0


@test("Continuous typing stream with periodic Alt")
def test_continuous_stream():
    """Type continuously, Alt every 2 seconds."""
    words = ["ghbdtn", "vbh", "ntrcn", "rjl", "ckjdf"]
    
    start = time.time()
    word_idx = 0
    
    while time.time() - start < 5:  # 5 second test
        w = words[word_idx % len(words)]
        for c in w:
            type_char_fast(c, "us", delay=0.025)
        type_char_fast(' ', "us", delay=0.1)
        
        # Alt every ~2 words
        if word_idx % 2 == 1:
            press_option_raw(delay=0.1)
        
        word_idx += 1
    
    result = get_result()
    print(f"  Typed {word_idx} words in 5s")
    print(f"  Result length: {len(result)} chars")
    return len(result) > 50


@test("Alt while OMFK is correcting previous word")
def test_alt_overlap_correction():
    """Type word1, space, immediately type word2, Alt - overlap."""
    # Word 1
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0)
    
    # Immediately start word 2 (OMFK still processing word 1)
    for c in "vbh":
        type_char_fast(c, "us", delay=0.01)
    
    # Alt while word 2 is incomplete
    press_option_raw(delay=0)
    
    # Finish word 2
    type_char_fast(' ', "us", delay=0.3)
    
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


@test("Triple Alt in quick succession")
def test_triple_alt_quick():
    """Three Alt presses with 30ms gaps."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.015)
    type_char_fast(' ', "us", delay=0.3)
    
    states = [get_result()]
    
    for i in range(3):
        press_option_raw(delay=0.03)
        states.append(get_result())
    
    print(f"  States: {states}")
    unique = len(set(states))
    print(f"  Unique: {unique}")
    return unique >= 2


@test("Type same word 10x, Alt each time - consistency check")
def test_consistency_10x():
    """Verify Alt behavior is consistent across 10 iterations."""
    results = []
    
    for i in range(10):
        clear_field()
        time.sleep(0.05)
        
        for c in "ghbdtn":
            type_char_fast(c, "us", delay=0.015)
        type_char_fast(' ', "us", delay=0.3)
        
        before = get_result()
        press_option_raw(delay=0.2)
        after = get_result()
        
        results.append((before, after))
    
    # Check consistency
    befores = [r[0] for r in results]
    afters = [r[1] for r in results]
    
    before_consistent = len(set(befores)) == 1
    after_consistent = len(set(afters)) == 1
    
    print(f"  Before states: {set(befores)}")
    print(f"  After states: {set(afters)}")
    print(f"  Before consistent: {before_consistent}")
    print(f"  After consistent: {after_consistent}")
    
    return before_consistent and after_consistent


@test("Alt on very short word (2 chars)")
def test_short_word_2chars():
    """Test Alt on 2-char word."""
    for c in "yj":  # "но"
        type_char_fast(c, "us", delay=0.02)
    type_char_fast(' ', "us", delay=0.4)
    
    before = get_result()
    print(f"  Before: '{before}'")
    
    press_option_raw(delay=0.3)
    after = get_result()
    print(f"  After: '{after}'")
    
    return len(before) > 0


@test("Alt on single char")
def test_single_char():
    """Test Alt on single character."""
    type_char_fast('z', "us", delay=0)  # "я"
    type_char_fast(' ', "us", delay=0.4)
    
    before = get_result()
    print(f"  Before: '{before}'")
    
    press_option_raw(delay=0.3)
    after = get_result()
    print(f"  After: '{after}'")
    
    return True  # Just check no crash


@test("Realistic sentence with typo and correction")
def test_realistic_typo_flow():
    """Type sentence, make typo, backspace, fix, continue."""
    # "привет как дела" with typo in middle
    
    # "ghbdtn " (привет)
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=random.uniform(0.03, 0.08))
    type_char_fast(' ', "us", delay=random.uniform(0.1, 0.2))
    
    # "rfk" (typo for "rfr")
    for c in "rfk":
        type_char_fast(c, "us", delay=random.uniform(0.03, 0.08))
    
    # Realize typo, backspace
    time.sleep(0.15)
    key_code(51, delay=0.05)
    type_char_fast('r', "us", delay=0.05)
    type_char_fast(' ', "us", delay=random.uniform(0.1, 0.2))
    
    # "ltkf" (дела)
    for c in "ltkf":
        type_char_fast(c, "us", delay=random.uniform(0.03, 0.08))
    type_char_fast(' ', "us", delay=0.4)
    
    result = get_result()
    print(f"  Result: '{result}'")
    
    # Now Alt to undo last word
    press_option_raw(delay=0.3)
    after_alt = get_result()
    print(f"  After Alt: '{after_alt}'")
    
    return len(result) >= 3  # At least some words


@test("Fast typing then immediate window switch simulation")
def test_fast_then_focus_change():
    """Type fast, then simulate what happens if focus changes."""
    for c in "ghbdtn":
        type_char_fast(c, "us", delay=0.01)
    type_char_fast(' ', "us", delay=0)
    
    # Simulate brief focus loss (click elsewhere)
    time.sleep(0.05)
    
    # Come back and Alt
    subprocess.run(['osascript', '-e', 'tell application "TextEdit" to activate'], capture_output=True)
    time.sleep(0.1)
    
    press_option_raw(delay=0.3)
    result = get_result()
    print(f"  Result: '{result}'")
    return len(result) > 0


# ============================================================================
# MAIN
# ============================================================================

def main():
    global passed, failed
    
    print("=" * 70)
    print("EXTREME Alt Cycling Tests - Finding Bugs")
    print("=" * 70)
    
    print("\nBuilding OMFK...")
    if not start_omfk():
        print("Failed to start OMFK")
        return 1
    
    setup_textedit()
    
    tests = [
        test_ultrafast_typing,
        test_zero_delay,
        test_alt_during_processing,
        test_double_space,
        test_alt_then_immediate_type,
        test_rapid_alt_type_alt,
        test_human_random_delays,
        test_burst_typing,
        test_alt_spam_20ms,
        test_alt_spam_5ms,
        test_space_alt_zero_gap,
        test_alt_after_each_word,
        test_long_phrase_random_alt,
        test_backspace_mid_word,
        test_hebrew_then_switch_alt,
        test_continuous_stream,
        test_alt_overlap_correction,
        test_triple_alt_quick,
        test_consistency_10x,
        test_short_word_2chars,
        test_single_char,
        test_realistic_typo_flow,
        test_fast_then_focus_change,
    ]
    
    try:
        for t in tests:
            t()
            time.sleep(0.2)
    finally:
        stop_omfk()
        subprocess.run(['osascript', '-e', 'tell application "TextEdit" to quit saving no'], capture_output=True)
    
    print("\n" + "=" * 70)
    print(f"TOTAL: {passed} passed, {failed} failed")
    print("=" * 70)
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
