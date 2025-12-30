#!/usr/bin/env python3
"""
Test runner for failed cases only (2025-12-30 session)
Runs only the tests that failed in the full E2E run.
"""

import sys
import subprocess
import os
import re
from pathlib import Path

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from comprehensive_test import (
    stop_omfk, write_active_layouts, BASE_ACTIVE_LAYOUTS,
    set_system_layouts, get_enabled_system_layouts,
    disable_system_layout, enable_system_layout,
    open_textedit, close_textedit, ensure_textedit_focused_auto, FocusLostError,
    run_test_category, OMFK_DIR, BUNDLE_ID
)
import json

_ACTIVE_LAYOUT_LINE = re.compile(r'^\s*([A-Za-z0-9_]+)\s*=\s*"?([^";]+)"?;\s*$')


def read_active_layouts() -> dict[str, str] | None:
    r = subprocess.run(
        ["defaults", "read", BUNDLE_ID, "activeLayouts"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return None
    layouts: dict[str, str] = {}
    for line in r.stdout.splitlines():
        m = _ACTIVE_LAYOUT_LINE.match(line)
        if not m:
            continue
        layouts[m.group(1)] = m.group(2)
    return layouts or None


def restore_active_layouts(original: dict[str, str] | None) -> None:
    if original is None:
        subprocess.run(
            ["defaults", "delete", BUNDLE_ID, "activeLayouts"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return
    cmd = ["defaults", "write", BUNDLE_ID, "activeLayouts", "-dict"]
    for k, v in sorted(original.items()):
        cmd.extend([str(k), str(v)])
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    print("="*70)
    print("FAILED CASES TEST (2025-12-30)")
    print("="*70)
    print("\nTesting only cases that failed in full E2E run")
    print("Total expected: ~40 tests\n")
    
    # Load failed cases
    test_file = OMFK_DIR / "tests/failed_cases_2025_12_30.json"
    with open(test_file) as f:
        test_cases = json.load(f)
    
    # Setup
    print("Checking for existing OMFK instances...")
    stop_omfk()
    
    # Save original layouts
    original_layouts = get_enabled_system_layouts()
    print(f"Saved original layouts: {original_layouts}")

    original_active_layouts = read_active_layouts()
    
    import time
    total_pass = 0
    total_fail = 0

    try:
        print("Building OMFK (release)...")
        result = subprocess.run(
            ["swift", "build", "-c", "release"],
            cwd=OMFK_DIR,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"❌ Build failed:\n{result.stderr}")
            return 1

        # Set up standard layouts
        print("Setting up system layouts...")
        set_system_layouts("us", "russian", "hebrew")

        # Persist activeLayouts for OMFK (picked up on app start).
        write_active_layouts(BASE_ACTIVE_LAYOUTS)

        # Start OMFK (release)
        env = dict(**os.environ)
        env["OMFK_DEBUG_LOG"] = env.get("OMFK_DEBUG_LOG", "1")
        subprocess.Popen(
            [str(OMFK_DIR / ".build/release/OMFK")],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        time.sleep(1.0)

        # Open TextEdit (ensures a document exists + disables system autocorrect)
        open_textedit()
        try:
            ensure_textedit_focused_auto()
        except FocusLostError as e:
            print(f"\n❌ {e}")
            print("   TextEdit must be frontmost in the current Space for real-typing tests.")
            print("   Bring TextEdit to the foreground and re-run this script.")
            return 2

        # Run tests
        for category_name, category_data in test_cases.items():
            print(f"\n{'='*70}")
            print(category_name.upper().replace('_', ' '))
            print("="*70)

            passed, failed = run_test_category(category_name, category_data, real_typing=True)
            total_pass += passed
            total_fail += failed

    finally:
        close_textedit()
        stop_omfk()

        # Restore original user layouts (best-effort).
        print(f"\nRestoring original layouts: {original_layouts}")
        current_enabled = get_enabled_system_layouts()
        for lay in current_enabled:
            if lay not in original_layouts:
                disable_system_layout(lay)
        for lay in original_layouts:
            if lay not in current_enabled:
                enable_system_layout(lay)

        restore_active_layouts(original_active_layouts)

    # Summary
    print(f"\n{'='*70}")
    print(f"TOTAL: {total_pass} passed, {total_fail} failed")
    print("="*70)

    return 0 if total_fail == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
