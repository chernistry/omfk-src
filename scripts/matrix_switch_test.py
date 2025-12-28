#!/usr/bin/env python3
"""
OMFK Matrix Test - tests different layout combinations.
Switches system layouts, restarts OMFK, runs tests, restores original.
"""

import json
import subprocess
import time
import sys
import os
from pathlib import Path

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
SWITCH_TOOL = OMFK_DIR / "scripts/switch_layout"
LOG_FILE = Path.home() / ".omfk" / "debug.log"

with open(OMFK_DIR / "OMFK/Sources/Resources/layouts.json") as f:
    LAYOUT_DATA = json.load(f)

# Layout combos to test: (en, ru, he, description)
# Start with combos that were FAILING
TEST_COMBOS = [
    # Mac layouts (likely to fail with current setup)
    ("US", "Russian", "Hebrew", "US + RU Mac + HE Mac"),
    ("US", "RussianWin", "Hebrew", "US + RU PC + HE Mac"),
    ("US", "RussianWin", "Hebrew-PC", "US + RU PC + HE PC"),
    ("US", "Russian-Phonetic", "Hebrew-QWERTY", "US + RU Phonetic + HE QWERTY"),
    # Baseline (should work)
    ("USInternational-PC", "RussianWin", "Hebrew-QWERTY", "US Int PC + RU PC + HE QWERTY"),
]

WORDS = {
    "en": ["hello", "world", "test"],
    "ru": ["привет", "текст", "код"],
    "he": ["שלום", "בית", "יום"],
}

KEY_OPTION, KEY_DELETE = 58, 51


def run_switch(cmd, layout=None):
    """Run switch_layout tool."""
    args = [str(SWITCH_TOOL), cmd]
    if layout:
        args.append(layout)
    r = subprocess.run(args, capture_output=True, text=True)
    return r.stdout.strip(), r.returncode == 0


def get_enabled_layouts():
    """Get currently enabled layout IDs."""
    out, ok = run_switch("list")
    if not ok:
        return []
    layouts = []
    for line in out.split("\n"):
        if line.strip().startswith("com.apple.keylayout."):
            layout_id = line.split()[0].replace("com.apple.keylayout.", "")
            layouts.append(layout_id)
    return layouts


def enable_layout(layout_id):
    out, ok = run_switch("enable", layout_id)
    return ok


def disable_layout(layout_id):
    out, ok = run_switch("disable", layout_id)
    return ok


def select_layout(layout_id):
    out, ok = run_switch("select", layout_id)
    return ok


def set_layouts(en, ru, he):
    """Set exactly these 3 layouts (disable others, enable these)."""
    current = get_enabled_layouts()
    target = [en, ru, he]
    
    # Disable layouts not in target
    for lay in current:
        if lay not in target:
            disable_layout(lay)
    
    # Enable target layouts
    for lay in target:
        if lay not in current:
            enable_layout(lay)
    
    time.sleep(0.3)
    return get_enabled_layouts()


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


def get_text():
    sw = AXUIElementCreateSystemWide()
    err, el = AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute, None)
    if err == 0 and el:
        err, val = AXUIElementCopyAttributeValue(el, kAXValueAttribute, None)
        if err == 0 and val:
            return str(val)
    return ""


def start_omfk():
    subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    time.sleep(0.3)
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    
    env = os.environ.copy()
    env["OMFK_DEBUG_LOG"] = "1"
    subprocess.Popen([str(OMFK_DIR / ".build/debug/OMFK")], env=env,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.2)


def layout_id_to_internal(layout_id):
    """Convert Apple layout ID to internal ID used in layouts.json."""
    mapping = {
        "US": "us", "ABC": "abc", "British": "british",
        "USInternational-PC": "usinternational_pc",
        "Russian": "russian", "RussianWin": "russianwin",
        "Russian-Phonetic": "russian_phonetic",
        "Hebrew": "hebrew", "Hebrew-PC": "hebrew_pc",
        "Hebrew-QWERTY": "hebrew_qwerty",
    }
    return mapping.get(layout_id, layout_id.lower().replace("-", "_"))


