#!/usr/bin/env python3
"""
OMFK Matrix Test Runner

Runs layout conversion tests against OMFK with debug logging.
"""

import json
import subprocess
import time
import sys
import os
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
LOG_FILE = Path.home() / ".omfk" / "debug.log"

KEY_OPTION = 58
KEY_DELETE = 51


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


def cmd_key(keycode):
    press_key(keycode, kCGEventFlagMaskCommand)


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


def clear_field():
    cmd_key(0)  # Cmd+A
    time.sleep(0.05)
    press_key(KEY_DELETE)
    time.sleep(0.05)


def run_test(typed: str, expected: str) -> tuple[bool, str]:
    clear_field()
    time.sleep(0.2)
    
    clipboard_set(typed)
    cmd_key(9)  # Cmd+V
    time.sleep(0.2)
    
    cmd_key(0)  # Cmd+A
    time.sleep(0.1)
    
    press_option()
    time.sleep(0.8)
    
    result = get_text().strip()
    return result == expected, result


def start_omfk():
    """Start OMFK with debug logging."""
    subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    time.sleep(0.3)
    
    # Clear log
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.write_text("")
    
    # Build
    print("Building OMFK...")
    r = subprocess.run(["swift", "build"], cwd=OMFK_DIR, capture_output=True)
    if r.returncode != 0:
        print(f"Build failed: {r.stderr.decode()}")
        return False
    
    # Start with debug
    env = os.environ.copy()
    env["OMFK_DEBUG_LOG"] = "1"
    subprocess.Popen(
        [str(OMFK_DIR / ".build/debug/OMFK")],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(1.5)
    print("OMFK started with OMFK_DEBUG_LOG=1")
    return True


def load_tests():
    """Generate test matrix inline."""
    with open(OMFK_DIR / "OMFK/Sources/Resources/layouts.json") as f:
        data = json.load(f)
    
    words = {
        "en": ["hello", "world", "test", "code"],
        "ru": ["привет", "текст", "слово", "код"],
        "he": ["שלום", "טקסט", "בית", "יום"],
    }
    
    layouts = {
        "en": ["us", "abc", "british", "usinternational_pc"],
        "ru": ["russian", "russianwin", "russian_phonetic"],
        "he": ["hebrew", "hebrew_pc", "hebrew_qwerty"],
    }
    
    def char_to_key(layout_id):
        m = {}
        for key, lays in data["map"].items():
            if layout_id in lays:
                for mod, ch in lays[layout_id].items():
                    if ch and ch not in m:
                        m[ch] = (key, mod)
        return m
    
    def convert(word, from_lay, to_lay):
        fm = char_to_key(from_lay)
        result = []
        for c in word:
            if c in fm:
                key, mod = fm[c]
                tc = data["map"].get(key, {}).get(to_lay, {}).get(mod)
                if tc:
                    result.append(tc)
                else:
                    return None
            elif c == " ":
                result.append(c)
            else:
                return None
        return "".join(result)
    
    tests = []
    for tgt_lang, tgt_words in words.items():
        for src_lang, src_lays in layouts.items():
            if src_lang == tgt_lang:
                continue
            for src_lay in src_lays:
                for tgt_lay in layouts[tgt_lang]:
                    for word in tgt_words:
                        typed = convert(word, tgt_lay, src_lay)
                        if typed and typed != word:
                            tests.append({
                                "typed": typed,
                                "expected": word,
                                "src": src_lay,
                                "tgt": tgt_lay,
                                "desc": f"{word} ({tgt_lay}) on {src_lay}",
                            })
    return tests


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    
    print("OMFK Matrix Test Runner")
    print("=" * 70)
    
    tests = load_tests()[:limit]
    print(f"Running {len(tests)} tests\n")
    
    if not start_omfk():
        return 1
    
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
    
    passed = failed = 0
    failures = []
    
    for i, t in enumerate(tests):
        ok, actual = run_test(t["typed"], t["expected"])
        
        if ok:
            passed += 1
            print(f"✓ [{i+1}] {t['desc']}")
        else:
            failed += 1
            print(f"✗ [{i+1}] {t['desc']}")
            print(f"    '{t['typed']}' → '{actual}' (expected '{t['expected']}')")
            failures.append(t | {"actual": actual})
        
        time.sleep(0.2)
    
    print("\n" + "=" * 70)
    print(f"RESULTS: {passed}/{len(tests)} passed")
    
    if failures:
        print("\nFailures by source layout:")
        by_src = {}
        for f in failures:
            by_src[f["src"]] = by_src.get(f["src"], 0) + 1
        for src, cnt in sorted(by_src.items(), key=lambda x: -x[1]):
            print(f"  {src}: {cnt}")
    
    # Show last log entries
    print("\n" + "=" * 70)
    print("Last 20 log entries:")
    if LOG_FILE.exists():
        for line in LOG_FILE.read_text().strip().split("\n")[-20:]:
            print(f"  {line}")
    
    subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'], capture_output=True)
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    exit(main())
