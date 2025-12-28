#!/usr/bin/env python3
"""
OMFK E2E Layout Combinations Test

Tests OMFK with different keyboard layout combinations using Peekaboo for automation.
Switches system layouts programmatically and verifies correction works correctly.
"""

import subprocess
import time
import json
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import Optional

# Layout combinations to test
LAYOUT_COMBOS = [
    # (EN layout, RU layout, HE layout, description)
    ("com.apple.keylayout.US", "com.apple.keylayout.RussianWin", "com.apple.keylayout.Hebrew-QWERTY", "US + RU-PC + HE-QWERTY (default)"),
    ("com.apple.keylayout.US", "com.apple.keylayout.Russian", "com.apple.keylayout.Hebrew", "US + RU-Mac + HE-Mac"),
    ("com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin", "com.apple.keylayout.Hebrew-PC", "ABC + RU-PC + HE-PC"),
    ("com.apple.keylayout.USInternational-PC", "com.apple.keylayout.Russian", "com.apple.keylayout.Hebrew-QWERTY", "US-Int-PC + RU-Mac + HE-QWERTY"),
    # Two-language combos
    ("com.apple.keylayout.US", "com.apple.keylayout.Russian", None, "US + RU-Mac (no Hebrew)"),
    ("com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew", None, "ABC + HE-Mac (no Russian)"),
]

# Test cases: (input_keycodes, expected_result, source_lang, target_lang, description)
# Keycodes are US QWERTY physical positions
TEST_CASES = [
    # Russian words typed on English layout
    ("ghbdtn", "привет", "en", "ru", "RU 'привет' on EN"),
    ("ntrcn", "текст", "en", "ru", "RU 'текст' on EN"),
    ("vbh", "мир", "en", "ru", "RU 'мир' on EN"),
    
    # English words typed on Russian layout  
    ("ру|щ", "hello", "ru", "en", "EN 'hello' on RU"),
    ("е|у|ые", "test", "ru", "en", "EN 'test' on RU"),
    
    # Hebrew words typed on English layout (for HE-QWERTY)
    ("akuo", "שלום", "en", "he", "HE 'שלום' on EN (QWERTY)"),
]

OMFK_DIR = Path(__file__).parent.parent
LOG_FILE = Path.home() / ".omfk" / "debug.log"


def run_cmd(cmd: list, check=True) -> subprocess.CompletedProcess:
    """Run command and return result."""
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def get_installed_layouts() -> list[str]:
    """Get list of installed keyboard layout IDs."""
    script = '''
    use framework "Carbon"
    set layoutList to {}
    set sources to current application's TISCreateInputSourceList(current application's NSDictionary's dictionary(), false)
    repeat with i from 0 to ((sources's |count|()) - 1)
        set src to sources's objectAtIndex:i
        set srcType to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceType)) as text
        if srcType is "TISTypeKeyboardLayout" then
            set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
            set end of layoutList to srcID
        end if
    end repeat
    return layoutList
    '''
    result = run_cmd(["osascript", "-l", "AppleScript", "-e", script], check=False)
    if result.returncode == 0:
        # Parse AppleScript list output
        layouts = result.stdout.strip().split(", ")
        return [l.strip() for l in layouts if l.strip()]
    return []


def enable_layout(layout_id: str) -> bool:
    """Enable a keyboard layout in System Settings."""
    script = f'''
    use framework "Carbon"
    set targetID to "{layout_id}"
    set sources to current application's TISCreateInputSourceList(current application's NSDictionary's dictionary(), true)
    repeat with i from 0 to ((sources's |count|()) - 1)
        set src to sources's objectAtIndex:i
        set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
        if srcID is targetID then
            current application's TISEnableInputSource(src)
            return true
        end if
    end repeat
    return false
    '''
    result = run_cmd(["osascript", "-l", "AppleScript", "-e", script], check=False)
    return "true" in result.stdout.lower()


def disable_layout(layout_id: str) -> bool:
    """Disable a keyboard layout."""
    script = f'''
    use framework "Carbon"
    set targetID to "{layout_id}"
    set sources to current application's TISCreateInputSourceList(current application's NSDictionary's dictionary(), false)
    repeat with i from 0 to ((sources's |count|()) - 1)
        set src to sources's objectAtIndex:i
        set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
        if srcID is targetID then
            current application's TISDisableInputSource(src)
            return true
        end if
    end repeat
    return false
    '''
    result = run_cmd(["osascript", "-l", "AppleScript", "-e", script], check=False)
    return "true" in result.stdout.lower()


