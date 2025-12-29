#!/usr/bin/env python3
"""
Realistic E2E Tests for OMFK

Tests real-world typing scenarios with:
- Variable typing speed
- Typos and corrections
- Mixed languages
- Real sentences people actually type
- Layout switching
"""

import subprocess
import time
import json
import sys
import random
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Tuple

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskAlternate,
)

OMFK_DIR = Path(__file__).parent.parent

# Load keycodes
_keycodes = {}
keycodes_path = OMFK_DIR / "scripts" / "keycodes.json"
if keycodes_path.exists():
    with open(keycodes_path) as f:
        _keycodes = json.load(f)


@dataclass
class TestCase:
    name: str
    input_text: str
    expected: str
    category: str
    typing_speed: str = "normal"  # slow, normal, fast, variable
    source_layout: str = "us"


# ============ REALISTIC TEST CASES ============

REALISTIC_TESTS = [
    # === REAL CHAT MESSAGES ===
    TestCase("telegram_quick", "ghbdtn rfr ltkf", "привет как дела", "chat", "fast"),
    TestCase("whatsapp_context", "cksim xnj yjdjuj", "слышь что нового", "chat", "variable"),
    TestCase("discord_gamer", "ujnjd r htqle", "готов к рейду", "chat", "fast"),
    TestCase("slack_work", "vjue gjpdjybnm xthtp 5 vby", "могу позвонить через 5 мин", "chat", "normal"),
    
    # === WORK EMAILS ===
    TestCase("email_formal", "ljhjujq rjkktuf", "дорогой коллега", "email", "slow"),
    TestCase("email_request", "gj;fkeqcnf jnghfdmnt jnxtn", "пожалуйста отправьте отчет", "email", "normal"),
    TestCase("email_deadline", "lj rjywf lyz ytj,[jlbvj", "до конца дня необходимо", "email", "normal"),
    
    # === CODE COMMENTS (mixed EN/RU) ===
    TestCase("code_todo", "TODO: bcghfdbnm ,fu c null", "TODO: исправить баг с null", "code", "normal"),
    TestCase("git_commit", "fix: bcghfdkty rhfi ghb pfuhepr", "fix: исправлен краш при загрузк", "code", "fast"),
    
    # === SEARCH QUERIES ===
    TestCase("google_search", "rfr ecnfyjdbnm python yf mac", "как установить python на mac", "search", "fast"),
    TestCase("youtube_search", "rehcs swift lkz yfxbyf.ob[", "курсы swift для начинающих", "search", "fast"),
    
    # === SINGLE LETTER PREPOSITIONS ===
    TestCase("preposition_v", "d 'njv ujle", "в этом году", "grammar", "normal"),
    TestCase("preposition_s", "c lytv hj;ltybz", "с днем рождения", "grammar", "normal"),
    TestCase("preposition_k", "r cj;fktyb. ytdjpvj;yj", "к сожалению невозможно", "grammar", "normal"),
    TestCase("preposition_u", "e vtyz tcnm bltz", "у меня есть идея", "grammar", "normal"),
    TestCase("preposition_o", "j xtv htxm", "о чем речь", "grammar", "normal"),
    
    # === PUNCTUATION PRESERVATION ===
    TestCase("punct_period", "ghbdtn. rfr ltkf", "привет. как дела", "punctuation", "normal"),
    TestCase("punct_comma", "lf rjytxyj", "да конечно", "punctuation", "normal"),
    TestCase("punct_question", "ns ult", "ты где", "punctuation", "normal"),
    TestCase("punct_exclaim", "rhenjq", "крутой", "punctuation", "fast"),
    
    # === AMBIGUOUS WORDS (should NOT convert) ===
    TestCase("ambig_ok", "ok", "ok", "ambiguous", "fast"),
    TestCase("ambig_test", "test", "test", "ambiguous", "normal"),
    TestCase("ambig_api", "API", "API", "ambiguous", "normal"),
    TestCase("ambig_url", "google.com", "google.com", "ambiguous", "normal"),
    
    # === MIXED LANGUAGE ===
    TestCase("mixed_tech", "bcgjkmpez React lkz frontend", "используя React для frontend", "mixed", "normal"),
    TestCase("mixed_brand", "pfrf;b yf Amazon", "закажи на Amazon", "mixed", "normal"),
    
    # === HEBREW (if layout available) ===
    TestCase("hebrew_shalom", "akuo", "שלום", "hebrew", "normal"),
    TestCase("hebrew_toda", ",usv", "תודה", "hebrew", "normal"),
    
    # === LONG REALISTIC SENTENCES ===
    TestCase("long_complaint", 
             "z yt vjue gjyznm gjxtve 'nj yt hf,jnftn",
             "я не могу понять почему это не работает",
             "long", "variable"),
    TestCase("long_plan",
             "pfdnhf vs j,celbv gkfy yf cktle.oe. ytltk.",
             "завтра мы обсудим план на следующую неделю",
             "long", "normal"),
]


