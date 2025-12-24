#!/usr/bin/env python3
"""
OMFK UI Test Framework

Provides low-level control for testing keyboard layout correction:
- CGEvent-based keyboard input (keycode-based, layout-independent)
- Accessibility API for reading text from UI elements
- Screenshot capture for visual verification
- OMFK log parsing
"""

import os
import time
import subprocess
from datetime import datetime
from pathlib import Path

# macOS frameworks
import Quartz
from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventPost,
    CGEventSetFlags,
    kCGHIDEventTap,
    kCGEventFlagMaskShift,
    kCGEventFlagMaskAlternate,
    CGWindowListCopyWindowInfo,
    kCGWindowListOptionOnScreenOnly,
    kCGNullWindowID,
    CGWindowListCreateImage,
    CGRectNull,
    kCGWindowListOptionIncludingWindow,
    kCGWindowImageDefault,
)
from ApplicationServices import (
    AXUIElementCreateSystemWide,
    AXUIElementCreateApplication,
    AXUIElementCopyAttributeValue,
    AXUIElementSetAttributeValue,
    kAXFocusedUIElementAttribute,
    kAXValueAttribute,
    kAXSelectedTextAttribute,
)
from AppKit import NSWorkspace, NSScreen
from Foundation import NSURL
from PIL import Image
import io


# US QWERTY keycode mapping
KEYCODE_MAP = {
    'a': 0, 'b': 11, 'c': 8, 'd': 2, 'e': 14, 'f': 3, 'g': 5, 'h': 4,
    'i': 34, 'j': 38, 'k': 40, 'l': 37, 'm': 46, 'n': 45, 'o': 31, 'p': 35,
    'q': 12, 'r': 15, 's': 1, 't': 17, 'u': 32, 'v': 9, 'w': 13, 'x': 7,
    'y': 16, 'z': 6,
    '1': 18, '2': 19, '3': 20, '4': 21, '5': 23, '6': 22, '7': 26, '8': 28,
    '9': 25, '0': 29,
    ' ': 49, '\n': 36, '\t': 48,
    '-': 27, '=': 24, '[': 33, ']': 30, '\\': 42, ';': 41, "'": 39,
    ',': 43, '.': 47, '/': 44, '`': 50,
}

# Special keys
KEY_RETURN = 36
KEY_TAB = 48
KEY_SPACE = 49
KEY_DELETE = 51
KEY_ESCAPE = 53
KEY_OPTION = 58
KEY_SHIFT = 56
KEY_COMMAND = 55
KEY_CONTROL = 59
KEY_LEFT = 123
KEY_RIGHT = 124
KEY_UP = 126
KEY_DOWN = 125


