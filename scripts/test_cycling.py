#!/usr/bin/env python3
"""Test OMFK cycling behavior - simulates manual hotkey presses"""

import subprocess
import time
from Quartz import (
    CGEventCreateKeyboardEvent, CGEventPost, kCGHIDEventTap,
    CGEventSetFlags, kCGEventFlagMaskAlternate, CGEventSourceCreate,
    kCGEventSourceStateHIDSystemState
)
from AppKit import NSWorkspace, NSPasteboard, NSStringPboardType

def get_frontmost_app():
    """Get frontmost app name"""
    ws = NSWorkspace.sharedWorkspace()
    app = ws.frontmostApplication()
    return app.localizedName() if app else "unknown"

def tap_option():
    """Tap Option key (triggers OMFK hotkey)"""
    src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    # Option down
    e = CGEventCreateKeyboardEvent(src, 58, True)
    CGEventSetFlags(e, kCGEventFlagMaskAlternate)
    CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.02)
    # Option up
    e = CGEventCreateKeyboardEvent(src, 58, False)
    CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.05)

def cmd_key(keycode):
    """Press Cmd+key"""
    src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
    e = CGEventCreateKeyboardEvent(src, keycode, True)
    CGEventSetFlags(e, 0x100000)  # Cmd
    CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.02)
    e = CGEventCreateKeyboardEvent(src, keycode, False)
    CGEventPost(kCGHIDEventTap, e)
    time.sleep(0.05)

def select_all():
    cmd_key(0)  # Cmd+A

def paste():
    cmd_key(9)  # Cmd+V

def clipboard_set(text):
    pb = NSPasteboard.generalPasteboard()
    pb.clearContents()
    pb.setString_forType_(text, NSStringPboardType)

def clipboard_get():
    pb = NSPasteboard.generalPasteboard()
    return pb.stringForType_(NSStringPboardType) or ""

def get_selected_text():
    """Get all text via clipboard (select all first)"""
    select_all()
    time.sleep(0.1)
    old = clipboard_get()
    cmd_key(8)  # Cmd+C
    time.sleep(0.1)
    text = clipboard_get()
    return text

def clear_log():
    subprocess.run(["rm", "-f", "/Users/sasha/.omfk/debug.log"], capture_output=True)

def get_log():
    try:
        with open("/Users/sasha/.omfk/debug.log", "r") as f:
            return f.read()
    except:
        return ""

def test_cycling():
    """Test cycling through alternatives"""
    print(f"App: {get_frontmost_app()}")
    print("=" * 60)
    
    # Test input
    test_text = "נתרצנ целенаправленно yfgbcfyysq ד неправильной הפצרכפלרת"
    expected_best = "текст целенаправленно написанный в неправильной раскладке"
    
    clear_log()
    
    # Paste test text
    print(f"1. Pasting: {test_text[:40]}...")
    clipboard_set(test_text)
    paste()
    time.sleep(0.5)
    
    # Select all
    print("2. Selecting all...")
    select_all()
    time.sleep(0.3)
    
    # First hotkey - should convert
    print("3. First Option tap (convert)...")
    tap_option()
    time.sleep(1.2)
    
    # Check log
    log = get_log()
    if "HOTKEY:" not in log:
        print("   ⚠️  No hotkey detected in log!")
    
    result1 = get_selected_text()
    print(f"   Result: {result1[:50]}..." if len(result1) > 50 else f"   Result: {result1}")
    
    # Cycle through alternatives
    results = [result1]
    print("\n4. Cycling through alternatives:")
    for i in range(6):
        select_all()
        time.sleep(0.1)
        tap_option()
        time.sleep(0.8)
        
        result = get_selected_text()
        results.append(result)
        
        # Check if we're back to original
        is_original = result.strip() == test_text.strip()
        is_best = result.strip() == expected_best.strip()
        
        marker = ""
        if is_original:
            marker = " ← ORIGINAL"
        elif is_best:
            marker = " ← BEST"
        
        print(f"   Cycle {i+1}: {result[:45]}...{marker}" if len(result) > 45 else f"   Cycle {i+1}: {result}{marker}")
        
        # If we got back to original, cycling works!
        if is_original:
            print(f"\n✓ SUCCESS: Returned to original after {i+1} cycles")
            break
    else:
        print("\n✗ FAIL: Did not return to original after 6 cycles")
    
    # Show unique results
    unique = list(dict.fromkeys([r.strip() for r in results if r.strip()]))
    print(f"\nUnique alternatives found: {len(unique)}")
    for i, u in enumerate(unique):
        print(f"  [{i}] {u[:60]}..." if len(u) > 60 else f"  [{i}] {u}")
    
    # Check log for errors
    log = get_log()
    if "Length mismatch" in log:
        print("\n⚠️  Length mismatch detected in log!")
    if "CYCLING - savedLen=18" in log or "CYCLING - savedLen=20" in log:
        print("\n⚠️  Suspicious short savedLen detected!")

def open_textedit():
    """Open TextEdit with new document"""
    subprocess.run(["open", "-a", "TextEdit"], capture_output=True)
    time.sleep(1.0)
    # Cmd+N for new document
    cmd_key(45)
    time.sleep(0.5)

if __name__ == "__main__":
    print("OMFK Cycling Test")
    print("Opening TextEdit...")
    open_textedit()
    time.sleep(1)
    test_cycling()
