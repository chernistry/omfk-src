#!/usr/bin/env python3
"""
Hebrew Layout Matrix Test

Tests Hebrew conversion across all layout combinations.

Hebrew layouts:
- hebrew (Mac) - positional, same physical keys as hebrew_pc
- hebrew_pc (PC) - positional  
- hebrew_qwerty (QWERTY) - PHONETIC, letters by sound (ש=w, ת=t, מ=m)

Key insight: hebrew_qwerty is phonetic, so "שלום" = "wlvM" not "akuo"
"""

import subprocess
import sys
import os
import json

OMFK_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_layouts():
    layouts_path = os.path.join(OMFK_DIR, "OMFK/Sources/Resources/layouts.json")
    with open(layouts_path) as f:
        return json.load(f)

def build_converter(layout_data):
    """Build conversion function from layout data"""
    char_to_key = {}  # layout_id -> {char: (keycode, mod)}
    key_to_char = {}  # layout_id -> {(keycode, mod): char}
    
    for layout in layout_data["layouts"]:
        lid = layout["id"]
        char_to_key[lid] = {}
        key_to_char[lid] = {}
    
    for keycode, layouts_map in layout_data["map"].items():
        for layout_id, mapping in layouts_map.items():
            if layout_id not in char_to_key:
                continue
            for mod in ["n", "s"]:
                char = mapping.get(mod)
                if char and len(char) == 1:
                    char_to_key[layout_id][char] = (keycode, mod)
                    key_to_char[layout_id][(keycode, mod)] = char
    
    def convert(text, from_layout, to_layout):
        result = []
        for char in text:
            if char in char_to_key.get(from_layout, {}):
                keycode, mod = char_to_key[from_layout][char]
                if (keycode, mod) in key_to_char.get(to_layout, {}):
                    result.append(key_to_char[to_layout][(keycode, mod)])
                else:
                    result.append(char)
            else:
                result.append(char)
        return "".join(result)
    
    return convert

def run_tests():
    print("=" * 60)
    print("HEBREW LAYOUT MATRIX TEST")
    print("=" * 60)
    
    layout_data = load_layouts()
    convert = build_converter(layout_data)
    
    # Test cases: (input, from_layout, to_layout, expected, description)
    # Hebrew Mac/PC are positional (same keys)
    # Hebrew QWERTY is phonetic (different keys!)
    
    test_cases = [
        # === POSITIONAL HEBREW (Mac & PC) ===
        # EN -> Hebrew Mac
        ("akuo", "us", "hebrew", "שלום", "EN->HE Mac: shalom"),
        (",usv", "us", "hebrew", "תודה", "EN->HE Mac: toda"),
        ("nv", "us", "hebrew", "מה", "EN->HE Mac: ma"),
        ("fi", "us", "hebrew", "כן", "EN->HE Mac: ken"),
        ("kt", "us", "hebrew", "לא", "EN->HE Mac: lo"),
        
        # EN -> Hebrew PC (same as Mac)
        ("akuo", "us", "hebrew_pc", "שלום", "EN->HE PC: shalom"),
        (",usv", "us", "hebrew_pc", "תודה", "EN->HE PC: toda"),
        
        # Hebrew Mac -> EN
        ("שלום", "hebrew", "us", "akuo", "HE Mac->EN: shalom"),
        ("תודה", "hebrew", "us", ",usv", "HE Mac->EN: toda"),
        
        # Hebrew PC -> EN
        ("שלום", "hebrew_pc", "us", "akuo", "HE PC->EN: shalom"),
        
        # === PHONETIC HEBREW (QWERTY) ===
        # EN -> Hebrew QWERTY (phonetic mapping!)
        # Note: ם (mem sofit) = Shift+M, ת = Shift+Y in QWERTY
        ("wlvM", "us", "hebrew_qwerty", "שלום", "EN->HE QWERTY: shalom (phonetic)"),
        ("Yvdh", "us", "hebrew_qwerty", "תודה", "EN->HE QWERTY: toda (phonetic)"),
        ("mh", "us", "hebrew_qwerty", "מה", "EN->HE QWERTY: ma (phonetic)"),
        ("la", "us", "hebrew_qwerty", "לא", "EN->HE QWERTY: lo (phonetic)"),
        
        # Hebrew QWERTY -> EN
        ("שלום", "hebrew_qwerty", "us", "wlvM", "HE QWERTY->EN: shalom"),
        ("תודה", "hebrew_qwerty", "us", "Yvdh", "HE QWERTY->EN: toda"),
        
        # === RUSSIAN <-> HEBREW ===
        # Russian typed on Hebrew Mac -> Hebrew
        # (user has RU active, types Hebrew word by mistake)
        
        # === CROSS-LAYOUT ===
        # Hebrew Mac -> Russian (what if user has RU layout?)
        ("שלום", "hebrew", "russianwin", None, "HE Mac->RU: shalom (check mapping)"),
    ]
    
    passed = 0
    failed = 0
    skipped = 0
    
    print("\n--- Conversion Tests ---\n")
    
    for input_text, from_l, to_l, expected, desc in test_cases:
        if expected is None:
            # Just show what we get
            result = convert(input_text, from_l, to_l)
            print(f"? {desc}")
            print(f"  {from_l} -> {to_l}: '{input_text}' -> '{result}'")
            skipped += 1
            continue
            
        result = convert(input_text, from_l, to_l)
        if result == expected:
            print(f"✓ {desc}")
            passed += 1
        else:
            print(f"✗ {desc}")
            print(f"  {from_l} -> {to_l}: '{input_text}' -> '{result}' (expected '{expected}')")
            failed += 1
    
    print(f"\n{'=' * 60}")
    print(f"Results: {passed}/{passed + failed} passed ({skipped} skipped)")
    print(f"{'=' * 60}")
    
    # Show layout comparison
    print("\n--- Hebrew Layout Comparison ---")
    print("Word      | Mac/PC (positional) | QWERTY (phonetic)")
    print("-" * 55)
    words = [("שלום", "shalom"), ("תודה", "toda"), ("מה", "ma"), ("כן", "ken"), ("לא", "lo")]
    for he_word, meaning in words:
        mac_keys = convert(he_word, "hebrew", "us")
        qwerty_keys = convert(he_word, "hebrew_qwerty", "us")
        print(f"{he_word} ({meaning:6}) | {mac_keys:19} | {qwerty_keys}")
    
    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