class OMFKTestFramework:
    """Framework for automated OMFK testing."""
    
    def __init__(self, screenshot_dir: str = None):
        self.screenshot_dir = Path(screenshot_dir or "/tmp/omfk_tests")
        self.screenshot_dir.mkdir(parents=True, exist_ok=True)
        self.screenshot_count = 0
        self.log_path = Path.home() / ".omfk" / "debug.log"
        
    # ==================== Keyboard Input ====================
    
    def press_key(self, keycode: int, flags: int = 0):
        """Press and release a key by keycode."""
        # Key down
        event = CGEventCreateKeyboardEvent(None, keycode, True)
        if flags:
            CGEventSetFlags(event, flags)
        CGEventPost(kCGHIDEventTap, event)
        
        time.sleep(0.02)
        
        # Key up
        event = CGEventCreateKeyboardEvent(None, keycode, False)
        if flags:
            CGEventSetFlags(event, flags)
        CGEventPost(kCGHIDEventTap, event)
        
        time.sleep(0.02)
    
    def type_char(self, char: str, shift: bool = False):
        """Type a single character using keycode."""
        lower = char.lower()
        if lower in KEYCODE_MAP:
            keycode = KEYCODE_MAP[lower]
            flags = kCGEventFlagMaskShift if (char.isupper() or shift) else 0
            self.press_key(keycode, flags)
        else:
            print(f"Warning: No keycode for '{char}'")
    
    def type_text(self, text: str, delay: float = 0.03):
        """Type text character by character using keycodes."""
        for char in text:
            self.type_char(char)
            time.sleep(delay)
    
    def press_option(self):
        """Press and release Option key (for OMFK hotkey)."""
        self.press_key(KEY_OPTION)
    
    def press_space(self):
        """Press space (triggers OMFK auto-correction)."""
        self.press_key(KEY_SPACE)
    
    def press_backspace(self, count: int = 1):
        """Press backspace N times."""
        for _ in range(count):
            self.press_key(KEY_DELETE)
            time.sleep(0.02)
    
    def select_all(self):
        """Press Cmd+A to select all."""
        self.press_key(0, kCGEventFlagMaskCommand)  # Just command
        event = CGEventCreateKeyboardEvent(None, 0, True)  # 'a' keycode
        CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
        CGEventPost(kCGHIDEventTap, event)
        event = CGEventCreateKeyboardEvent(None, 0, False)
        CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
        CGEventPost(kCGHIDEventTap, event)
        time.sleep(0.1)
    
    # ==================== Accessibility API ====================
    
    def get_focused_element(self):
        """Get the currently focused UI element."""
        system_wide = AXUIElementCreateSystemWide()
        err, focused = AXUIElementCopyAttributeValue(
            system_wide, kAXFocusedUIElementAttribute, None
        )
        if err == 0:
            return focused
        return None
    
    def get_element_value(self, element=None) -> str:
        """Get the value (text) of a UI element."""
        if element is None:
            element = self.get_focused_element()
        if element is None:
            return ""
        
        err, value = AXUIElementCopyAttributeValue(element, kAXValueAttribute, None)
        if err == 0 and value:
            return str(value)
        return ""
    
    def get_selected_text(self, element=None) -> str:
        """Get selected text from a UI element."""
        if element is None:
            element = self.get_focused_element()
        if element is None:
            return ""
        
        err, value = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, None)
        if err == 0 and value:
            return str(value)
        return ""
    
    def set_element_value(self, text: str, element=None) -> bool:
        """Set the value of a UI element."""
        if element is None:
            element = self.get_focused_element()
        if element is None:
            return False
        
        err = AXUIElementSetAttributeValue(element, kAXValueAttribute, text)
        return err == 0
    
    def get_frontmost_app(self) -> dict:
        """Get info about the frontmost application."""
        workspace = NSWorkspace.sharedWorkspace()
        app = workspace.frontmostApplication()
        return {
            'name': app.localizedName(),
            'bundle_id': app.bundleIdentifier(),
            'pid': app.processIdentifier(),
        }
    
    # ==================== Screenshots ====================
    
    def take_screenshot(self, label: str = "") -> Path:
        """Take a screenshot of TextEdit window only."""
        self.screenshot_count += 1
        timestamp = datetime.now().strftime("%H%M%S")
        filename = f"{self.screenshot_count:03d}_{timestamp}_{label}.png"
        filepath = self.screenshot_dir / filename
        
        # Get TextEdit window ID and capture only that window
        try:
            result = subprocess.run(['osascript', '-e', '''
                tell application "System Events"
                    tell process "TextEdit"
                        set winID to id of window 1
                    end tell
                end tell
                return winID
            '''], capture_output=True, text=True)
            
            # Use screencapture with window selection for TextEdit
            subprocess.run(['screencapture', '-x', '-l', result.stdout.strip(), str(filepath)], 
                          capture_output=True, check=False)
        except:
            # Fallback to capturing frontmost window
            subprocess.run(['screencapture', '-x', '-w', str(filepath)], capture_output=True, check=False)
        
        if filepath.exists():
            size_kb = filepath.stat().st_size // 1024
            print(f"📸 Screenshot: {filepath.name} ({size_kb}KB)")
        return filepath
    
    def take_window_screenshot(self, window_id: int = None, label: str = "") -> Path:
        """Take a screenshot of a specific window."""
        self.screenshot_count += 1
        timestamp = datetime.now().strftime("%H%M%S")
        filename = f"{self.screenshot_count:03d}_{timestamp}_{label}.png"
        filepath = self.screenshot_dir / filename
        
        if window_id:
            subprocess.run(['screencapture', '-x', '-l', str(window_id), str(filepath)], check=True)
        else:
            subprocess.run(['screencapture', '-x', str(filepath)], check=True)
        
        print(f"📸 Screenshot: {filepath}")
        return filepath
    
    # ==================== OMFK Log Parsing ====================
    
    def clear_log(self):
        """Clear OMFK debug log."""
        if self.log_path.exists():
            self.log_path.write_text("")
    
    def get_log(self) -> str:
        """Get OMFK debug log content."""
        if self.log_path.exists():
            return self.log_path.read_text()
        return ""
    
    def get_log_lines(self, since: str = None) -> list:
        """Get log lines, optionally filtered by timestamp."""
        lines = self.get_log().strip().split('\n')
        if since:
            # Filter lines after timestamp
            filtered = []
            for line in lines:
                if since in line or (filtered and line):
                    filtered.append(line)
            return filtered
        return [l for l in lines if l.strip()]
    
    def wait_for_log_entry(self, pattern: str, timeout: float = 3.0) -> bool:
        """Wait for a log entry matching pattern."""
        start = time.time()
        while time.time() - start < timeout:
            if pattern in self.get_log():
                return True
            time.sleep(0.1)
        return False
    
    # ==================== App Control ====================
    
    def activate_app(self, app_name: str):
        """Activate an application by name."""
        script = f'tell application "{app_name}" to activate'
        subprocess.run(['osascript', '-e', script], check=True)
        time.sleep(0.3)
    
    def open_textedit(self) -> bool:
        """Open TextEdit with a new document."""
        self.activate_app("TextEdit")
        time.sleep(0.3)
        
        # Create new document
        script = '''
        tell application "TextEdit"
            if (count of documents) = 0 then
                make new document
            end if
        end tell
        '''
        subprocess.run(['osascript', '-e', script], check=True)
        time.sleep(0.3)
        return True
    
    def clear_textedit(self):
        """Clear TextEdit content."""
        self.set_element_value("")
        time.sleep(0.1)
    
    def is_omfk_running(self) -> bool:
        """Check if OMFK is running."""
        result = subprocess.run(['pgrep', '-x', 'OMFK'], capture_output=True)
        return result.returncode == 0
    
    # ==================== Test Utilities ====================
    
    def wait(self, seconds: float):
        """Wait for specified time."""
        time.sleep(seconds)
    
    def log(self, message: str):
        """Print a log message."""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {message}")


