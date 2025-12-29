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
import argparse
from pathlib import Path
from datetime import datetime

from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskAlternate, kCGEventFlagMaskCommand, kCGEventFlagMaskShift,
    CGEventSourceCreate, kCGEventSourceStateHIDSystemState
)
from ApplicationServices import (
    AXUIElementCreateSystemWide, AXUIElementCopyAttributeValue,
    kAXFocusedUIElementAttribute, kAXValueAttribute
)
from AppKit import NSPasteboard, NSStringPboardType

OMFK_DIR = Path(__file__).parent.parent
TESTS_FILE = OMFK_DIR / "tests/test_cases.json"
LOG_FILE = Path.home() / ".omfk" / "debug.log"
KEYCODES_FILE = Path(__file__).parent / "keycodes.json"
SWITCH_LAYOUT = OMFK_DIR / "scripts/switch_layout"

KEY_OPTION, KEY_DELETE, KEY_SPACE = 58, 51, 49
BUNDLE_ID = "com.chernistry.omfk"

# Load keycodes for real typing
_keycodes = {}
if KEYCODES_FILE.exists():
    with open(KEYCODES_FILE) as f:
        _keycodes = json.load(f)

# Layout Apple IDs for switching
LAYOUT_APPLE_IDS = {
    "us": "com.apple.keylayout.US",
    "russianwin": "com.apple.keylayout.RussianWin",
    "russian": "com.apple.keylayout.Russian",
    "russian_phonetic": "com.apple.keylayout.Russian-Phonetic",
    "hebrew": "com.apple.keylayout.Hebrew",
    "hebrew_qwerty": "com.apple.keylayout.Hebrew-QWERTY",
    "hebrew_pc": "com.apple.keylayout.Hebrew-PC",
}

BASE_ACTIVE_LAYOUTS = {
    "en": "us",
    "ru": "russian",      # Mac Russian (not PC)
    "he": "hebrew",       # Mac Hebrew (not QWERTY)
}

# Popular layout combinations to test
LAYOUT_COMBOS = [
    {"en": "us", "ru": "russian", "he": "hebrew", "name": "Mac defaults"},
    {"en": "us", "ru": "russianwin", "he": "hebrew", "name": "US + RU-PC + HE-Mac"},
    {"en": "us", "ru": "russianwin", "he": "hebrew_qwerty", "name": "US + RU-PC + HE-QWERTY"},
    {"en": "us", "ru": "russian_phonetic", "he": "hebrew", "name": "US + RU-Phonetic + HE-Mac"},
]

# Short names for switch_layout tool
LAYOUT_SHORT_NAMES = {
    "us": "US",
    "russianwin": "RussianWin",
    "russian": "Russian",
    "russian_phonetic": "Russian-Phonetic",
    "hebrew": "Hebrew",
    "hebrew_qwerty": "Hebrew-QWERTY",
    "hebrew_pc": "Hebrew-PC",
}


def get_enabled_system_layouts() -> list[str]:
    """Get currently enabled system layout short names (matching LAYOUT_SHORT_NAMES values)."""
    r = subprocess.run([str(SWITCH_LAYOUT), "list"], capture_output=True, text=True)
    layouts = []
    for line in r.stdout.split("\n"):
        if "com.apple.keylayout." in line:
            # Extract short name: com.apple.keylayout.Hebrew-QWERTY -> Hebrew-QWERTY
            layout_name = line.split()[0].replace("com.apple.keylayout.", "")
            layouts.append(layout_name)
    return layouts


def enable_system_layout(layout_id: str) -> bool:
    """Enable a system layout."""
    name = LAYOUT_SHORT_NAMES.get(layout_id, layout_id)
    r = subprocess.run([str(SWITCH_LAYOUT), "enable", name], capture_output=True)
    return r.returncode == 0


