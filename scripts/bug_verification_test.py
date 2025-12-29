#!/usr/bin/env python3
"""
Bug Verification Tests for OMFK

Tests specific bugs from current_task.md to verify if they're fixed.
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


def setup_textedit():
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            make new document
        end tell
    '''], capture_output=True)
    time.sleep(0.5)


# ============ BUG TESTS ============

def test_bug_b_mixed_input_duplication():
    """Bug B: "шзрщтуiphone" → "iphoneiphone" (Duplication)"""
    clear_field()
    # Type Russian "шзрщту" (which is "iphone" on RU layout) + "iphone"
    # This simulates mixed input
    type_word("iphone", "russian")  # шзрщту
    type_word("iphone", "us")       # iphone
    type_space()
    
    result = get_result().strip()
    # Should NOT have duplication
    has_duplication = "iphoneiphone" in result.lower()
    
    return {
        "name": "Bug B: Mixed input duplication",
        "input": "шзрщтуiphone",
        "got": result,
        "expected": "NOT 'iphoneiphone'",
        "passed": not has_duplication,
        "note": "Duplication detected" if has_duplication else "No duplication"
    }


def test_bug_double_space_partial():
    """BUG 1: Double Space Leaves Partial Character"""
    clear_field()
    type_word("ghbdtn", "us")
    type_space(wait=0.05)  # First space
    type_space(wait=0.05)  # Second space quickly
    time.sleep(0.5)
    
    result = get_result().strip()
    press_option()  # Undo
    time.sleep(0.3)
    
    undone = get_result().strip()
    
    # After undo, should be clean "ghbdtn" without partial Cyrillic
    has_partial = any('\u0400' <= c <= '\u04FF' for c in undone) and any('a' <= c.lower() <= 'z' for c in undone)
    
    return {
        "name": "BUG 1: Double space partial char",
        "input": "ghbdtn + double space + Alt",
        "got": undone,
        "expected": "ghbdtn (clean undo)",
        "passed": not has_partial,
        "note": "Partial char remains" if has_partial else "Clean undo"
    }


def test_bug_backspace_alt_deleted_char():
    """BUG 3: Backspace + Alt Shows Deleted Character"""
    clear_field()
    type_word("ghbdtx", "us")  # Typo
    press_backspace()
    type_char("n", "us")
    type_space()
    
    result = get_result().strip()
    press_option()  # Undo
    time.sleep(0.3)
    
    undone = get_result().strip()
    
    # Should NOT contain the deleted 'x'
    has_deleted = 'x' in undone
    
    return {
        "name": "BUG 3: Backspace + Alt shows deleted",
        "input": "ghbdtx + backspace + n + space + Alt",
        "got": undone,
        "expected": "ghbdtn (no 'x')",
        "passed": not has_deleted,
        "note": "Deleted char 'x' appears" if has_deleted else "Clean"
    }


def test_bug_punctuation_trigger():
    """BUG 4: Word Boundary Detection - punctuation should trigger correction"""
    results = []
    
    for punct, name in [('.', 'period'), (',', 'comma'), ('!', 'exclaim'), ('?', 'question')]:
        clear_field()
        type_word("ghbdtn", "us")
        type_char(punct, "us")
        time.sleep(0.8)
        
        result = get_result().strip()
        corrected = 'привет' in result
        
        results.append({
            "punct": name,
            "got": result,
            "corrected": corrected
        })
    
    all_passed = all(r["corrected"] for r in results)
    
    return {
        "name": "BUG 4: Punctuation as word boundary",
        "input": "ghbdtn + various punctuation",
        "got": str(results),
        "expected": "All should correct to 'привет'",
        "passed": all_passed,
        "note": f"{sum(r['corrected'] for r in results)}/4 punctuation types trigger correction"
    }


def test_single_letter_russian():
    """BUG GROUP 1: Single-Letter Russian Words"""
    cases = [
        ("f", "а"),  # а
        ("j", "о"),  # о
        ("e", "у"),  # у
        ("r", "к"),  # к
    ]
    
    results = []
    for en_char, ru_expected in cases:
        clear_field()
        type_char(en_char, "us")
        type_space()
        type_word("ghbdtn", "us")  # привет - context
        type_space()
        
        result = get_result().strip()
        # Check if first word is Russian
        first_word = result.split()[0] if result.split() else ""
        is_russian = first_word == ru_expected
        
        results.append({
            "input": en_char,
            "expected": ru_expected,
            "got": first_word,
            "passed": is_russian
        })
    
    passed_count = sum(r["passed"] for r in results)
    
    return {
        "name": "BUG GROUP 1: Single-letter Russian words",
        "input": "f/j/e/r + context",
        "got": str([(r["input"], r["got"]) for r in results]),
        "expected": "а/о/у/к",
        "passed": passed_count == len(cases),
        "note": f"{passed_count}/{len(cases)} single letters converted"
    }


def test_vs_to_my():
    """BUG GROUP 2: 'vs' → 'мы' Not Converted"""
    clear_field()
    type_word("d", "us")  # в
    type_space(wait=0.3)
    type_word("'njv", "us")  # этом
    type_space(wait=0.3)
    type_word("ujle", "us")  # году
    type_space(wait=0.3)
    type_word("vs", "us")  # мы
    type_space(wait=0.3)
    type_word("pfgecnbkb", "us")  # запустили
    type_space()
    
    result = get_result().strip()
    has_my = "мы" in result
    has_vs = "vs" in result.lower()
    
    return {
        "name": "BUG GROUP 2: 'vs' → 'мы'",
        "input": "d 'njv ujle vs pfgecnbkb",
        "got": result,
        "expected": "в этом году мы запустили",
        "passed": has_my and not has_vs,
        "note": "'мы' present" if has_my else "'vs' not converted"
    }


def test_punctuation_preserved():
    """BUG GROUP 3: Punctuation Converted Instead of Preserved"""
    cases = [
        ("ghbdtn.rfr", "привет.как", "period"),
        ("ghbdtn,rfr", "привет,как", "comma"),
    ]
    
    results = []
    for input_str, expected_start, name in cases:
        clear_field()
        for char in input_str:
            type_char(char, "us")
        type_space()
        
        result = get_result().strip()
        # Check if punctuation is preserved (not converted to ю or б)
        punct_preserved = '.' in result or ',' in result
        no_yu = 'ю' not in result[:15]  # . → ю on Russian layout
        no_b = 'б' not in result[:15]   # , → б on Russian layout
        
        results.append({
            "name": name,
            "got": result[:20],
            "punct_ok": punct_preserved and no_yu and no_b
        })
    
    all_passed = all(r["punct_ok"] for r in results)
    
    return {
        "name": "BUG GROUP 3: Punctuation preserved",
        "input": "ghbdtn.rfr / ghbdtn,rfr",
        "got": str([(r["name"], r["got"]) for r in results]),
        "expected": "привет.как / привет,как",
        "passed": all_passed,
        "note": f"{sum(r['punct_ok'] for r in results)}/{len(cases)} punctuation preserved"
    }


def test_colon_semicolon_preserved():
    """BUG GROUP 4: Colon/Semicolon Stripped"""
    cases = [
        ("ghbdtn:", "привет:", "colon"),
        ("ghbdtn;", "привет;", "semicolon"),
    ]
    
    results = []
    for input_str, expected, name in cases:
        clear_field()
        for char in input_str:
            type_char(char, "us")
        type_space()
        type_word("vbh", "us")  # мир
        type_space()
        
        result = get_result().strip()
        punct_char = ':' if name == "colon" else ';'
        has_punct = punct_char in result
        
        results.append({
            "name": name,
            "got": result,
            "has_punct": has_punct
        })
    
    all_passed = all(r["has_punct"] for r in results)
    
    return {
        "name": "BUG GROUP 4: Colon/semicolon preserved",
        "input": "ghbdtn: / ghbdtn;",
        "got": str([(r["name"], r["got"]) for r in results]),
        "expected": "привет: / привет;",
        "passed": all_passed,
        "note": f"{sum(r['has_punct'] for r in results)}/{len(cases)} preserved"
    }


def test_user_dictionary_learning():
    """Test User Dictionary learning (Ticket 28)"""
    # Clear dictionary first
    dict_path = Path.home() / ".omfk" / "user_dictionary.json"
    if dict_path.exists():
        dict_path.unlink()
    
    # Type "ye" and undo twice to trigger keepAsIs
    for i in range(2):
        clear_field()
        type_word("ye", "us")
        type_space()
        time.sleep(0.5)
        press_option()  # Undo
        time.sleep(0.3)
    
    # Now type "ye" again - should NOT auto-correct
    clear_field()
    type_word("ye", "us")
    type_space()
    time.sleep(0.5)
    
    result = get_result().strip()
    kept_as_is = "ye" in result.lower() and "ну" not in result
    
    # Check if rule was saved
    rule_saved = False
    if dict_path.exists():
        with open(dict_path) as f:
            data = json.load(f)
            # Format is array of rules
            if isinstance(data, list):
                rule_saved = any(r.get("token") == "ye" for r in data)
            else:
                rule_saved = any(r.get("token") == "ye" for r in data.get("rules", {}).values())
    
    return {
        "name": "User Dictionary: keepAsIs after 2 undos",
        "input": "ye (undo x2) → ye",
        "got": result,
        "expected": "ye (not converted)",
        "passed": kept_as_is,
        "note": f"Rule saved: {rule_saved}, Kept as-is: {kept_as_is}"
    }


def test_user_dictionary_prefer_hypothesis():
    """Test User Dictionary preferHypothesis learning"""
    # Clear dictionary
    dict_path = Path.home() / ".omfk" / "user_dictionary.json"
    if dict_path.exists():
        dict_path.unlink()
    
    # Type "ye", let it correct, then manually select Russian via Alt
    clear_field()
    type_word("ye", "us")
    type_space()
    time.sleep(0.5)
    
    # Press Alt to cycle to Russian "ну"
    press_option()
    time.sleep(0.3)
    
    result1 = get_result().strip()
    
    # Now type "ye" again - should auto-correct to "ну"
    clear_field()
    type_word("ye", "us")
    type_space()
    time.sleep(0.5)
    
    result2 = get_result().strip()
    learned = "ну" in result2
    
    return {
        "name": "User Dictionary: preferHypothesis after manual",
        "input": "ye → Alt(ну) → ye",
        "got": f"After manual: {result1}, After learning: {result2}",
        "expected": "ну (auto-corrected)",
        "passed": learned,
        "note": "Learned preference" if learned else "Not learned"
    }


# ============ MAIN ============

def main():
    print("=" * 60)
    print("OMFK Bug Verification Tests")
    print("=" * 60)
    
    setup_textedit()
    time.sleep(1)
    
    tests = [
        test_bug_b_mixed_input_duplication,
        test_bug_double_space_partial,
        test_bug_backspace_alt_deleted_char,
        test_bug_punctuation_trigger,
        test_single_letter_russian,
        test_vs_to_my,
        test_punctuation_preserved,
        test_colon_semicolon_preserved,
        test_user_dictionary_learning,
        test_user_dictionary_prefer_hypothesis,
    ]
    
    results = []
    for test_fn in tests:
        print(f"\nRunning: {test_fn.__name__}...")
        try:
            result = test_fn()
            results.append(result)
            status = "✓ PASS" if result["passed"] else "✗ FAIL"
            print(f"  {status}: {result['name']}")
            print(f"    Got: {result['got'][:80]}..." if len(str(result['got'])) > 80 else f"    Got: {result['got']}")
            print(f"    Note: {result['note']}")
        except Exception as e:
            print(f"  ✗ ERROR: {e}")
            results.append({"name": test_fn.__name__, "passed": False, "note": str(e)})
    
    print("\n" + "=" * 60)
    passed = sum(1 for r in results if r.get("passed"))
    print(f"SUMMARY: {passed}/{len(results)} tests passed")
    print("=" * 60)
    
    # Print failures
    failures = [r for r in results if not r.get("passed")]
    if failures:
        print("\nFAILED TESTS:")
        for f in failures:
            print(f"  - {f['name']}: {f.get('note', 'N/A')}")
    
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