def char_to_key(layout_id):
    m = {}
    for key, lays in LAYOUT_DATA["map"].items():
        if layout_id in lays:
            for mod, ch in lays[layout_id].items():
                if ch and ch not in m:
                    m[ch] = (key, mod)
    return m


def convert_word(word, from_lay, to_lay):
    fm = char_to_key(from_lay)
    result = []
    for c in word:
        if c in fm:
            key, mod = fm[c]
            tc = LAYOUT_DATA["map"].get(key, {}).get(to_lay, {}).get(mod)
            if tc:
                result.append(tc)
            else:
                return None
        elif c == " ":
            result.append(c)
        else:
            return None
    return "".join(result)


def run_test(typed, expected):
    cmd_key(0); time.sleep(0.05)  # Cmd+A
    press_key(KEY_DELETE); time.sleep(0.1)
    
    clipboard_set(typed)
    cmd_key(9); time.sleep(0.15)  # Cmd+V
    cmd_key(0); time.sleep(0.1)   # Cmd+A
    
    press_option()
    time.sleep(0.8)
    
    return get_text().strip()


def test_combo(en, ru, he, desc):
    print(f"\n{'='*60}")
    print(f"Testing: {desc}")
    
    # Set layouts
    actual = set_layouts(en, ru, he)
    print(f"  Layouts set: {actual}")
    
    # Restart OMFK
    start_omfk()
    
    # Select EN layout for typing
    select_layout(en)
    time.sleep(0.2)
    
    # Convert layout IDs to internal format
    en_int = layout_id_to_internal(en)
    ru_int = layout_id_to_internal(ru)
    he_int = layout_id_to_internal(he)
    
    # Generate tests
    tests = []
    
    # RU words typed on EN
    for word in WORDS["ru"]:
        typed = convert_word(word, ru_int, en_int)
        if typed:
            tests.append((typed, word, f"RU '{word}' on EN"))
    
    # EN words typed on RU
    for word in WORDS["en"]:
        typed = convert_word(word, en_int, ru_int)
        if typed:
            tests.append((typed, word, f"EN '{word}' on RU"))
    
    # HE words typed on EN
    for word in WORDS["he"]:
        typed = convert_word(word, he_int, en_int)
        if typed:
            tests.append((typed, word, f"HE '{word}' on EN"))
    
    passed = 0
    for typed, expected, test_desc in tests:
        actual = run_test(typed, expected)
        ok = actual == expected
        if ok:
            passed += 1
            print(f"  ✓ {test_desc}")
        else:
            print(f"  ✗ {test_desc}: '{typed}' → '{actual}' (expected '{expected}')")
        time.sleep(0.15)
    
    return passed, len(tests)


def main():
    print("OMFK Layout Combo Test")
    print("=" * 60)
    
    # Build OMFK first
    print("Building OMFK...")
    subprocess.run(["swift", "build"], cwd=OMFK_DIR, capture_output=True)
    
    # Save original layouts
    original = get_enabled_layouts()
    print(f"Original layouts: {original}")
    
    # Open TextEdit
    subprocess.run(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    subprocess.run(["osascript", "-e", '''
        tell application "TextEdit"
            activate
            if (count of documents) = 0 then make new document
        end tell
    '''], capture_output=True)
    time.sleep(0.3)
    
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(TEST_COMBOS)
    results = []
    
    try:
        for en, ru, he, desc in TEST_COMBOS[:limit]:
            p, t = test_combo(en, ru, he, desc)
            results.append((desc, p, t))
    finally:
        # Restore original layouts
        print(f"\n{'='*60}")
        print("Restoring original layouts...")
        set_layouts(*original[:3] if len(original) >= 3 else original + ["US"]*(3-len(original)))
        print(f"Restored: {get_enabled_layouts()}")
        
        subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
        subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'], capture_output=True)
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    total_p, total_t = 0, 0
    for desc, p, t in results:
        pct = 100*p//t if t else 0
        status = "✓" if p == t else "✗"
        print(f"{status} {desc}: {p}/{t} ({pct}%)")
        total_p += p
        total_t += t
    
    print(f"\nTotal: {total_p}/{total_t}")
    return 0 if total_p == total_t else 1


if __name__ == "__main__":
    exit(main())
