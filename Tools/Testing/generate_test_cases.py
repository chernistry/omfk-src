#!/usr/bin/env python3
"""Generate test cases for layout detection from layouts.json and corpus data."""
import json
import random
import os
import argparse

CLASSES = ['ru', 'en', 'he', 'ru_from_en', 'he_from_en', 'en_from_ru', 'en_from_he', 'he_from_ru', 'ru_from_he']

# Minimal seeds for testing (real corpus loaded if available)
SEEDS = {
    "en": ["hello", "world", "computer", "keyboard", "language", "testing", "system", "program", "function", "variable"],
    "ru": ["привет", "мир", "компьютер", "клавиатура", "язык", "тестирование", "система", "программа", "функция", "переменная"],
    "he": ["שלום", "עולם", "מחשב", "מקלדת", "שפה", "בדיקה", "מערכת", "תוכנית", "פונקציה", "משתנה"]
}

def load_layout_map(json_path):
    """Load layouts.json and build character conversion maps."""
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    layouts = {'en': ['en_us'], 'ru': ['ru_pc'], 'he': ['he_standard', 'he_qwerty']}
    maps = {}
    key_map = data['map']
    
    def get_char(k, l_id, mod='n'):
        return key_map.get(k, {}).get(l_id, {}).get(mod)

    for src_lang, src_layouts in layouts.items():
        for tgt_lang, tgt_layouts in layouts.items():
            if src_lang == tgt_lang:
                continue
            pair_key = f"{tgt_lang}_from_{src_lang}"
            if pair_key not in maps:
                maps[pair_key] = []
            
            for s_layout in src_layouts:
                for t_layout in tgt_layouts:
                    mapping = {}
                    for key_code in key_map:
                        for mod in ['n', 's']:
                            s_char = get_char(key_code, s_layout, mod)
                            t_char = get_char(key_code, t_layout, mod)
                            if s_char and t_char:
                                mapping[s_char] = t_char
                    if mapping:
                        maps[pair_key].append(mapping)
    return maps

def convert_text(text, mapping):
    return "".join(mapping.get(c, c) for c in text)

def generate_test_case(class_name, maps, seeds):
    """Generate a single test case for the given class."""
    if class_name in ['ru', 'en', 'he']:
        word = random.choice(seeds[class_name])
        return {"input": word, "expected_class": class_name, "intended_text": word}
    
    parts = class_name.split('_from_')
    intended_lang, typed_layout_lang = parts[0], parts[1]
    map_key = f"{typed_layout_lang}_from_{intended_lang}"
    available_maps = maps.get(map_key, [])
    
    if not available_maps:
        return None
    
    mapping = random.choice(available_maps)
    word = random.choice(seeds[intended_lang])
    converted = convert_text(word, mapping)
    
    return {"input": converted, "expected_class": class_name, "intended_text": word}

def main():
    parser = argparse.ArgumentParser(description='Generate test cases for layout detection')
    parser.add_argument('--layouts', default='../../.sdd/layouts.json', help='Path to layouts.json')
    parser.add_argument('--corpus_dir', default=None, help='Directory with {lang}.txt corpus files')
    parser.add_argument('--output', default='test_cases.json', help='Output JSON file')
    parser.add_argument('--per_class', type=int, default=20, help='Test cases per class')
    args = parser.parse_args()
    
    maps = load_layout_map(args.layouts)
    seeds = dict(SEEDS)
    
    # Load corpus if available
    if args.corpus_dir:
        for lang in ['ru', 'en', 'he']:
            path = os.path.join(args.corpus_dir, f"{lang}.txt")
            if os.path.exists(path):
                with open(path, 'r', encoding='utf-8') as f:
                    words = [w for line in f for w in line.strip().split() if 3 <= len(w) <= 15][:500]
                    if words:
                        seeds[lang] = words
    
    test_cases = []
    for cls in CLASSES:
        for _ in range(args.per_class):
            case = generate_test_case(cls, maps, seeds)
            if case:
                test_cases.append(case)
    
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump({"test_cases": test_cases, "total": len(test_cases)}, f, ensure_ascii=False, indent=2)
    
    print(f"Generated {len(test_cases)} test cases to {args.output}")
    for cls in CLASSES:
        count = sum(1 for tc in test_cases if tc['expected_class'] == cls)
        print(f"  {cls}: {count}")

if __name__ == "__main__":
    main()
