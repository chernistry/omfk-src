#!/usr/bin/env python3
"""
Minimal test for Hebrew layout conversion issue.
Tests "akuo" -> "שלום" across different Hebrew layouts.
"""

import subprocess
import time
import sys
import os

OMFK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def switch_layout(name):
    subprocess.run([f"{OMFK_DIR}/scripts/switch_layout", "select", name], 
                   capture_output=True, text=True)
    time.sleep(0.3)

def type_text(text):
    """Type text using osascript"""
    subprocess.run(['osascript', '-e', f'tell application "System Events" to keystroke "{text}"'],
                   capture_output=True)

def get_clipboard():
    """Get clipboard content"""
    r = subprocess.run(['pbpaste'], capture_output=True, text=True)
    return r.stdout

def clear_and_select_all():
    """Clear text and select all"""
    subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "a" using command down'],
                   capture_output=True)
    time.sleep(0.1)

def copy_selection():
    """Copy selection to clipboard"""
    subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "c" using command down'],
                   capture_output=True)
    time.sleep(0.2)

def run_test(input_text, expected, desc):
    """Run a single test case"""
    # Clear clipboard
    subprocess.run(['pbcopy'], input=b'', capture_output=True)
    
    # Select all and delete
    clear_and_select_all()
    subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 51'],  # delete
                   capture_output=True)
    time.sleep(0.1)
    
    # Type input + space (to trigger correction)
    type_text(input_text + " ")
    time.sleep(1.5)  # Wait for OMFK to process
    
    # Select all and copy
    clear_and_select_all()
    copy_selection()
    
    result = get_clipboard().strip()
    
    # Check result
    passed = result == expected or result == expected + " "
    status = "✓" if passed else "✗"
    print(f"{status} {desc}")
    if not passed:
        print(f"    input: '{input_text}'")
        print(f"    got: '{result}'")
        print(f"    expected: '{expected}'")
    return passed

def main():
    print("=" * 60)
    print("HEBREW LAYOUT MINIMAL TEST")
    print("=" * 60)
    
    # Ensure TextEdit is open
    subprocess.run(['osascript', '-e', 'tell application "TextEdit" to activate'], capture_output=True)
    time.sleep(0.5)
    
    # Get current layouts
    r = subprocess.run([f"{OMFK_DIR}/scripts/switch_layout", "list"], capture_output=True, text=True)
    print(f"Available layouts: {r.stdout.strip()}")
    print()
    
    tests = [
        # Test 1: akuo on Mac Hebrew system
        {
            "setup": lambda: switch_layout("Hebrew"),
            "input": "akuo",
            "expected": "שלום",
            "desc": "akuo -> שלום (Hebrew Mac active)",
            "layout": "Hebrew"
        },
        # Test 2: akuo on Hebrew QWERTY system (THE BUG)
        {
            "setup": lambda: switch_layout("Hebrew-QWERTY"),
            "input": "akuo",
            "expected": "שלום",
            "desc": "akuo -> שלום (Hebrew QWERTY active - should try all HE layouts!)",
            "layout": "Hebrew-QWERTY"
        },
        # Test 3: wlvM on Hebrew QWERTY system (correct QWERTY input)
        {
            "setup": lambda: switch_layout("Hebrew-QWERTY"),
            "input": "wlvM",
            "expected": "שלום",
            "desc": "wlvM -> שלום (Hebrew QWERTY native)",
            "layout": "Hebrew-QWERTY"
        },
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        print(f"\n--- Testing with {test['layout']} ---")
        test["setup"]()
        time.sleep(0.3)
        switch_layout("US")  # Always type on US
        time.sleep(0.3)
        
        if run_test(test["input"], test["expected"], test["desc"]):
            passed += 1
        else:
            failed += 1
    
    print()
    print("=" * 60)
    print(f"Results: {passed}/{passed + failed} passed")
    print("=" * 60)
    
    return failed == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
