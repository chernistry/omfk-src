#!/usr/bin/env python3
"""
E2E test for Alt hotkey cycling after auto-correction.
Tests Bug 1: Cycling should work after auto-correction (space trigger).
"""

import subprocess
import time
import os

def run_applescript(script):
    """Run AppleScript and return output."""
    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    return result.stdout.strip()

def type_text(text):
    """Type text using AppleScript."""
    escaped = text.replace('\\', '\\\\').replace('"', '\\"')
    run_applescript(f'tell application "System Events" to keystroke "{escaped}"')

def press_key(key, modifiers=None):
    """Press a key with optional modifiers."""
    if modifiers:
        mod_str = ' using {' + ', '.join(f'{m} down' for m in modifiers) + '}'
    else:
        mod_str = ''
    run_applescript(f'tell application "System Events" to key code {key}{mod_str}')

def get_text_from_textedit():
    """Get all text from TextEdit."""
    script = '''
    tell application "TextEdit"
        if (count of documents) > 0 then
            return text of document 1
        end if
    end tell
    '''
    return run_applescript(script)

def clear_textedit():
    """Clear TextEdit content."""
    run_applescript('tell application "TextEdit" to set text of document 1 to ""')

def wait_for_omfk():
    """Check if OMFK is running."""
    result = subprocess.run(['pgrep', '-x', 'OMFK'], capture_output=True)
    return result.returncode == 0

def clear_log():
    """Clear OMFK debug log."""
    log_path = os.path.expanduser('~/.omfk/debug.log')
    with open(log_path, 'w') as f:
        f.write('')

def get_log():
    """Get OMFK debug log content."""
    log_path = os.path.expanduser('~/.omfk/debug.log')
    try:
        with open(log_path, 'r') as f:
            return f.read()
    except:
        return ''

def test_cycling_after_autocorrection():
    """Test that Alt cycling works after auto-correction."""
    print("=" * 60)
    print("Test: Cycling after auto-correction")
    print("=" * 60)
    
    # Check OMFK is running
    if not wait_for_omfk():
        print("❌ OMFK is not running!")
        return False
    
    # Open TextEdit
    run_applescript('tell application "TextEdit" to activate')
    time.sleep(0.5)
    
    # Create new document if needed
    run_applescript('''
    tell application "TextEdit"
        if (count of documents) = 0 then
            make new document
        end if
    end tell
    ''')
    time.sleep(0.3)
    
    clear_textedit()
    clear_log()
    time.sleep(0.3)
    
    # Type word in wrong layout + space (triggers auto-correction)
    print("1. Typing 'ghbdtn ' (should auto-correct to 'привет ')...")
    type_text("ghbdtn ")
    time.sleep(1.0)  # Wait for auto-correction
    
    text_after_auto = get_text_from_textedit().strip()
    print(f"   After auto-correction: '{text_after_auto}'")
    
    # Check log for cycling state
    log = get_log()
    has_cycling = "cyclingState" in log.lower() or "CYCLING" in log
    print(f"   Cycling state in log: {has_cycling}")
    
    # Press Alt to cycle (should undo to original)
    print("2. Pressing Alt (should cycle to original 'ghbdtn ')...")
    press_key(58)  # Option key
    time.sleep(0.5)
    
    text_after_alt1 = get_text_from_textedit().strip()
    print(f"   After Alt #1: '{text_after_alt1}'")
    
    # Press Alt again (should cycle to next alternative)
    print("3. Pressing Alt again (should cycle to next alternative)...")
    press_key(58)
    time.sleep(0.5)
    
    text_after_alt2 = get_text_from_textedit().strip()
    print(f"   After Alt #2: '{text_after_alt2}'")
    
    # Press Alt again
    print("4. Pressing Alt again...")
    press_key(58)
    time.sleep(0.5)
    
    text_after_alt3 = get_text_from_textedit().strip()
    print(f"   After Alt #3: '{text_after_alt3}'")
    
    # Analyze results
    print("\n" + "=" * 60)
    print("Results:")
    print("=" * 60)
    
    unique_texts = list(dict.fromkeys([text_after_auto, text_after_alt1, text_after_alt2, text_after_alt3]))
    print(f"Unique texts seen: {len(unique_texts)}")
    for i, t in enumerate(unique_texts):
        print(f"  [{i}] '{t}'")
    
    # Check if cycling worked
    cycling_worked = len(unique_texts) > 1
    original_restored = "ghbdtn" in [text_after_alt1, text_after_alt2, text_after_alt3]
    
    if cycling_worked:
        print("\n✅ PASS: Cycling is working (multiple alternatives seen)")
    else:
        print("\n❌ FAIL: Cycling not working (only one text seen)")
    
    if original_restored:
        print("✅ PASS: Original text was restored during cycling")
    else:
        print("⚠️  WARN: Original text 'ghbdtn' not seen in cycling")
    
    # Show log excerpt
    print("\n" + "=" * 60)
    print("Log excerpt:")
    print("=" * 60)
    log_lines = get_log().split('\n')
    for line in log_lines[-20:]:
        if line.strip():
            print(f"  {line}")
    
    return cycling_worked

if __name__ == "__main__":
    success = test_cycling_after_autocorrection()
    exit(0 if success else 1)
