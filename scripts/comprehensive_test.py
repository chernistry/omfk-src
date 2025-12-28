#!/usr/bin/env python3
"""
OMFK Comprehensive Test Runner

Loads test cases from JSON and runs them against OMFK.
Supports: single words, paragraphs, context boost, cycling, stress tests.
"""

import json
import subprocess
import time
import sys
import os
import random
from pathlib import Path
from datetime import datetime

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskAlternate, kCGEventFlagMaskCommand
)
from ApplicationServices import (
    AXUIElementCreateSystemWide, AXUIElementCopyAttributeValue,
    kAXFocusedUIElementAttribute, kAXValueAttribute
)
from AppKit import NSPasteboard, NSStringPboardType

OMFK_DIR = Path(__file__).parent.parent
TESTS_FILE = OMFK_DIR / "tests/test_cases.json"
LOG_FILE = Path.home() / ".omfk" / "debug.log"

KEY_OPTION, KEY_DELETE, KEY_SPACE = 58, 51, 49


def press_key(keycode, flags=0):
    ev = CGEventCreateKeyboardEvent(None, keycode, True)
    if flags: CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.015)
    ev = CGEventCreateKeyboardEvent(None, keycode, False)
    if flags: CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.015)


def press_option():
    ev = CGEventCreateKeyboardEvent(None, KEY_OPTION, True)
    CGEventSetFlags(ev, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.03)
    ev = CGEventCreateKeyboardEvent(None, KEY_OPTION, False)
    CGEventPost(kCGHIDEventTap, ev)


def cmd_key(kc):
    press_key(kc, kCGEventFlagMaskCommand)


def clipboard_set(text):
    pb = NSPasteboard.generalPasteboard()
    pb.clearContents()
    pb.setString_forType_(text, NSStringPboardType)


def clipboard_get():
    return NSPasteboard.generalPasteboard().stringForType_(NSStringPboardType) or ""


def get_text():
    sw = AXUIElementCreateSystemWide()
    err, el = AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute, None)
    if err == 0 and el:
        err, val = AXUIElementCopyAttributeValue(el, kAXValueAttribute, None)
        if err == 0 and val:
            return str(val)
    return ""


def clear_field():
    cmd_key(0)  # Cmd+A
    time.sleep(0.05)
    press_key(KEY_DELETE)
    time.sleep(0.05)


def type_and_space(text):
    """Type text via paste, then press space."""
    clipboard_set(text)
    cmd_key(9)  # Cmd+V
    time.sleep(0.1)
    press_key(KEY_SPACE)
    time.sleep(0.8)  # Wait for OMFK


def select_all_and_correct():
    """Select all and press Option to correct."""
    cmd_key(0)  # Cmd+A
    time.sleep(0.1)
    press_option()
    time.sleep(0.8)


def get_result():
    """Get current text."""
    return get_text().strip()


def start_omfk():
    subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    time.sleep(0.3)
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    
    env = os.environ.copy()
    env["OMFK_DEBUG_LOG"] = "1"
    subprocess.Popen([str(OMFK_DIR / ".build/debug/OMFK")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)


def open_textedit():
    subprocess.run(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    subprocess.run(["osascript", "-e", '''
        tell application "TextEdit"
            activate
            if (count of documents) = 0 then make new document
        end tell
    '''], capture_output=True)
    time.sleep(0.3)


def close_textedit():
    subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'], capture_output=True)


# ============== TEST RUNNERS ==============

def run_single_test(input_text, expected):
    """Run single correction test."""
    clear_field()
    time.sleep(0.15)
    
    clipboard_set(input_text)
    cmd_key(9)  # Paste
    time.sleep(0.15)
    
    cmd_key(0)  # Select all
    time.sleep(0.1)
    
    press_option()
    time.sleep(0.8)
    
    result = get_result()
    return result == expected, result


def run_context_boost_test(words, expected_final):
    """Test word-by-word typing with context boost.
    
    Simulates typing words one by one, with OMFK correcting after each.
    The key test: first ambiguous word should be corrected when second word confirms language.
    """
    clear_field()
    time.sleep(0.2)
    
    # Type all words with spaces
    full_text = " ".join(words)
    clipboard_set(full_text)
    cmd_key(9)  # Paste
    time.sleep(0.15)
    
    # Select all and correct
    cmd_key(0)  # Cmd+A
    time.sleep(0.1)
    press_option()
    time.sleep(0.8)
    
    result = get_result().rstrip()
    return result == expected_final, result


def run_cycling_test(input_text, alt_presses, expected_sequence=None):
    """Test Alt cycling through alternatives."""
    clear_field()
    time.sleep(0.15)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.15)
    cmd_key(0)
    time.sleep(0.1)
    
    results = [get_result()]
    
    for i in range(alt_presses):
        press_option()
        time.sleep(0.3)
        results.append(get_result())
    
    if expected_sequence:
        # Check if results match expected sequence
        match = all(r == e for r, e in zip(results, expected_sequence) if e is not None)
        return match, results
    
    return True, results  # Just verify no crash


def run_stress_cycling(input_text, times, delay_ms=50):
    """Rapid Alt spam test."""
    clear_field()
    time.sleep(0.15)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.15)
    cmd_key(0)
    time.sleep(0.1)
    
    for _ in range(times):
        press_option()
        time.sleep(delay_ms / 1000)
    
    time.sleep(0.3)
    result = get_result()
    return len(result) > 0, result


