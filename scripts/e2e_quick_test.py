#!/usr/bin/env python3
"""
OMFK Quick E2E Test - tests with current system layouts.
Uses Peekaboo for screenshots if available.
"""

import subprocess
import time
import sys
from pathlib import Path

OMFK_DIR = Path(__file__).parent.parent
LOG_FILE = Path.home() / ".omfk" / "debug.log"

# Test cases: (input, expected, description)
TESTS = [
    # Russian on English
    ("ghbdtn", "привет", "RU 'привет'"),
    ("ntrcn", "текст", "RU 'текст'"),
    ("vbh", "мир", "RU 'мир'"),
    ("ckjdf", "слова", "RU 'слова'"),
    
    # Multiple words
    ("ghbdtn vbh", "привет мир", "RU two words"),
    
    # With punctuation
    ("ghbdtn!", "привет!", "RU with !"),
    ("ghbdtn, vbh", "привет, мир", "RU with comma"),
    
    # Uppercase
    ("GHBDTN", "ПРИВЕТ", "RU uppercase"),
    ("Ghbdtn", "Привет", "RU capitalized"),
]


def run(cmd, check=True):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def clipboard_set(text):
    run(["osascript", "-e", f'set the clipboard to "{text}"'])


def clipboard_get():
    return run(["osascript", "-e", "get the clipboard"], check=False).stdout.strip()


def applescript(script):
    run(["osascript", "-e", script])


def clear_and_type(text):
    """Clear field and paste text."""
    applescript('''
        tell application "System Events"
            keystroke "a" using command down
            delay 0.05
            key code 51
        end tell
    ''')
    time.sleep(0.1)
    
    clipboard_set(text)
    applescript('tell application "System Events" to keystroke "v" using command down')
    time.sleep(0.2)


def select_all():
    applescript('tell application "System Events" to keystroke "a" using command down')
    time.sleep(0.1)


def press_option():
    """Press Option key using CGEvent (OMFK hotkey)."""
    # AppleScript doesn't trigger OMFK properly, use Python CGEvent
    try:
        from Quartz import (
            CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
            kCGHIDEventTap, kCGEventFlagMaskAlternate
        )
        # Option key = keycode 58
        # Key down
        event = CGEventCreateKeyboardEvent(None, 58, True)
        CGEventSetFlags(event, kCGEventFlagMaskAlternate)
        CGEventPost(kCGHIDEventTap, event)
        time.sleep(0.03)
        # Key up
        event = CGEventCreateKeyboardEvent(None, 58, False)
        CGEventPost(kCGHIDEventTap, event)
    except ImportError:
        # Fallback to AppleScript
        applescript('''
            tell application "System Events"
                key down option
                delay 0.03
                key up option
            end tell
        ''')


def get_text():
    """Get text via copy."""
    applescript('tell application "System Events" to keystroke "c" using command down')
    time.sleep(0.15)
    return clipboard_get()


def take_screenshot(label=""):
    """Take screenshot using Peekaboo if available."""
    try:
        result = run(["which", "peekaboo"], check=False)
        if result.returncode == 0:
            ts = time.strftime("%H%M%S")
            path = f"/tmp/omfk_test_{ts}_{label}.png"
            run(["peekaboo", "image", "--mode", "screen", "--path", path], check=False)
            return path
    except:
        pass
    return None


def run_test(input_text, expected, desc):
    """Run single test. Returns (passed, actual)."""
    clear_and_type(input_text)
    select_all()
    
    # Trigger OMFK
    press_option()
    time.sleep(0.8)
    
    # Get result
    actual = get_text()
    passed = actual == expected
    
    return passed, actual


def get_current_layouts():
    """Get currently enabled layouts."""
    script = '''
    use framework "Carbon"
    set layoutList to {}
    set sources to current application's TISCreateInputSourceList(current application's NSDictionary's dictionary(), false)
    repeat with i from 0 to ((sources's |count|()) - 1)
        set src to sources's objectAtIndex:i
        set srcType to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceType)) as text
        if srcType is "TISTypeKeyboardLayout" then
            set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
            set srcName to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyLocalizedName)) as text
            set end of layoutList to srcName
        end if
    end repeat
    return layoutList
    '''
    result = run(["osascript", "-l", "AppleScript", "-e", script], check=False)
    return result.stdout.strip()


def main():
    print("OMFK Quick E2E Test")
    print("=" * 60)
    
    # Show current layouts
    layouts = get_current_layouts()
    print(f"Current layouts: {layouts}")
    print()
    
    # Check OMFK
    result = run(["pgrep", "-x", "OMFK"], check=False)
    if result.returncode != 0:
        print("Starting OMFK...")
        run(["swift", "build"], check=False)
        subprocess.Popen(
            [str(OMFK_DIR / ".build/debug/OMFK")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=OMFK_DIR
        )
        time.sleep(1.5)
    
    # Open TextEdit
    print("Opening TextEdit...")
    run(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    applescript('''
        tell application "TextEdit"
            activate
            if (count of documents) = 0 then make new document
        end tell
    ''')
    time.sleep(0.3)
    
    # Run tests
    passed = 0
    failed = 0
    results = []
    
    print(f"\nRunning {len(TESTS)} tests...\n")
    
    for input_text, expected, desc in TESTS:
        ok, actual = run_test(input_text, expected, desc)
        
        if ok:
            passed += 1
            print(f"✓ {desc}")
        else:
            failed += 1
            print(f"✗ {desc}")
            print(f"    Input:    '{input_text}'")
            print(f"    Expected: '{expected}'")
            print(f"    Got:      '{actual}'")
            # Take screenshot on failure
            screenshot = take_screenshot(f"fail_{desc.replace(' ', '_')}")
            if screenshot:
                print(f"    Screenshot: {screenshot}")
        
        results.append((desc, ok, input_text, expected, actual))
        time.sleep(0.3)
    
    # Summary
    print("\n" + "=" * 60)
    print(f"Results: {passed}/{len(TESTS)} passed, {failed} failed")
    
    if failed:
        print("\nFailed tests:")
        for desc, ok, inp, exp, act in results:
            if not ok:
                print(f"  - {desc}: '{inp}' -> '{act}' (expected '{exp}')")
    
    # Cleanup
    applescript('tell application "TextEdit" to quit saving no')
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    exit(main())