# ==================== Test Runner ====================

def run_test_cycling_after_autocorrect():
    """Test: Cycling should work with selected text in Sublime Text."""
    fw = OMFKTestFramework()
    
    print("=" * 60)
    print("Test: Cycling with SELECTED text in Sublime Text")
    print("=" * 60)
    
    # Check OMFK
    if not fw.is_omfk_running():
        print("❌ OMFK is not running!")
        return False
    
    fw.clear_log()
    
    # Open Sublime Text
    print("Opening Sublime Text...")
    subprocess.run(['osascript', '-e', '''
        tell application "Sublime Text"
            activate
        end tell
    '''], capture_output=True)
    fw.wait(1.0)
    
    # Create new file
    print("Creating new file (Cmd+N)...")
    event = CGEventCreateKeyboardEvent(None, 45, True)  # 'n' = keycode 45
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 45, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.5)
    
    # Test text
    test_text = "נתרצנ целенаправленно yfgbcfyysq ד неправильной הפצרכפלרת"
    print(f"\n1. Pasting test text via clipboard...")
    
    # Copy to clipboard and paste
    subprocess.run(['osascript', '-e', f'set the clipboard to "{test_text}"'], capture_output=True)
    fw.wait(0.2)
    
    # Paste (Cmd+V)
    event = CGEventCreateKeyboardEvent(None, 9, True)  # 'v' = keycode 9
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 9, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.5)
    
    # Select all (Cmd+A)
    print("2. Selecting all text (Cmd+A)...")
    event = CGEventCreateKeyboardEvent(None, 0, True)  # 'a' = keycode 0
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 0, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.5)
    
    # Check what's selected via clipboard (Cmd+C)
    event = CGEventCreateKeyboardEvent(None, 8, True)  # 'c' = keycode 8
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 8, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.3)
    
    result = subprocess.run(['osascript', '-e', 'get the clipboard'], capture_output=True, text=True)
    text_before = result.stdout.strip()
    print(f"   Selected text: '{text_before[:50]}...'")
    
    # Press Option to correct selected text
    print("\n3. Pressing Option (should correct selected text)...")
    fw.press_option()
    fw.wait(1.0)
    
    # Copy result
    event = CGEventCreateKeyboardEvent(None, 8, True)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 8, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.3)
    
    result = subprocess.run(['osascript', '-e', 'get the clipboard'], capture_output=True, text=True)
    text_after_opt1 = result.stdout.strip()
    print(f"   Text after Option #1: '{text_after_opt1[:50]}...'")
    
    # Press Option again
    print("\n4. Pressing Option again...")
    fw.press_option()
    fw.wait(0.5)
    
    event = CGEventCreateKeyboardEvent(None, 8, True)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 8, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.3)
    
    result = subprocess.run(['osascript', '-e', 'get the clipboard'], capture_output=True, text=True)
    text_after_opt2 = result.stdout.strip()
    print(f"   Text after Option #2: '{text_after_opt2[:50]}...'")
    
    # Results
    print("\n" + "=" * 60)
    print("Results:")
    print("=" * 60)
    
    texts = [text_before, text_after_opt1, text_after_opt2]
    unique = list(dict.fromkeys([t for t in texts if t]))
    
    print(f"Unique texts: {len(unique)}")
    for i, t in enumerate(unique):
        print(f"  [{i}] '{t[:70]}{'...' if len(t) > 70 else ''}'")
    
    cycling_works = len(unique) > 1
    
    if cycling_works:
        print("\n✅ PASS: Cycling is working")
    else:
        print("\n❌ FAIL: Cycling not working")
    
    # Show relevant log entries
    print("\n" + "=" * 60)
    print("OMFK Log (last 30 lines):")
    print("=" * 60)
    for line in fw.get_log_lines()[-30:]:
        print(f"  {line}")
    
    # Close Sublime tab without saving (Cmd+W, then Don't Save)
    print("\nClosing Sublime Text tab...")
    event = CGEventCreateKeyboardEvent(None, 13, True)  # 'w' = keycode 13
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 13, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    fw.wait(0.5)
    
    # Press Cmd+D for "Don't Save"
    event = CGEventCreateKeyboardEvent(None, 2, True)  # 'd' = keycode 2
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    event = CGEventCreateKeyboardEvent(None, 2, False)
    CGEventSetFlags(event, Quartz.kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, event)
    
    return cycling_works


if __name__ == "__main__":
    success = run_test_cycling_after_autocorrect()
    exit(0 if success else 1)
