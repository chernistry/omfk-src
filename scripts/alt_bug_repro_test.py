#!/usr/bin/env python3
"""
Bug-focused tests based on anomalies found in extreme tests.

BUGS FOUND:
1. Double space + Alt leaves partial char: 'привет' → 'пghbdtn'
2. Alt + immediate typing produces garbage: 'пghbdtn בה'
3. Backspace mid-word + Alt produces wrong result: 'ghbdtxn'
4. Alt overlap with next word: 'привет мvbh'
5. Continuous stream fails
"""

import subprocess
import time
import json
import sys
import os
from pathlib import Path

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskAlternate,
)

OMFK_DIR = Path(__file__).parent.parent
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
    if shift:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {code} using shift down'], capture_output=True)
    else:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {code}'], capture_output=True)
    if delay > 0:
        time.sleep(delay)


def type_char(char: str, layout: str = "us", delay: float = 0):
    if char == ' ':
        key_code(49, delay=delay)
    elif char == '\n':
        key_code(36, delay=delay)
    else:
        layout_map = _keycodes.get(layout, {})
        if char in layout_map:
            kc, shift = layout_map[char]
            key_code(kc, shift, delay)


def press_option(delay: float = 0):
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
    subprocess.run(['swift', 'build'], cwd=OMFK_DIR, capture_output=True)
    env = os.environ.copy()
    env['OMFK_DEBUG_LOG'] = '1'
    subprocess.Popen([str(OMFK_DIR / ".build" / "debug" / "OMFK")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)


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


# ============================================================================
# BUG REPRODUCTION TESTS
# ============================================================================

def test_bug_double_space_partial_char():
    """
    BUG: Double space + Alt leaves partial character.
    Expected: 'привет' → 'ghbdtn' (full undo)
    Actual: 'привет' → 'пghbdtn' (first char remains!)
    """
    print("\n" + "="*60)
    print("BUG TEST: Double space leaves partial char")
    print("="*60)
    
    results = []
    for delay_between_spaces in [0.01, 0.02, 0.05, 0.1, 0.2]:
        clear_field()
        switch_layout("US")
        
        for c in "ghbdtn":
            type_char(c, "us", delay=0.015)
        type_char(' ', "us", delay=delay_between_spaces)
        type_char(' ', "us", delay=0.3)
        
        before = get_result()
        press_option(delay=0.3)
        after = get_result()
        
        # Check if first char of 'привет' leaked
        has_cyrillic = any('\u0400' <= c <= '\u04FF' for c in after)
        
        print(f"  Delay {delay_between_spaces*1000:.0f}ms: '{before}' → '{after}' (cyrillic leaked: {has_cyrillic})")
        results.append((delay_between_spaces, has_cyrillic, before, after))
    
    bugs = [r for r in results if r[1]]
    print(f"\n  BUGS FOUND: {len(bugs)}/{len(results)}")
    return len(bugs) == 0


def test_bug_alt_immediate_typing_garbage():
    """
    BUG: Alt + immediate typing produces garbage.
    Expected: Clean word separation
    Actual: 'пghbdtn בה' - mixed scripts garbage
    """
    print("\n" + "="*60)
    print("BUG TEST: Alt + immediate typing produces garbage")
    print("="*60)
    
    results = []
    for delay_after_alt in [0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.3]:
        clear_field()
        switch_layout("US")
        
        for c in "ghbdtn":
            type_char(c, "us", delay=0.015)
        type_char(' ', "us", delay=0.3)
        
        press_option(delay=delay_after_alt)
        
        # Immediately type next word
        for c in "vbh":
            type_char(c, "us", delay=0.015)
        type_char(' ', "us", delay=0.3)
        
        result = get_result()
        words = result.split()
        
        # Check for garbage (mixed scripts in single word, or Hebrew chars)
        has_garbage = any('\u0590' <= c <= '\u05FF' for c in result)  # Hebrew
        has_mixed = any(
            any('\u0400' <= c <= '\u04FF' for c in w) and any('a' <= c <= 'z' for c in w)
            for w in words
        )
        
        print(f"  Delay {delay_after_alt*1000:.0f}ms: '{result}' (garbage: {has_garbage or has_mixed})")
        results.append((delay_after_alt, has_garbage or has_mixed, result))
    
    bugs = [r for r in results if r[1]]
    print(f"\n  BUGS FOUND: {len(bugs)}/{len(results)}")
    
    # Find minimum safe delay
    safe_delays = [r[0] for r in results if not r[1]]
    if safe_delays:
        print(f"  MINIMUM SAFE DELAY: {min(safe_delays)*1000:.0f}ms")
    
    return len(bugs) == 0


def test_bug_backspace_alt_wrong_result():
    """
    BUG: Backspace mid-word + complete + Alt produces wrong result.
    Expected: 'ghbdtn' (original typed)
    Actual: 'ghbdtxn' (includes the deleted char!)
    """
    print("\n" + "="*60)
    print("BUG TEST: Backspace + Alt produces wrong result")
    print("="*60)
    
    clear_field()
    switch_layout("US")
    
    # Type "ghbdtx" (typo - x instead of n)
    for c in "ghbdtx":
        type_char(c, "us", delay=0.02)
    
    time.sleep(0.1)
    
    # Backspace to delete 'x'
    key_code(51, delay=0.1)
    
    # Type correct 'n'
    type_char('n', "us", delay=0.02)
    type_char(' ', "us", delay=0.5)
    
    before = get_result()
    print(f"  After typing with fix: '{before}'")
    
    press_option(delay=0.3)
    after = get_result()
    print(f"  After Alt: '{after}'")
    
    # Bug: 'x' appears in result even though it was deleted
    has_x = 'x' in after
    print(f"  Contains deleted 'x': {has_x}")
    
    if has_x:
        print("  BUG CONFIRMED: Deleted character appears in Alt result!")
        return False
    return True


def test_bug_alt_overlap_partial():
    """
    BUG: Alt while typing next word causes partial correction.
    Expected: Clean words
    Actual: 'привет мvbh' - second word partially converted
    """
    print("\n" + "="*60)
    print("BUG TEST: Alt overlap causes partial correction")
    print("="*60)
    
    results = []
    for overlap_chars in [1, 2, 3]:
        clear_field()
        switch_layout("US")
        
        # Type first word
        for c in "ghbdtn":
            type_char(c, "us", delay=0.01)
        type_char(' ', "us", delay=0)
        
        # Start typing second word
        second_word = "vbh"
        for i, c in enumerate(second_word):
            type_char(c, "us", delay=0.01)
            if i == overlap_chars - 1:
                # Alt in the middle of second word
                press_option(delay=0)
        
        type_char(' ', "us", delay=0.3)
        
        result = get_result()
        words = result.split()
        
        # Check for partial conversion (mixed scripts in one word)
        has_partial = any(
            any('\u0400' <= c <= '\u04FF' for c in w) and any('a' <= c <= 'z' for c in w)
            for w in words
        )
        
        print(f"  Overlap at char {overlap_chars}: '{result}' (partial: {has_partial})")
        results.append((overlap_chars, has_partial, result))
    
    bugs = [r for r in results if r[1]]
    print(f"\n  BUGS FOUND: {len(bugs)}/{len(results)}")
    return len(bugs) == 0


def test_bug_rapid_alt_state_corruption():
    """
    BUG: Rapid Alt presses corrupt internal state.
    Test: Press Alt at different speeds, check for consistent cycling.
    """
    print("\n" + "="*60)
    print("BUG TEST: Rapid Alt state corruption")
    print("="*60)
    
    results = []
    for interval_ms in [5, 10, 20, 50, 100, 200]:
        clear_field()
        switch_layout("US")
        
        for c in "ghbdtn":
            type_char(c, "us", delay=0.015)
        type_char(' ', "us", delay=0.3)
        
        initial = get_result()
        
        # Press Alt 6 times at given interval
        states = [initial]
        for _ in range(6):
            press_option(delay=interval_ms/1000)
            states.append(get_result())
        
        # Check if we cycled properly (should return to initial after full cycle)
        # Or at least have consistent state transitions
        unique = len(set(states))
        returned_to_start = states[-1] == states[0] or states[-2] == states[0]
        
        print(f"  Interval {interval_ms}ms: {unique} unique states, returned: {returned_to_start}")
        print(f"    States: {states[:4]}...")
        results.append((interval_ms, unique, returned_to_start, states))
    
    # Check for inconsistencies
    inconsistent = [r for r in results if r[1] < 2]  # Should have at least 2 states
    print(f"\n  INCONSISTENT: {len(inconsistent)}/{len(results)}")
    return len(inconsistent) == 0


def test_bug_timing_window():
    """
    Find the exact timing window where bugs occur.
    """
    print("\n" + "="*60)
    print("BUG TEST: Finding timing window")
    print("="*60)
    
    # Test space-to-Alt timing
    print("\n  Space-to-Alt timing:")
    for delay_ms in [0, 5, 10, 20, 30, 50, 100, 200, 300, 500]:
        clear_field()
        switch_layout("US")
        
        for c in "ghbdtn":
            type_char(c, "us", delay=0.01)
        
        type_char(' ', "us", delay=0)
        time.sleep(delay_ms / 1000)
        press_option(delay=0.2)
        
        result = get_result()
        expected_undo = result in ['ghbdtn', 'גהבדתנ']  # Original or Hebrew
        expected_keep = result == 'привет'
        
        status = "UNDO" if expected_undo else ("KEEP" if expected_keep else "OTHER")
        print(f"    {delay_ms:3d}ms: '{result}' [{status}]")
    
    # This test is informational (prints timing behavior), not a strict pass/fail assertion.
    return True


def test_bug_word_boundary_detection():
    """
    Test if OMFK correctly detects word boundaries with various triggers.
    """
    print("\n" + "="*60)
    print("BUG TEST: Word boundary detection")
    print("="*60)
    
    triggers = [
        (' ', "space"),
        ('.', "period"),
        (',', "comma"),
        ('!', "exclaim"),
        ('?', "question"),
        ('\n', "newline"),
    ]
    
    all_ok = True
    
    for trigger, name in triggers:
        clear_field()
        switch_layout("US")
        
        for c in "ghbdtn":
            type_char(c, "us", delay=0.015)
        type_char(trigger, "us", delay=0.5)
        
        result = get_result()
        corrected = 'привет' in result or 'прив' in result
        
        print(f"  {name:10s}: '{result}' (corrected: {corrected})")
        all_ok = all_ok and corrected
    
    return all_ok


# ============================================================================
# MAIN
# ============================================================================

def main():
    print("=" * 70)
    print("BUG REPRODUCTION TESTS")
    print("=" * 70)
    
    start_omfk()
    setup_textedit()
    
    tests = [
        ("Double space partial char", test_bug_double_space_partial_char),
        ("Alt + immediate typing garbage", test_bug_alt_immediate_typing_garbage),
        ("Backspace + Alt wrong result", test_bug_backspace_alt_wrong_result),
        ("Alt overlap partial correction", test_bug_alt_overlap_partial),
        ("Rapid Alt state corruption", test_bug_rapid_alt_state_corruption),
        ("Timing window analysis", test_bug_timing_window),
        ("Word boundary detection", test_bug_word_boundary_detection),
    ]
    
    results = []
    try:
        for name, test in tests:
            try:
                passed = test()
                results.append((name, passed))
            except Exception as e:
                print(f"  ERROR: {e}")
                import traceback
                traceback.print_exc()
                results.append((name, False))
    finally:
        stop_omfk()
        subprocess.run(['osascript', '-e', 'tell application "TextEdit" to quit saving no'], capture_output=True)
    
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    
    for name, passed in results:
        status = "✓ OK" if passed else "✗ BUG"
        print(f"  {status}: {name}")
    
    bugs = [r for r in results if not r[1]]
    print(f"\nTOTAL BUGS FOUND: {len(bugs)}")
    
    return 0 if len(bugs) == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