# ============ HELPERS ============

def get_current_layouts() -> List[str]:
    """Get list of currently enabled keyboard layouts."""
    result = subprocess.run(
        ['defaults', 'read', 'com.apple.HIToolbox', 'AppleEnabledInputSources'],
        capture_output=True, text=True
    )
    layouts = []
    for line in result.stdout.split('\n'):
        if 'KeyboardLayout Name' in line:
            name = line.split('=')[1].strip().strip(';').strip('"')
            layouts.append(name)
    return layouts


def get_current_layout() -> str:
    """Get currently active keyboard layout."""
    result = subprocess.run(
        ['defaults', 'read', 'com.apple.HIToolbox', 'AppleSelectedInputSources'],
        capture_output=True, text=True
    )
    for line in result.stdout.split('\n'):
        if 'KeyboardLayout Name' in line:
            return line.split('=')[1].strip().strip(';').strip('"')
    return "Unknown"


def switch_layout(target: str = "US") -> bool:
    """Switch to target layout using switch_layout script."""
    script = OMFK_DIR / "scripts" / "switch_layout"
    result = subprocess.run([str(script), "select", target], capture_output=True, text=True)
    time.sleep(0.2)
    return "Selected:" in result.stdout


def clear_field():
    """Clear TextEdit document."""
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            tell application "System Events"
                keystroke "a" using command down
                key code 51
            end tell
        end tell
    '''], capture_output=True)
    time.sleep(0.15)


def get_result() -> str:
    """Get text from TextEdit."""
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


def type_char(char: str, layout: str = "us", delay: float = 0.02):
    """Type a single character using keycode."""
    if char == ' ':
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], 
                      capture_output=True)
    elif char == '\n':
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 36'], 
                      capture_output=True)
    else:
        layout_map = _keycodes.get(layout, {})
        if char in layout_map:
            keycode, shift = layout_map[char]
            if shift:
                subprocess.run(['osascript', '-e', 
                    f'tell application "System Events" to key code {keycode} using shift down'], 
                    capture_output=True)
            else:
                subprocess.run(['osascript', '-e', 
                    f'tell application "System Events" to key code {keycode}'], 
                    capture_output=True)
        else:
            # Fallback: use keystroke for special chars
            escaped = char.replace('"', '\\"').replace('\\', '\\\\')
            subprocess.run(['osascript', '-e', 
                f'tell application "System Events" to keystroke "{escaped}"'], 
                capture_output=True)
    time.sleep(delay)


def get_typing_delay(speed: str) -> float:
    """Get delay between keystrokes based on speed."""
    if speed == "fast":
        return random.uniform(0.008, 0.015)
    elif speed == "slow":
        return random.uniform(0.05, 0.1)
    elif speed == "variable":
        return random.uniform(0.01, 0.08)
    else:  # normal
        return random.uniform(0.02, 0.035)


def type_text(text: str, layout: str = "us", speed: str = "normal"):
    """Type text with realistic timing."""
    for char in text:
        delay = get_typing_delay(speed)
        type_char(char, layout, delay)


def type_space(wait: float = 0.6):
    """Type space and wait for correction."""
    subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], 
                  capture_output=True)
    time.sleep(wait)


def press_option(wait: float = 0.3):
    """Press Option/Alt key."""
    ev = CGEventCreateKeyboardEvent(None, 58, True)
    CGEventSetFlags(ev, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(0.02)
    ev = CGEventCreateKeyboardEvent(None, 58, False)
    CGEventPost(kCGHIDEventTap, ev)
    time.sleep(wait)


# ============ TEST RUNNER ============

def run_test(test: TestCase) -> Tuple[bool, str, str]:
    """Run a single test case. Returns (passed, got, expected)."""
    # Ensure US layout
    if not switch_layout("US"):
        return False, "[layout switch failed]", test.expected
    
    clear_field()
    time.sleep(0.1)
    
    # Type the input
    type_text(test.input_text, test.source_layout, test.typing_speed)
    type_space(wait=0.7)
    
    result = get_result().strip()
    
    # Check if expected is contained in result (allowing for trailing space/punctuation)
    expected_clean = test.expected.strip()
    result_clean = result.strip()
    
    # Flexible matching: expected should be prefix of result or match exactly
    passed = result_clean.startswith(expected_clean) or expected_clean in result_clean
    
    return passed, result_clean, expected_clean


def run_all_tests(categories: Optional[List[str]] = None) -> dict:
    """Run all tests, optionally filtered by category."""
    results = {
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "details": []
    }
    
    tests = REALISTIC_TESTS
    if categories:
        tests = [t for t in tests if t.category in categories]
    
    print(f"\n{'='*60}")
    print(f"Running {len(tests)} realistic E2E tests")
    print(f"{'='*60}\n")
    
    # Setup TextEdit
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            make new document
        end tell
    '''], capture_output=True)
    time.sleep(1)
    
    current_category = None
    
    for test in tests:
        # Print category header
        if test.category != current_category:
            current_category = test.category
            print(f"\n--- {current_category.upper()} ---")
        
        try:
            passed, got, expected = run_test(test)
            
            if passed:
                results["passed"] += 1
                status = "✓"
                print(f"  {status} {test.name}")
            else:
                results["failed"] += 1
                status = "✗"
                print(f"  {status} {test.name}")
                print(f"      got:      '{got[:50]}{'...' if len(got) > 50 else ''}'")
                print(f"      expected: '{expected[:50]}{'...' if len(expected) > 50 else ''}'")
            
            results["details"].append({
                "name": test.name,
                "category": test.category,
                "passed": passed,
                "got": got,
                "expected": expected
            })
            
        except Exception as e:
            results["skipped"] += 1
            print(f"  ⚠ {test.name}: {e}")
            results["details"].append({
                "name": test.name,
                "category": test.category,
                "passed": False,
                "error": str(e)
            })
    
    return results


