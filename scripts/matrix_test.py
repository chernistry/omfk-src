#!/usr/bin/env python3
"""
OMFK Layout Matrix Test

Tests ALL combinations of source/target layouts.
For each pair: type word in wrong layout → verify correct conversion.
"""

import json
import subprocess
import time
import sys
from pathlib import Path
from itertools import product

OMFK_DIR = Path(__file__).parent.parent
LAYOUTS_JSON = OMFK_DIR / "OMFK/Sources/Resources/layouts.json"

# Load layout data
with open(LAYOUTS_JSON) as f:
    LAYOUT_DATA = json.load(f)

# Test words per language (common words that use only basic keys, no finals/special)
TEST_WORDS = {
    "en": ["hello", "world", "test", "code", "work"],
    "ru": ["привет", "текст", "слово", "работа", "код"],
    "he": ["שלום", "טקסט", "עולם", "בית", "יום"],  # Note: some have finals
}

# Layouts to test (grouped by language)
LAYOUTS = {
    "en": [
        ("us", "U.S."),
        ("abc", "ABC"),
        ("british", "British"),
        ("british_pc", "British PC"),
        ("usinternational_pc", "US International PC"),
        ("colemak", "Colemak"),
        ("dvorak", "Dvorak"),
    ],
    "ru": [
        ("russian", "Russian Mac"),
        ("russianwin", "Russian PC"),
        ("russian_phonetic", "Russian Phonetic"),
    ],
    "he": [
        ("hebrew", "Hebrew Mac"),
        ("hebrew_pc", "Hebrew PC"),
        ("hebrew_qwerty", "Hebrew QWERTY"),
    ],
}


def build_char_to_key_map(layout_id: str) -> dict:
    """Build reverse map: character → (key_name, modifier)"""
    char_map = {}
    for key_name, layouts in LAYOUT_DATA["map"].items():
        if layout_id not in layouts:
            continue
        mods = layouts[layout_id]
        for mod, char in mods.items():
            if char and char not in char_map:
                char_map[char] = (key_name, mod)
    return char_map


def convert_word(word: str, from_layout: str, to_layout: str) -> str | None:
    """Convert word from one layout to another using the mapping."""
    from_map = build_char_to_key_map(from_layout)
    
    result = []
    for char in word:
        if char in from_map:
            key_name, mod = from_map[char]
            # Get target character for same key+mod
            target_layouts = LAYOUT_DATA["map"].get(key_name, {})
            target_mods = target_layouts.get(to_layout, {})
            target_char = target_mods.get(mod)
            if target_char:
                result.append(target_char)
            else:
                return None  # Can't convert
        elif char in " \t\n":
            result.append(char)
        else:
            return None  # Character not in layout
    
    return "".join(result)


def generate_test_matrix():
    """Generate all test cases: (typed_text, expected, source_layout, target_layout, word, description)"""
    tests = []
    
    # For each target language word
    for target_lang, words in TEST_WORDS.items():
        target_layouts = LAYOUTS[target_lang]
        
        # For each source language (wrong layout)
        for source_lang in LAYOUTS.keys():
            if source_lang == target_lang:
                continue  # Skip same language
            
            source_layouts = LAYOUTS[source_lang]
            
            # For each combination of source and target layouts
            for (src_id, src_name), (tgt_id, tgt_name) in product(source_layouts, target_layouts):
                for word in words:
                    # What would be typed if user types target word on source layout?
                    typed = convert_word(word, tgt_id, src_id)
                    if typed and typed != word:
                        tests.append({
                            "typed": typed,
                            "expected": word,
                            "source_layout": src_id,
                            "target_layout": tgt_id,
                            "source_name": src_name,
                            "target_name": tgt_name,
                            "target_lang": target_lang,
                            "desc": f"{word} ({tgt_name}) typed on {src_name}",
                        })
    
    return tests