def disable_system_layout(layout_id: str) -> bool:
    """Disable a system layout."""
    name = LAYOUT_SHORT_NAMES.get(layout_id, layout_id)
    r = subprocess.run([str(SWITCH_LAYOUT), "disable", name], capture_output=True)
    return r.returncode == 0


def set_system_layouts(en: str, ru: str, he: str):
    """Set exactly these 3 system layouts (disable others, enable these)."""
    current = get_enabled_system_layouts()
    target = [LAYOUT_SHORT_NAMES.get(en, en), 
              LAYOUT_SHORT_NAMES.get(ru, ru), 
              LAYOUT_SHORT_NAMES.get(he, he)]
    
    print(f"  Current: {current}, Target: {target}", flush=True)
    
    # Disable layouts not in target
    for lay in current:
        if lay not in target:
            ok = disable_system_layout(lay)
            print(f"  Disable {lay}: {'OK' if ok else 'FAILED'}", flush=True)
    
    # Enable target layouts
    for lay in target:
        if lay not in current:
            ok = enable_system_layout(lay)
            print(f"  Enable {lay}: {'OK' if ok else 'FAILED'}", flush=True)
    
    time.sleep(0.15)
    result = get_enabled_system_layouts()
    print(f"  Final layouts: {result}", flush=True)
    return result


def write_active_layouts(layouts):
    """Persist activeLayouts for OMFK (picked up on app start)."""
    if not layouts:
        layouts = BASE_ACTIVE_LAYOUTS

    cmd = ["defaults", "write", BUNDLE_ID, "activeLayouts", "-dict"]
    for k, v in sorted(layouts.items()):
        cmd.extend([str(k), str(v)])
    subprocess.run(cmd, capture_output=True)


def stop_omfk():
    subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    time.sleep(0.15)


# ============== REAL TYPING FUNCTIONS ==============

def switch_system_layout(layout_id: str) -> bool:
    """Switch macOS input source to given layout."""
    short_names = {
        "us": "US",
        "russianwin": "RussianWin", 
        "russian": "Russian",
        "russian_phonetic": "Russian-Phonetic",
        "hebrew": "Hebrew",
        "hebrew_qwerty": "Hebrew-QWERTY",
        "hebrew_pc": "Hebrew-PC",
    }
    name = short_names.get(layout_id, layout_id)
    # Use start_new_session to prevent terminal focus stealing
    result = subprocess.run(
        [str(SWITCH_LAYOUT), "select", name], 
        capture_output=True, 
        timeout=2,
        start_new_session=True
    )
    time.sleep(0.15)
    return result.returncode == 0


def detect_input_layout(text: str) -> str | None:
    """Detect which ENABLED layout can type all chars in text."""
    # Get currently enabled system layouts
    enabled = get_enabled_system_layouts()
    # Map short names to our layout IDs
    enabled_ids = set()
    for lay in enabled:
        # RussianWin -> russianwin, Hebrew-QWERTY -> hebrew_qwerty
        lay_id = lay.lower().replace("-", "_")
        enabled_ids.add(lay_id)
    
    # Priority order, but only check enabled layouts
    for layout in ["us", "russianwin", "hebrew", "hebrew_qwerty", "russian_phonetic", "russian", "hebrew_pc"]:
        if layout not in enabled_ids:
            continue
        layout_map = _keycodes.get(layout, {})
        if all(c in layout_map or c in " \t\n" for c in text):
            return layout
    return None


def type_char_real(char: str, layout: str, delay: float = 0.012) -> bool:
    """Type a single character via AppleScript key code."""
    if char == ' ':
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
        time.sleep(delay)
        return True
    
    layout_map = _keycodes.get(layout, {})
    if char not in layout_map:
        return False
    
    keycode, shift = layout_map[char]
    if shift:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {keycode} using shift down'], capture_output=True)
    else:
        subprocess.run(['osascript', '-e', f'tell application "System Events" to key code {keycode}'], capture_output=True)
    time.sleep(delay)
    return True


