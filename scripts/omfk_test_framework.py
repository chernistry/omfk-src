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
    """Test: Cycling should work after auto-correction."""
    fw = OMFKTestFramework()
    
    print("=" * 60)
    print("Test: Cycling after auto-correction")
    print("=" * 60)
    
    # Check OMFK
    if not fw.is_omfk_running():
        print("❌ OMFK is not running!")
        return False
    
    # Close any existing TextEdit windows without saving
    print("Closing existing TextEdit windows...")
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            close every window saving no
        end tell
    '''], capture_output=True)
    fw.wait(0.3)
    
    # Open fresh TextEdit document
    print("Opening fresh TextEdit document...")
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            activate
            make new document
        end tell
    '''], capture_output=True)
    fw.wait(0.5)
    
    # Ensure focus is in the text area by clicking
    subprocess.run(['osascript', '-e', '''
        tell application "System Events"
            tell process "TextEdit"
                set frontmost to true
                -- Click in the text area
                click text area 1 of scroll area 1 of window 1
            end tell
        end tell
    '''], capture_output=True)
    fw.wait(0.5)
    
    # Double-check TextEdit is frontmost
    subprocess.run(['osascript', '-e', 'tell application "TextEdit" to activate'], capture_output=True)
    fw.wait(0.5)
    
    # Verify TextEdit is active
    app_info = fw.get_frontmost_app()
    print(f"   Active app: {app_info['name']}")
    if app_info['name'] != 'TextEdit':
        print("❌ TextEdit is not active!")
        return False
    
    # Note: Layout switching is unreliable via automation
    # The test will work with whatever layout triggers auto-correction
    print("Note: Test works with any layout that triggers auto-correction")
    
    fw.clear_log()
    
    # Activate TextEdit RIGHT BEFORE typing (no subprocess calls between)
    subprocess.run(['osascript', '-e', 'tell application "TextEdit" to activate'], capture_output=True)
    time.sleep(0.5)
    
    # Type word in wrong layout (ghbdtn = привет on RU keyboard)
    print("\n1. Typing 'ghbdtn' + space (should trigger auto-correction)...")
    fw.type_text("ghbdtn")
    fw.take_screenshot("01_after_type")
    
    text_before_space = fw.get_element_value()
    print(f"   Text before space: '{text_before_space.strip()}'")
    
    fw.press_space()  # Triggers auto-correction
    fw.wait(1.0)
    fw.take_screenshot("03_after_space")
    
    text_after_auto = fw.get_element_value()
    print(f"   Text after auto-correction: '{text_after_auto.strip()}'")
    
    # Check log
    log = fw.get_log()
    has_correction = "CORRECTION APPLIED" in log
    print(f"   Auto-correction triggered: {has_correction}")
    
    # Press Option to cycle
    print("\n2. Pressing Option (should cycle to original)...")
    fw.press_option()
    fw.wait(0.5)
    fw.take_screenshot("04_after_option1")
    
    text_after_opt1 = fw.get_element_value()
    print(f"   Text after Option #1: '{text_after_opt1.strip()}'")
    
    # Press Option again
    print("\n3. Pressing Option again...")
    fw.press_option()
    fw.wait(0.5)
    fw.take_screenshot("05_after_option2")
    
    text_after_opt2 = fw.get_element_value()
    print(f"   Text after Option #2: '{text_after_opt2.strip()}'")
    
    # Press Option third time
    print("\n4. Pressing Option again...")
    fw.press_option()
    fw.wait(0.5)
    fw.take_screenshot("06_after_option3")
    
    text_after_opt3 = fw.get_element_value()
    print(f"   Text after Option #3: '{text_after_opt3.strip()}'")
    
    # Results
    print("\n" + "=" * 60)
    print("Results:")
    print("=" * 60)
    
    texts = [text_after_auto.strip(), text_after_opt1.strip(), 
             text_after_opt2.strip(), text_after_opt3.strip()]
    unique = list(dict.fromkeys(texts))
    
    print(f"Unique texts: {len(unique)}")
    for i, t in enumerate(unique):
        print(f"  [{i}] '{t}'")
    
    cycling_works = len(unique) > 1
    
    if cycling_works:
        print("\n✅ PASS: Cycling is working")
    else:
        print("\n❌ FAIL: Cycling not working")
    
    # Show relevant log entries
    print("\n" + "=" * 60)
    print("OMFK Log (last 20 lines):")
    print("=" * 60)
    for line in fw.get_log_lines()[-20:]:
        print(f"  {line}")
    
    print(f"\n📁 Screenshots saved to: {fw.screenshot_dir}")
    
    # Close TextEdit window without saving
    print("\nClosing TextEdit window...")
    subprocess.run(['osascript', '-e', '''
        tell application "TextEdit"
            close front window saving no
        end tell
    '''], capture_output=True)
    
    return cycling_works


if __name__ == "__main__":
    success = run_test_cycling_after_autocorrect()
    exit(0 if success else 1)