def switch_to_layout(layout_id: str) -> bool:
    """Switch to a specific keyboard layout."""
    script = f'''
    use framework "Carbon"
    set targetID to "{layout_id}"
    set sources to current application's TISCreateInputSourceList(current application's NSDictionary's dictionary(), false)
    repeat with i from 0 to ((sources's |count|()) - 1)
        set src to sources's objectAtIndex:i
        set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
        if srcID is targetID then
            current application's TISSelectInputSource(src)
            return true
        end if
    end repeat
    return false
    '''
    result = run_cmd(["osascript", "-l", "AppleScript", "-e", script], check=False)
    return "true" in result.stdout.lower()


def get_current_layout() -> str:
    """Get current keyboard layout ID."""
    script = '''
    use framework "Carbon"
    set src to current application's TISCopyCurrentKeyboardInputSource()
    set srcID to (current application's TISGetInputSourceProperty(src, current application's kTISPropertyInputSourceID)) as text
    return srcID
    '''
    result = run_cmd(["osascript", "-l", "AppleScript", "-e", script], check=False)
    return result.stdout.strip()


def clipboard_set(text: str):
    """Set clipboard content."""
    run_cmd(["osascript", "-e", f'set the clipboard to "{text}"'])


def clipboard_get() -> str:
    """Get clipboard content."""
    result = run_cmd(["osascript", "-e", "get the clipboard"], check=False)
    return result.stdout.strip()


def press_option():
    """Press Option key (OMFK hotkey)."""
    script = '''
    tell application "System Events"
        key down option
        delay 0.03
        key up option
    end tell
    '''
    run_cmd(["osascript", "-e", script])


def type_text_via_applescript(text: str):
    """Type text using AppleScript keystroke."""
    # Escape special characters
    escaped = text.replace('\\', '\\\\').replace('"', '\\"')
    script = f'''
    tell application "System Events"
        keystroke "{escaped}"
    end tell
    '''
    run_cmd(["osascript", "-e", script])


def select_all_and_copy() -> str:
    """Select all text and copy to clipboard."""
    script = '''
    tell application "System Events"
        keystroke "a" using command down
        delay 0.1
        keystroke "c" using command down
        delay 0.1
    end tell
    '''
    run_cmd(["osascript", "-e", script])
    time.sleep(0.2)
    return clipboard_get()


def clear_text():
    """Clear text in current app."""
    script = '''
    tell application "System Events"
        keystroke "a" using command down
        delay 0.05
        key code 51
    end tell
    '''
    run_cmd(["osascript", "-e", script])
    time.sleep(0.1)