def type_string_real(text: str, layout: str, char_delay: float = 0.008) -> tuple[bool, list[str]]:
    """Type string via AppleScript System Events char by char."""
    for char in text:
        type_char_real(char, layout, char_delay)
    return True, []


def type_word_and_space_real(word: str, layout: str, char_delay: float = 0.008, space_wait: float = 0.4) -> bool:
    """Type word + space via AppleScript key codes, wait for OMFK to process."""
    type_string_real(word, layout, char_delay)
    # Type space via key code
    subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
    time.sleep(space_wait)
    return True


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
    time.sleep(0.1)
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
    time.sleep(0.08)
    press_key(KEY_DELETE)
    time.sleep(0.08)


def type_and_space(text):
    """Type text via paste, then press space."""
    clipboard_set(text)
    cmd_key(9)  # Cmd+V
    time.sleep(0.15)
    press_key(KEY_SPACE)
    time.sleep(0.15)  # Wait for OMFK


def select_all_and_correct():
    """Select all and press Option to correct."""
    cmd_key(0)  # Cmd+A
    time.sleep(0.15)
    press_option()
    time.sleep(0.15)


def get_result():
    """Get current text from TextEdit via AppleScript (more reliable than AX API)."""
    r = subprocess.run(['osascript', '-e', 
        'tell application "TextEdit" to get text of front document'],
        capture_output=True, text=True)
    return r.stdout.strip()


def run_single_test_real(input_text: str, expected: str) -> tuple[bool, str]:
    """Run test with REAL typing simulation."""
    # Detect layout for input
    layout = detect_input_layout(input_text)
    if not layout:
        return False, f"[no layout for: {input_text[:20]}]"
    
    # Switch system layout FIRST
    if not switch_system_layout(layout):
        return False, f"[failed to switch to {layout}]"
    
    # Activate TextEdit and verify
    subprocess.run(["osascript", "-e", 'tell application "TextEdit" to activate'], capture_output=True)
    time.sleep(0.1)
    check_focus()
    
    clear_field()
    time.sleep(0.15)
    
    # Type word(s) with spaces
    words = input_text.split()
    for i, word in enumerate(words):
        for char in word:
            type_char_real(char, layout)
        
        check_focus()
        
        # Type space via key code (so OMFK sees it)
        subprocess.run(['osascript', '-e', 'tell application "System Events" to key code 49'], capture_output=True)
        
        if i == len(words) - 1:
            time.sleep(0.15)  # Wait for OMFK after last word
        else:
            time.sleep(0.1)
    
    result = get_result().rstrip()
    return result == expected, result