def print_matrix_summary():
    """Print summary of test matrix."""
    tests = generate_test_matrix()
    
    print("OMFK Layout Matrix Test Generator")
    print("=" * 70)
    print(f"Total test cases: {len(tests)}")
    print()
    
    # Group by source→target language
    by_pair = {}
    for t in tests:
        src_lang = None
        tgt_lang = t["target_lang"]
        for lang, layouts in LAYOUTS.items():
            if any(l[0] == t["source_layout"] for l in layouts):
                src_lang = lang
                break
        
        pair = f"{src_lang}→{tgt_lang}"
        if pair not in by_pair:
            by_pair[pair] = []
        by_pair[pair].append(t)
    
    print("By language pair:")
    for pair, pair_tests in sorted(by_pair.items()):
        print(f"  {pair}: {len(pair_tests)} tests")
    
    print()
    print("Sample tests:")
    for t in tests[:10]:
        print(f"  '{t['typed']}' → '{t['expected']}' ({t['desc']})")
    
    if len(tests) > 10:
        print(f"  ... and {len(tests) - 10} more")
    
    return tests


def run_conversion_test(typed: str, expected: str, desc: str) -> tuple[bool, str]:
    """Run single conversion test using OMFK. Returns (passed, actual)."""
    # This would need OMFK running and TextEdit open
    # For now, just use the LayoutMapper directly via swift
    
    # Quick test via command line
    result = subprocess.run(
        ["swift", "run", "omfk-test", typed],
        cwd=OMFK_DIR,
        capture_output=True,
        text=True,
        timeout=10
    )
    
    if result.returncode == 0:
        actual = result.stdout.strip()
        return actual == expected, actual
    
    return False, f"ERROR: {result.stderr}"


def export_test_cases(output_file: Path):
    """Export test cases to JSON for use by other test runners."""
    tests = generate_test_matrix()
    
    with open(output_file, "w") as f:
        json.dump(tests, f, indent=2, ensure_ascii=False)
    
    print(f"Exported {len(tests)} test cases to {output_file}")


def verify_mappings():
    """Verify that all layout mappings are consistent."""
    print("\nVerifying layout mappings...")
    
    issues = []
    
    for layout_id, layout_name in [(l[0], l[1]) for layouts in LAYOUTS.values() for l in layouts]:
        char_map = build_char_to_key_map(layout_id)
        
        if len(char_map) < 30:
            issues.append(f"{layout_name} ({layout_id}): only {len(char_map)} characters mapped")
    
    if issues:
        print("Issues found:")
        for issue in issues:
            print(f"  ⚠️  {issue}")
    else:
        print("All mappings OK")
    
    return len(issues) == 0


def test_specific_conversion(word: str, from_layout: str, to_layout: str):
    """Test a specific conversion and show details."""
    print(f"\nConverting '{word}' from {to_layout} → {from_layout}:")
    
    from_map = build_char_to_key_map(from_layout)
    to_map = build_char_to_key_map(to_layout)
    
    typed = convert_word(word, to_layout, from_layout)
    print(f"  Typed on {from_layout}: '{typed}'")
    
    # Show character-by-character
    print(f"  Breakdown:")
    for i, char in enumerate(word):
        if char in to_map:
            key, mod = to_map[char]
            from_layouts = LAYOUT_DATA["map"].get(key, {})
            from_char = from_layouts.get(from_layout, {}).get(mod, "?")
            print(f"    '{char}' → {key}[{mod}] → '{from_char}'")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        
        if cmd == "export":
            output = Path(sys.argv[2]) if len(sys.argv) > 2 else OMFK_DIR / "test_matrix.json"
            export_test_cases(output)
        
        elif cmd == "verify":
            verify_mappings()
        
        elif cmd == "test" and len(sys.argv) >= 5:
            # test <word> <from_layout> <to_layout>
            test_specific_conversion(sys.argv[2], sys.argv[3], sys.argv[4])
        
        else:
            print("Usage:")
            print("  python matrix_test.py          # Show test matrix summary")
            print("  python matrix_test.py export   # Export test cases to JSON")
            print("  python matrix_test.py verify   # Verify layout mappings")
            print("  python matrix_test.py test <word> <from> <to>  # Test specific conversion")
    else:
        tests = print_matrix_summary()
        print()
        verify_mappings()