def open_textedit():
    """Open TextEdit with new document."""
    run_cmd(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    script = '''
    tell application "TextEdit"
        activate
        if (count of documents) = 0 then
            make new document
        end if
    end tell
    '''
    run_cmd(["osascript", "-e", script])
    time.sleep(0.3)


def close_textedit():
    """Close TextEdit without saving."""
    script = '''
    tell application "TextEdit"
        close every document saving no
        quit
    end tell
    '''
    run_cmd(["osascript", "-e", script], check=False)


def restart_omfk():
    """Restart OMFK to pick up new layouts."""
    run_cmd(["pkill", "-f", ".build/debug/OMFK"], check=False)
    time.sleep(0.3)
    
    # Build if needed
    result = run_cmd(["swift", "build"], check=False)
    if result.returncode != 0:
        print(f"Build failed: {result.stderr}")
        return False
    
    # Start OMFK
    subprocess.Popen(
        [str(OMFK_DIR / ".build/debug/OMFK")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=OMFK_DIR
    )
    time.sleep(1.5)
    return True


def run_single_test(input_text: str, expected: str, source_lang: str, target_lang: str, desc: str) -> tuple[bool, str]:
    """Run a single test case. Returns (passed, actual_result)."""
    clear_text()
    time.sleep(0.2)
    
    # Type input text
    clipboard_set(input_text)
    script = '''
    tell application "System Events"
        keystroke "v" using command down
    end tell
    '''
    run_cmd(["osascript", "-e", script])
    time.sleep(0.3)
    
    # Select all
    script = '''
    tell application "System Events"
        keystroke "a" using command down
    end tell
    '''
    run_cmd(["osascript", "-e", script])
    time.sleep(0.2)
    
    # Press Option to trigger OMFK
    press_option()
    time.sleep(1.0)
    
    # Get result
    result = select_all_and_copy()
    
    passed = result == expected
    return passed, result


def test_layout_combo(en_layout: str, ru_layout: Optional[str], he_layout: Optional[str], desc: str) -> dict:
    """Test OMFK with a specific layout combination."""
    print(f"\n{'='*70}")
    print(f"Testing: {desc}")
    print(f"  EN: {en_layout}")
    if ru_layout:
        print(f"  RU: {ru_layout}")
    if he_layout:
        print(f"  HE: {he_layout}")
    print(f"{'='*70}")
    
    # Get current layouts to restore later
    original_layouts = get_installed_layouts()
    
    # Enable required layouts
    layouts_to_enable = [en_layout]
    if ru_layout:
        layouts_to_enable.append(ru_layout)
    if he_layout:
        layouts_to_enable.append(he_layout)
    
    for layout in layouts_to_enable:
        if layout not in original_layouts:
            print(f"  Enabling {layout}...")
            enable_layout(layout)
    
    time.sleep(0.5)
    
    # Restart OMFK to detect new layouts
    print("  Restarting OMFK...")
    if not restart_omfk():
        return {"combo": desc, "error": "Failed to restart OMFK", "tests": []}
    
    # Switch to English layout for typing
    switch_to_layout(en_layout)
    time.sleep(0.3)
    
    # Run tests
    results = []
    for input_text, expected, src_lang, tgt_lang, test_desc in TEST_CASES:
        # Skip tests that require unavailable layouts
        if tgt_lang == "ru" and not ru_layout:
            continue
        if tgt_lang == "he" and not he_layout:
            continue
        
        passed, actual = run_single_test(input_text, expected, src_lang, tgt_lang, test_desc)
        status = "✓" if passed else "✗"
        print(f"  {status} {test_desc}: '{input_text}' -> '{actual}' (expected: '{expected}')")
        results.append({
            "desc": test_desc,
            "input": input_text,
            "expected": expected,
            "actual": actual,
            "passed": passed
        })
    
    return {
        "combo": desc,
        "en": en_layout,
        "ru": ru_layout,
        "he": he_layout,
        "tests": results,
        "passed": sum(1 for r in results if r["passed"]),
        "total": len(results)
    }


def main():
    print("OMFK E2E Layout Combinations Test")
    print("=" * 70)
    
    # Check if running with specific combo
    if len(sys.argv) > 1:
        combo_idx = int(sys.argv[1])
        if 0 <= combo_idx < len(LAYOUT_COMBOS):
            combos = [LAYOUT_COMBOS[combo_idx]]
        else:
            print(f"Invalid combo index. Available: 0-{len(LAYOUT_COMBOS)-1}")
            return 1
    else:
        combos = LAYOUT_COMBOS
    
    # Save original layouts
    original_layouts = get_installed_layouts()
    print(f"Original layouts: {len(original_layouts)}")
    
    # Open TextEdit
    open_textedit()
    
    all_results = []
    
    try:
        for en, ru, he, desc in combos:
            result = test_layout_combo(en, ru, he, desc)
            all_results.append(result)
    finally:
        # Cleanup
        close_textedit()
        run_cmd(["pkill", "-f", ".build/debug/OMFK"], check=False)
    
    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    
    total_passed = 0
    total_tests = 0
    
    for result in all_results:
        if "error" in result:
            print(f"❌ {result['combo']}: {result['error']}")
        else:
            status = "✓" if result["passed"] == result["total"] else "✗"
            print(f"{status} {result['combo']}: {result['passed']}/{result['total']} passed")
            total_passed += result["passed"]
            total_tests += result["total"]
    
    print(f"\nTotal: {total_passed}/{total_tests} tests passed")
    
    # Save results
    results_file = OMFK_DIR / "test_results.json"
    with open(results_file, "w") as f:
        json.dump(all_results, f, indent=2, ensure_ascii=False)
    print(f"\nResults saved to: {results_file}")
    
    return 0 if total_passed == total_tests else 1


if __name__ == "__main__":
    exit(main())