def start_omfk():
    stop_omfk()
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    
    env = os.environ.copy()
    env["OMFK_DEBUG_LOG"] = "1"
    # Don't set OMFK_DISABLE_LAYOUT_AUTODETECT - it breaks conversion
    subprocess.Popen([str(OMFK_DIR / ".build/debug/OMFK")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    time.sleep(1.0)  # Give OMFK more time to start and read config


def open_textedit():
    subprocess.run(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    subprocess.run(["osascript", "-e", '''
        tell application "TextEdit"
            activate
            if (count of documents) = 0 then make new document
        end tell
    '''], capture_output=True)
    time.sleep(0.15)
    
    # Disable macOS autocorrect for this session
    subprocess.run(["defaults", "write", "-g", "NSAutomaticSpellingCorrectionEnabled", "-bool", "false"], capture_output=True)
    subprocess.run(["defaults", "write", "-g", "NSAutomaticTextCompletionEnabled", "-bool", "false"], capture_output=True)
    subprocess.run(["defaults", "write", "-g", "NSAutomaticQuoteSubstitutionEnabled", "-bool", "false"], capture_output=True)
    subprocess.run(["defaults", "write", "-g", "NSAutomaticDashSubstitutionEnabled", "-bool", "false"], capture_output=True)


def close_textedit():
    subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'], capture_output=True)
    # Restore macOS autocorrect
    subprocess.run(["defaults", "write", "-g", "NSAutomaticSpellingCorrectionEnabled", "-bool", "true"], capture_output=True)
    subprocess.run(["defaults", "write", "-g", "NSAutomaticTextCompletionEnabled", "-bool", "true"], capture_output=True)


def get_frontmost_app() -> str:
    """Get name of frontmost application."""
    r = subprocess.run(["osascript", "-e", 
        'tell application "System Events" to get name of first process whose frontmost is true'],
        capture_output=True, text=True)
    return r.stdout.strip()


class FocusLostError(Exception):
    """Raised when TextEdit loses focus."""
    pass


def check_focus():
    """Check if TextEdit is focused. Raise FocusLostError if not."""
    app = get_frontmost_app()
    if app != "TextEdit":
        raise FocusLostError(f"Focus lost to: {app}")


def ensure_textedit_focused():
    """Ensure TextEdit is frontmost. Pause and wait if not."""
    while True:
        app = get_frontmost_app()
        if app == "TextEdit":
            return
        print(f"\n⚠️  Focus lost! Current app: {app}")
        print("    Switch to TextEdit and press Enter to continue...")
        input()
        subprocess.run(["osascript", "-e", 'tell application "TextEdit" to activate'], capture_output=True)
        time.sleep(0.15)


# ============== TEST RUNNERS ==============

def run_single_test(input_text, expected):
    """Run single correction test."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)  # Paste
    time.sleep(0.08)
    
    cmd_key(0)  # Select all
    time.sleep(0.15)
    
    press_option()
    time.sleep(0.15)
    
    result = get_result()
    return result == expected, result


def run_context_boost_test(words, expected_final):
    """Test word-by-word typing with context boost.
    
    Simulates typing words one by one, with OMFK correcting after each.
    The key test: first ambiguous word should be corrected when second word confirms language.
    """
    # Ensure US layout before typing
    switch_system_layout("us")
    time.sleep(0.5)  # Give more time for layout switch
    
    clear_field()
    time.sleep(0.15)
    
    # Type words one by one with spaces (real typing, not paste)
    for word in words:
        type_word_and_space_real(word, "us", char_delay=0.012, space_wait=0.5)
    
    time.sleep(0.2)
    result = get_result().rstrip()
    return result == expected_final, result


def run_cycling_test(input_text, alt_presses, expected_sequence=None):
    """Test Alt cycling through alternatives."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.08)
    cmd_key(0)
    time.sleep(0.15)
    
    results = [get_result()]
    
    for i in range(alt_presses):
        press_option()
        time.sleep(0.15)
        results.append(get_result())
    
    if expected_sequence:
        # Check if results match expected sequence
        match = all(r == e for r, e in zip(results, expected_sequence) if e is not None)
        return match, results
    
    return True, results  # Just verify no crash


def run_stress_cycling(input_text, times, delay_ms=50):
    """Rapid Alt spam test."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.08)
    cmd_key(0)
    time.sleep(0.15)
    
    for _ in range(times):
        press_option()
        time.sleep(delay_ms / 1000)
    
    time.sleep(0.15)
    result = get_result()
    return len(result) > 0, result


def run_performance_test(input_text, expected, max_time_ms):
    """Test correction speed."""
    clear_field()
    time.sleep(0.08)
    
    clipboard_set(input_text)
    cmd_key(9)
    time.sleep(0.08)
    cmd_key(0)
    time.sleep(0.15)
    
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
    parser = argparse.ArgumentParser(description="OMFK Comprehensive Test Runner")
    parser.add_argument("categories", nargs="*", help="Test categories to run (empty = all)")
    parser.add_argument("--real-typing", "-r", action="store_true", 
                        help="Use real keyboard typing (char-by-char + space) instead of paste+Option")
    parser.add_argument("--combo", "-c", type=int, default=0,
                        help="Layout combo index (0=Mac defaults, 1=RU-PC, 2=HE-QWERTY, 3=RU-Phonetic)")
    parser.add_argument("--all-combos", "-a", action="store_true",
                        help="Run tests on all layout combinations")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    args = parser.parse_args()
    
    real_typing_mode = args.real_typing
    categories = args.categories if args.categories else None
    verbose = args.verbose
    
    mode_str = "REAL TYPING" if real_typing_mode else "SELECT+OPTION"
    print(f"OMFK Comprehensive Test Runner [{mode_str}]")
    print("=" * 70)
    
    # Load test cases
    with open(TESTS_FILE) as f:
        tests = json.load(f)
    
    # Build OMFK
    print("Building OMFK...")
    r = subprocess.run(["swift", "build"], cwd=OMFK_DIR, capture_output=True)
    if r.returncode != 0:
        print("Build failed!")
        return 1
    
    # Save original user layouts to restore later
    original_layouts = get_enabled_system_layouts()
    print(f"Saved original layouts: {original_layouts}")
    
    # Select layout combo
    combo_idx = args.combo if not args.all_combos else 0
    combo = LAYOUT_COMBOS[combo_idx % len(LAYOUT_COMBOS)]
    base_layouts = {"en": combo["en"], "ru": combo["ru"], "he": combo["he"]}
    print(f"Using layout combo: {combo['name']}")
    
    # Set up initial system layouts
    print("Setting up system layouts...")
    set_system_layouts(base_layouts["en"], base_layouts["ru"], base_layouts["he"])
    
    # Ensure deterministic base layout config (picked up on app start)
    write_active_layouts(base_layouts)

    start_omfk()
    open_textedit()
    
    # Verify TextEdit is ready
    time.sleep(0.5)
    ensure_textedit_focused()
    print("✓ TextEdit focused and ready")
    
    total_passed = 0
    total_failed = 0
    results = []
    current_layouts = dict(base_layouts)

    def ensure_layouts_for_case(case):
        nonlocal current_layouts
        layouts = (case.get("settings") or {}).get("activeLayouts") or base_layouts
        if layouts != current_layouts:
            print(f"\n↺ Switching activeLayouts: {current_layouts} -> {layouts}")
            
            # Update SYSTEM layouts (enable/disable)
            set_system_layouts(layouts.get("en", "us"), 
                              layouts.get("ru", "russian"), 
                              layouts.get("he", "hebrew"))
            
            # Update OMFK config
            write_active_layouts(layouts)
            start_omfk()
            current_layouts = dict(layouts)
            
            # Restore focus to TextEdit after OMFK restart
            subprocess.run(["osascript", "-e", 'tell application "TextEdit" to activate'], capture_output=True)
            time.sleep(0.15)

    def run_input_expected_category(key, title):
        nonlocal total_passed, total_failed
        cases = tests.get(key, {}).get("cases", [])
        if not cases:
            return
        print("\n" + "=" * 70)
        print(title)
        print("=" * 70)
        for case in cases:
            ensure_layouts_for_case(case)
            
            try:
                if real_typing_mode:
                    ok, result = run_single_test_real(case["input"], case["expected"])
                else:
                    ok, result = run_single_test(case["input"], case["expected"])
            except FocusLostError as e:
                print(f"\n❌ FOCUS LOST: {e}")
                print("Test aborted. Check which app stole focus.")
                raise
            
            status = "✓" if ok else "✗"
            print(f"{status} {case.get('desc','')}")
            if not ok:
                print(f"    '{case['input']}' → '{result}' (expected '{case['expected']}')")
                total_failed += 1
            else:
                total_passed += 1
            time.sleep(0.1)
    
    try:
        # Single words
        if not categories or "single" in categories or "single_words" in categories:
            run_input_expected_category("single_words", "SINGLE WORDS")
        
        # Paragraphs
        if not categories or "paragraphs" in categories or "real_paragraphs" in categories:
            run_input_expected_category("real_paragraphs", "PARAGRAPHS (REAL)")

        if not categories or "multiline" in categories or "multiline_realistic" in categories:
            run_input_expected_category("multiline_realistic", "MULTILINE (REALISTIC)")

        if not categories or "mixed" in categories or "mixed_language_real" in categories:
            run_input_expected_category("mixed_language_real", "MIXED LANGUAGE (REAL)")

        if not categories or "symbols" in categories or "special_symbols" in categories:
            run_input_expected_category("special_symbols", "SPECIAL SYMBOLS")

        if not categories or "hebrew" in categories or "hebrew_cases" in categories:
            run_input_expected_category("hebrew_cases", "HEBREW CASES")

        if not categories or "punct" in categories or "punctuation_triggers" in categories:
            run_input_expected_category("punctuation_triggers", "PUNCTUATION TRIGGERS")

        if not categories or "typos" in categories or "typos_and_errors" in categories:
            run_input_expected_category("typos_and_errors", "TYPOS AND ERRORS")

        if not categories or "numbers" in categories or "numbers_and_special" in categories:
            run_input_expected_category("numbers_and_special", "NUMBERS AND SPECIALS")

        if not categories or "ambiguous" in categories or "ambiguous_words" in categories:
            run_input_expected_category("ambiguous_words", "AMBIGUOUS WORDS (NEGATIVE)")

        if not categories or "negative" in categories or "negative_should_not_change" in categories:
            run_input_expected_category("negative_should_not_change", "NEGATIVE SHOULD NOT CHANGE")

        if not categories or "edge" in categories or "edge_cases_system" in categories:
            run_input_expected_category("edge_cases_system", "EDGE CASES (SYSTEM)")
        
        # Context boost
        if not categories or "context" in categories or "context_boost_hard" in categories:
            print("\n" + "=" * 70)
            print("CONTEXT BOOST (word-by-word)")
            print("=" * 70)
            context_cases = (tests.get("context_boost_hard") or tests.get("context_boost_realistic") or {}).get("cases", [])
            for case in context_cases:
                ensure_layouts_for_case(case)
                ok, result = run_context_boost_test(case["words"], case["expected_final"])
                status = "✓" if ok else "✗"
                print(f"{status} {case.get('desc','')}")
                if not ok:
                    print(f"    Words: {case['words']}")
                    print(f"    Got: '{result}'")
                    print(f"    Exp: '{case['expected_final']}'")
                    total_failed += 1
                else:
                    total_passed += 1
                time.sleep(0.15)
        
        # Cycling
        if not categories or "cycling" in categories:
            print("\n" + "=" * 70)
            print("ALT CYCLING")
            print("=" * 70)
            for case in tests.get("cycling_tests", {}).get("cases", []):
                ensure_layouts_for_case(case)
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
                time.sleep(0.1)
        
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
                time.sleep(0.1)
        
        # Performance
        if not categories or "perf" in categories:
            print("\n" + "=" * 70)
            print("PERFORMANCE")
            print("=" * 70)
            for case in tests.get("performance_stress", {}).get("cases", []):
                ensure_layouts_for_case(case)
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
        stop_omfk()
        
        # Restore original user layouts
        print(f"\nRestoring original layouts: {original_layouts}")
        current_enabled = get_enabled_system_layouts()
        # Disable layouts that weren't originally enabled
        for lay in current_enabled:
            if lay not in original_layouts:
                disable_system_layout(lay)
        # Enable layouts that were originally enabled
        for lay in original_layouts:
            if lay not in current_enabled:
                enable_system_layout(lay)
    
    # Summary
    print("\n" + "=" * 70)
    print(f"TOTAL: {total_passed} passed, {total_failed} failed")
    print("=" * 70)
    
    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    exit(main())
