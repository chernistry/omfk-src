#!/usr/bin/env python3
"""
Test runner for failed cases only (2025-12-30 session)
Runs only the tests that failed in the full E2E run.
"""

import sys
import subprocess
from pathlib import Path

# Add parent dir to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from comprehensive_test import (
    stop_omfk, write_active_layouts, BASE_ACTIVE_LAYOUTS,
    set_system_layouts, get_enabled_system_layouts,
    run_test_category, OMFK_DIR
)
import json

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
    
    print("Building OMFK...")
    result = subprocess.run(
        ["swift", "build", "-c", "release"],
        cwd=OMFK_DIR,
        capture_output=True
    )
    if result.returncode != 0:
        print(f"❌ Build failed: {result.stderr.decode()}")
        return 1
    
    # Save original layouts
    original_layouts = get_enabled_system_layouts()
    print(f"Saved original layouts: {original_layouts}")
    
    # Set up standard layouts
    print("Setting up system layouts...")
    set_system_layouts("us", "russian", "hebrew")
    write_active_layouts(BASE_ACTIVE_LAYOUTS)
    
    # Start OMFK
    import time
    subprocess.Popen(
        [str(OMFK_DIR / ".build/release/OMFK")],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    time.sleep(2)
    
    # Open TextEdit
    subprocess.run(["open", "-a", "TextEdit"], check=True)
    time.sleep(1)
    
    # Run tests
    total_pass = 0
    total_fail = 0
    
    for category_name, category_data in test_cases.items():
        print(f"\n{'='*70}")
        print(category_name.upper().replace('_', ' '))
        print("="*70)
        
        passed, failed = run_test_category(category_name, category_data, real_typing=True)
        total_pass += passed
        total_fail += failed
    
    # Restore layouts
    print(f"\nRestoring original layouts: {original_layouts}")
    if len(original_layouts) >= 3:
        set_system_layouts(
            original_layouts[0].lower().replace("-", "_"),
            original_layouts[1].lower().replace("-", "_") if len(original_layouts) > 1 else "russian",
            original_layouts[2].lower().replace("-", "_") if len(original_layouts) > 2 else "hebrew"
        )
    
    # Summary
    print(f"\n{'='*70}")
    print(f"TOTAL: {total_pass} passed, {total_fail} failed")
    print("="*70)
    
    return 0 if total_fail == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