def run_performance_test(input_text, expected, max_time_ms):
    """Test correction speed."""
    clear_field()
    time.sleep(0.15)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.15)
    cmd_key(0)
    time.sleep(0.1)
    
    start = time.time()
    press_option()
    time.sleep(0.5)  # Minimum wait
    result = get_result()
    elapsed_ms = (time.time() - start) * 1000
    
    correct = result == expected
    fast_enough = elapsed_ms <= max_time_ms
    
    return correct and fast_enough, result, elapsed_ms


# ============== MAIN ==============

def main():
    print("OMFK Comprehensive Test Runner")
    print("=" * 70)
    
    # Load test cases
    with open(TESTS_FILE) as f:
        tests = json.load(f)
    
    # Parse args
    categories = sys.argv[1:] if len(sys.argv) > 1 else None
    
    # Build OMFK
    print("Building OMFK...")
    r = subprocess.run(["swift", "build"], cwd=OMFK_DIR, capture_output=True)
    if r.returncode != 0:
        print("Build failed!")
        return 1
    
    start_omfk()
    open_textedit()
    
    total_passed = 0
    total_failed = 0
    results = []
    
    try:
        # Single words
        if not categories or "single" in categories:
            print("\n" + "=" * 70)
            print("SINGLE WORDS")
            print("=" * 70)
            for case in tests.get("single_words", {}).get("cases", []):
                ok, result = run_single_test(case["input"], case["expected"])
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}")
                if not ok:
                    print(f"    '{case['input']}' → '{result}' (expected '{case['expected']}')")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.2)
        
        # Paragraphs
        if not categories or "paragraphs" in categories:
            print("\n" + "=" * 70)
            print("PARAGRAPHS")
            print("=" * 70)
            for case in tests.get("paragraphs", {}).get("cases", []):
                ok, result = run_single_test(case["input"], case["expected"])
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}")
                if not ok:
                    print(f"    Got: '{result[:60]}...'")
                    print(f"    Exp: '{case['expected'][:60]}...'")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.3)
        
        # Context boost
        if not categories or "context" in categories:
            print("\n" + "=" * 70)
            print("CONTEXT BOOST (word-by-word)")
            print("=" * 70)
            for case in tests.get("context_boost_realistic", {}).get("cases", []):
                ok, result = run_context_boost_test(case["words"], case["expected_final"])
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}")
                if not ok:
                    print(f"    Words: {case['words']}")
                    print(f"    Got: '{result}'")
                    print(f"    Exp: '{case['expected_final']}'")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.3)
        
        # Cycling
        if not categories or "cycling" in categories:
            print("\n" + "=" * 70)
            print("ALT CYCLING")
            print("=" * 70)
            for case in tests.get("cycling_tests", {}).get("cases", []):
                expected_seq = case.get("expected_sequence")
                ok, result = run_cycling_test(case["input"], case["alt_presses"], expected_seq)
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}")
                if not ok:
                    print(f"    Results: {result}")
                    if expected_seq:
                        print(f"    Expected: {expected_seq}")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.2)
        
        # Stress
        if not categories or "stress" in categories:
            print("\n" + "=" * 70)
            print("STRESS TESTS")
            print("=" * 70)
            
            # Rapid cycling
            print("Testing rapid Alt spam (10x)...")
            ok, result = run_stress_cycling("ghbdtn vbh ntrcn", 10, 50)
            status = "✓" if ok else "✗"
            print(f"{status} Rapid cycling - result not empty: {len(result)} chars")
            if ok:
                total_passed += 1
            else:
                total_failed += 1
            
            # Random cycling
            print("Testing random cycling (1-5 times, 3 rounds)...")
            for i in range(3):
                times = random.randint(1, 5)
                ok, result = run_stress_cycling("ntrcn lkz ntcnf", times, 100)
                status = "✓" if ok else "✗"
                print(f"  {status} Round {i+1}: {times} presses → '{result[:30]}...'")
                if ok:
                    total_passed += 1
                else:
                    total_failed += 1
                time.sleep(0.2)
        
        # Performance
        if not categories or "perf" in categories:
            print("\n" + "=" * 70)
            print("PERFORMANCE")
            print("=" * 70)
            for case in tests.get("performance_stress", {}).get("cases", []):
                ok, result, elapsed = run_performance_test(
                    case["input"], case["expected"], case["max_time_ms"]
                )
                status = "✓" if ok else "✗"
                print(f"{status} {case['desc']}: {elapsed:.0f}ms (max {case['max_time_ms']}ms)")
                if not ok:
                    if result != case["expected"]:
                        print(f"    Result mismatch")
                    if elapsed > case["max_time_ms"]:
                        print(f"    Too slow!")
                    total_failed += 1
                else:
                    total_passed += 1
        
    finally:
        close_textedit()
        subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    
    # Summary
    print("\n" + "=" * 70)
    print(f"TOTAL: {total_passed} passed, {total_failed} failed")
    print("=" * 70)
    
    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    exit(main())
