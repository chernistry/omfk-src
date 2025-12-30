#!/usr/bin/env python3
"""Quick manual test for comma/period in words"""
import subprocess
import time

def type_text(text):
    """Type text using AppleScript"""
    script = f'tell application "System Events" to keystroke "{text}"'
    subprocess.run(["osascript", "-e", script], capture_output=True)
    time.sleep(0.1)

def type_space():
    """Type space"""
    subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke " "'], capture_output=True)
    time.sleep(0.3)

def get_textedit_content():
    """Get TextEdit content"""
    result = subprocess.run([
        "osascript", "-e",
        'tell application "TextEdit" to get text of front document'
    ], capture_output=True, text=True)
    return result.stdout.strip()

def clear_textedit():
    """Clear TextEdit"""
    subprocess.run(["osascript", "-e", '''
        tell application "TextEdit"
            activate
            tell application "System Events"
                keystroke "a" using command down
                key code 51
            end tell
        end tell
    '''], capture_output=True)
    time.sleep(0.2)

# Test cases
test_cases = [
    ("k.,k.", "люблю"),
    (",tp", "без"),
    ("j,", "об"),
]

print("Starting manual tests...")
print("Make sure TextEdit is open and OMFK is running!")
time.sleep(2)

for input_text, expected in test_cases:
    print(f"\nTest: {input_text} → {expected}")
    clear_textedit()
    
    # Type character by character
    for char in input_text:
        type_text(char)
    
    type_space()
    time.sleep(0.5)
    
    result = get_textedit_content()
    # Remove trailing space for comparison
    result = result.rstrip()
    
    if result == expected:
        print(f"  ✅ PASS: got '{result}'")
    else:
        print(f"  ❌ FAIL: got '{result}', expected '{expected}'")

print("\nDone!")
