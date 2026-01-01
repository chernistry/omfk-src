#!/usr/bin/env python3
"""
E2E test runner for GitHub issues test cases.
Tests OMFK with real keyboard events and clipboard operations.
"""

import json
import subprocess
import time
import sys
from pathlib import Path

# AppleScript for typing simulation
APPLESCRIPT_TYPE = '''
tell application "TextEdit"
    activate
    delay 0.3
    tell application "System Events"
        keystroke "n" using command down
        delay 0.2
        keystroke "{text}"
        delay {delay}
    end tell
end tell
'''

APPLESCRIPT_GET_TEXT = '''
tell application "TextEdit"
    activate
    delay 0.1
    tell application "System Events"
        keystroke "a" using command down
        delay 0.1
        keystroke "c" using command down
        delay 0.2
    end tell
end tell
'''

APPLESCRIPT_CLOSE = '''
tell application "TextEdit"
    close every window without saving
end tell
'''

def run_applescript(script):
    """Execute AppleScript and return output."""
    result = subprocess.run(
        ['osascript', '-e', script],
        capture_output=True,
        text=True
    )
    return result.returncode == 0

def get_clipboard():
    """Get clipboard content."""
    result = subprocess.run(['pbpaste'], capture_output=True, text=True)
    return result.stdout

def is_omfk_running():
    """Check if OMFK is running."""
    result = subprocess.run(
        ['pgrep', '-x', 'OMFK'],
        capture_output=True
    )
    return result.returncode == 0

def start_omfk():
    """Start OMFK application."""
    app_path = '/Applications/OMFK.app'
    if not Path(app_path).exists():
        print(f"❌ OMFK not found at {app_path}")
        return False
    
    subprocess.Popen(['open', app_path])
    time.sleep(2)
    return is_omfk_running()

def type_and_capture(text, delay=0.5):
    """Type text in TextEdit and capture result."""
    # Type text
    script = APPLESCRIPT_TYPE.format(text=text, delay=delay)
    if not run_applescript(script):
        return None
    
    # Get text via clipboard
    if not run_applescript(APPLESCRIPT_GET_TEXT):
        return None
    
    result = get_clipboard().strip()
    
    # Close window
    run_applescript(APPLESCRIPT_CLOSE)
    
    return result

def run_test_case(case, category):
    """Run single test case."""
    input_text = case['input']
    expected = case['expected']
    desc = case.get('desc', '')
    
    print(f"  Testing: {desc}")
    print(f"    Input: {input_text}")
    print(f"    Expected: {expected}")
    
    actual = type_and_capture(input_text)
    
    if actual is None:
        print(f"    ❌ FAILED: Could not capture output")
        return False
    
    print(f"    Actual: {actual}")
    
    if actual == expected:
        print(f"    ✅ PASSED")
        return True
    else:
        print(f"    ❌ FAILED")
        return False

def run_tests(test_file):
    """Run all tests from JSON file."""
    with open(test_file) as f:
        data = json.load(f)
    
    print(f"\n{'='*60}")
    print(f"OMFK E2E Tests - {data['description']}")
    print(f"{'='*60}\n")
    
    # Check OMFK
    if not is_omfk_running():
        print("⚠️  OMFK not running. Starting...")
        if not start_omfk():
            print("❌ Failed to start OMFK")
            return
        print("✅ OMFK started\n")
    else:
        print("✅ OMFK is running\n")
    
    total = 0
    passed = 0
    failed_cases = []
    
    # Run tests by category
    for category, content in data.items():
        if category in ['version', 'description']:
            continue
        
        print(f"\n{'─'*60}")
        print(f"Category: {content['description']}")
        print(f"{'─'*60}")
        
        for case in content['cases']:
            total += 1
            if run_test_case(case, category):
                passed += 1
            else:
                failed_cases.append({
                    'category': category,
                    'case': case
                })
            time.sleep(0.5)  # Delay between tests
    
    # Summary
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Total: {total}")
    print(f"Passed: {passed} ({passed/total*100:.1f}%)")
    print(f"Failed: {total-passed} ({(total-passed)/total*100:.1f}%)")
    
    if failed_cases:
        print(f"\n{'─'*60}")
        print("FAILED CASES:")
        print(f"{'─'*60}")
        for item in failed_cases:
            case = item['case']
            print(f"\n{item['category']}: {case.get('desc', '')}")
            print(f"  Input: {case['input']}")
            print(f"  Expected: {case['expected']}")
    
    return passed == total

if __name__ == '__main__':
    test_file = Path(__file__).parent / 'github_issues_test_cases.json'
    
    if not test_file.exists():
        print(f"❌ Test file not found: {test_file}")
        sys.exit(1)
    
    success = run_tests(test_file)
    sys.exit(0 if success else 1)
