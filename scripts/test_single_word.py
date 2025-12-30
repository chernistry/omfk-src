#!/usr/bin/env python3
"""Simple test for k.,k. word"""
import subprocess
import time
import os

# Kill existing OMFK
subprocess.run(["pkill", "-9", "OMFK"], capture_output=True)
time.sleep(0.5)

# Start OMFK with debug
env = os.environ.copy()
env["OMFK_DEBUG_LOG"] = "1"
omfk_proc = subprocess.Popen([".build/debug/OMFK"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(2)

# Open TextEdit
subprocess.run(["osascript", "-e", '''
    tell application "TextEdit"
        activate
        if (count of documents) = 0 then make new document
    end tell
'''], capture_output=True)
time.sleep(0.5)

# Disable autocorrect
subprocess.run(["defaults", "write", "-g", "NSAutomaticSpellingCorrectionEnabled", "-bool", "false"], capture_output=True)
subprocess.run(["defaults", "write", "-g", "NSAutomaticTextCompletionEnabled", "-bool", "false"], capture_output=True)

# Clear TextEdit
subprocess.run(["osascript", "-e", '''
    tell application "System Events"
        keystroke "a" using command down
        key code 51
    end tell
'''], capture_output=True)
time.sleep(0.3)

print("Typing: k.,k. ")
# Type k.,k. character by character
for char in "k.,k.":
    subprocess.run(["osascript", "-e", f'tell application "System Events" to keystroke "{char}"'], capture_output=True)
    time.sleep(0.05)

# Type space to trigger
subprocess.run(["osascript", "-e", 'tell application "System Events" to keystroke " "'], capture_output=True)
time.sleep(1)

# Get result
result = subprocess.run(["osascript", "-e", 'tell application "TextEdit" to get text of front document'], capture_output=True, text=True)
print(f"Result: '{result.stdout.strip()}'")
print(f"Expected: 'люблю'")

# Check logs
print("\n=== OMFK Logs ===")
subprocess.run(["log", "show", "--predicate", "subsystem == 'com.chernistry.omfk'", "--last", "10s", "--style", "compact"])

# Cleanup
omfk_proc.terminate()
subprocess.run(["osascript", "-e", 'tell app "TextEdit" to quit saving no'], capture_output=True)
