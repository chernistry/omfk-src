#!/usr/bin/env python3
"""
OMFK Stress Tester - comprehensive test suite
"""

import subprocess
import time
import os
from pathlib import Path
from AppKit import NSPasteboard, NSStringPboardType, NSRunningApplication
from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap,
    CGEventSetFlags, kCGEventFlagMaskCommand, kCGEventFlagMaskAlternate,
    CGEventSourceCreate, kCGEventSourceStateHIDSystemState
)
from ApplicationServices import (
    AXUIElementCreateSystemWide, AXUIElementCopyAttributeValue,
    kAXFocusedUIElementAttribute, kAXValueAttribute
)

OMFK_DIR = Path(__file__).parent.parent
LOG_FILE = Path.home() / ".omfk" / "debug.log"

# Key codes
K_A, K_C, K_V, K_N = 0x00, 0x08, 0x09, 0x2D
K_OPTION, K_BACKSPACE, K_DELETE = 0x3A, 0x33, 0x75

def post_key(kc, flags=0, down=True):
    src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    ev = CGEventCreateKeyboardEvent(src, kc, down)
    if flags: CGEventSetFlags(ev, flags)
    CGEventPost(kCGHIDEventTap, ev)

def press(kc, flags=0):
    post_key(kc, flags, True); time.sleep(0.01); post_key(kc, flags, False)

def cmd(kc): press(kc, kCGEventFlagMaskCommand)

def tap_option():
    post_key(K_OPTION, kCGEventFlagMaskAlternate, True)
    time.sleep(0.03)
    post_key(K_OPTION, 0, False)

def clipboard_get():
    return NSPasteboard.generalPasteboard().stringForType_(NSStringPboardType) or ""

def clipboard_set(t):
    pb = NSPasteboard.generalPasteboard(); pb.clearContents()
    pb.setString_forType_(t, NSStringPboardType)

def get_text():
    sw = AXUIElementCreateSystemWide()
    err, el = AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute, None)
    if err == 0 and el:
        err, v = AXUIElementCopyAttributeValue(el, kAXValueAttribute, None)
        if err == 0: return v
    return ""

def clear_doc():
    # Use osascript for reliable clearing
    subprocess.run(["osascript", "-e", '''
        tell application "System Events" to tell process "TextEdit"
            keystroke "a" using command down
            delay 0.05
            key code 51
            delay 0.05
        end tell
    '''], capture_output=True)
    time.sleep(0.1)

def test(input_text, expected=None, name=""):
    """Run single test. Returns (passed, result, time_ms)"""
    clear_doc()
    time.sleep(0.3)  # Wait for OMFK to reset
    
    clipboard_set(input_text)
    cmd(K_V); time.sleep(0.2)
    
    initial = get_text() or ""
    cmd(K_A); time.sleep(0.05)
    
    t0 = time.time()
    tap_option()
    time.sleep(1.0)  # Wait for OMFK
    elapsed = (time.time() - t0) * 1000
    
    result = get_text() or ""
    
    if expected:
        passed = result == expected
    else:
        passed = result != initial and result != ""
    
    return passed, initial, result, elapsed

# ============== TEST CASES ==============

TESTS = [
    # (input, expected_or_None, description)
    
    # === Basic single words ===
    ("ghbdtn", "привет", "RU word 'привет' on EN"),
    ("ckjdf", "слова", "RU word 'слова' on EN"),
    ("ntrcn", "текст", "RU word 'текст' on EN"),
    ("vbh", "мир", "RU short word 'мир'"),
    
    # === Hebrew words ===
    ("akuo", "שלום", "HE word 'שלום' on EN"),
    
    # === English on wrong layout ===
    ("ру|щ", None, "EN 'hello' on RU layout"),
    ("еуну", None, "EN 'test' on RU layout"),
    
    # === Mixed language sentences ===
    ("ghbdtn vbh", None, "Two RU words"),
    ("נתרצנ целенаправленно yfgbcfyysq ד неправильной הפצרכפלרת",
     "текст целенаправленно написанный в неправильной раскладке",
     "Complex mixed HE/RU/EN"),
    
    # === Edge cases ===
    ("a", None, "Single letter"),
    ("123", None, "Only digits - should not change"),
    ("hello", None, "Correct EN word - may not change"),
    ("GHBDTN", None, "Uppercase RU on EN"),
    
    # === Punctuation ===
    ("ghbdtn!", None, "Word with exclamation"),
    ("ghbdtn, vbh", None, "Words with comma"),
    ("\"ghbdtn\"", None, "Word in quotes"),
    
    # === Long text ===
    ("ghbdtn vbh ckjdf ntrcn", None, "Multiple RU words"),
    
    # === Special characters ===
    ("ghbdtn123", None, "Word with numbers"),
    ("ghbdtn_vbh", None, "Words with underscore"),
    
    # === Repeated conversions (stress) ===
    ("ntcn", "тест", "Stress test 1"),
    ("ntcn", "тест", "Stress test 2"),
    ("ntcn", "тест", "Stress test 3"),
]

def main():
    print("OMFK Stress Tester")
    print("=" * 70)
    
    # Start OMFK
    subprocess.run(["pkill", "-f", ".build/debug/OMFK"], capture_output=True)
    time.sleep(0.3)
    LOG_FILE.parent.mkdir(exist_ok=True)
    LOG_FILE.unlink(missing_ok=True)
    
    print("Building OMFK...")
    r = subprocess.run(["swift", "build"], cwd=OMFK_DIR, capture_output=True)
    if r.returncode != 0:
        print(f"Build failed!"); return 1
    
    env = os.environ.copy()
    env["OMFK_DEBUG_LOG"] = "1"
    omfk = subprocess.Popen([str(OMFK_DIR / ".build/debug/OMFK")], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    
    # Open TextEdit
    subprocess.run(["open", "-a", "TextEdit"])
    time.sleep(0.5)
    cmd(K_N); time.sleep(0.3)
    apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_("com.apple.TextEdit")
    if apps: apps[0].activateWithOptions_(0)
    time.sleep(0.3)
    
    # Run tests
    passed = failed = 0
    times = []
    results = []
    
    print(f"\nRunning {len(TESTS)} tests...\n")
    
    for i, (inp, exp, desc) in enumerate(TESTS):
        ok, initial, result, ms = test(inp, exp, desc)
        times.append(ms)
        
        status = "✓" if ok else "✗"
        result_short = result[:40] + "..." if len(result) > 40 else result
        
        if ok:
            passed += 1
            print(f"{status} [{ms:5.0f}ms] {desc}")
        else:
            failed += 1
            print(f"{status} [{ms:5.0f}ms] {desc}")
            print(f"    Input:    '{inp[:50]}'")
            print(f"    Expected: '{exp or 'changed'}'")
            print(f"    Got:      '{result_short}'")
        
        results.append((desc, ok, inp, result, ms))
        time.sleep(0.2)
    
    # Summary
    print("\n" + "=" * 70)
    print(f"RESULTS: {passed}/{len(TESTS)} passed, {failed} failed")
    print(f"TIMING:  avg={sum(times)/len(times):.0f}ms, "
          f"min={min(times):.0f}ms, max={max(times):.0f}ms")
    
    if failed:
        print("\nFAILED TESTS:")
        for desc, ok, inp, res, ms in results:
            if not ok:
                print(f"  - {desc}")
    
    # Cleanup
    omfk.terminate()
    subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'],
                   capture_output=True)
    
    return 0 if failed == 0 else 1

if __name__ == "__main__":
    exit(main())