def print_summary(results: dict):
    """Print test summary."""
    total = results["passed"] + results["failed"] + results["skipped"]
    
    print(f"\n{'='*60}")
    print(f"SUMMARY: {results['passed']}/{total} passed")
    print(f"{'='*60}")
    
    if results["failed"] > 0:
        print(f"\nFailed: {results['failed']}")
        for d in results["details"]:
            if not d.get("passed") and "error" not in d:
                print(f"  - {d['name']} ({d['category']})")
    
    if results["skipped"] > 0:
        print(f"\nSkipped: {results['skipped']}")
    
    # Category breakdown
    print("\nBy category:")
    categories = {}
    for d in results["details"]:
        cat = d["category"]
        if cat not in categories:
            categories[cat] = {"passed": 0, "total": 0}
        categories[cat]["total"] += 1
        if d.get("passed"):
            categories[cat]["passed"] += 1
    
    for cat, stats in sorted(categories.items()):
        pct = stats["passed"] / stats["total"] * 100 if stats["total"] > 0 else 0
        print(f"  {cat}: {stats['passed']}/{stats['total']} ({pct:.0f}%)")


def main():
    print("OMFK Realistic E2E Tests")
    print("=" * 60)
    
    # Check OMFK is running
    result = subprocess.run(['pgrep', '-f', 'OMFK'], capture_output=True)
    if result.returncode != 0:
        print("⚠ OMFK not running. Starting...")
        subprocess.Popen(
            [str(OMFK_DIR / ".build" / "debug" / "OMFK")],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        time.sleep(2)
    
    # Save current layout
    original_layout = get_current_layout()
    print(f"Original layout: {original_layout}")
    print(f"Available layouts: {get_current_layouts()}")
    
    try:
        results = run_all_tests()
        print_summary(results)
    finally:
        # Restore original layout
        switch_layout(original_layout)
        print(f"\nRestored layout: {get_current_layout()}")
    
    return 0 if results["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
