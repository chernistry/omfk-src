import json
import random
import os
import argparse

# Seed lexicons for MVP (Top ~50 words per language to capture reasonable N-grams)
# In a real production run, download_corpus.py would populate these.
# UPDATED: Added common conversational/slang/profanity words that might be missing from formal Wikipedia data.
COMMON_SEEDS = {
    "en": "hello hi lol ok wow thanks yes no maybe please sorry bro dude wtf omg idc idk u r ur".split(),
    "ru": "привет пока да нет ок спс пж лол кек сука блять нахуй пиздец говно залупа мудак педрило ебок привет как дела че кого хах".split(),
    "he": "שלום היי ביי טוב לא כן תודה בבקשה סבבה יאללה אח שלי חיים כפרה זין מניאק שרמוטה בן זונה".split()
}

SEEDS = {
    "en": "the be to of and a in that have I it for not on with he as you do at this but his by from they we say her she or an will my one all would there their what so up out if about who get which go me when make can like time no just him know take people into year your good some could them see other than then now look only come its over think also back after use two how our work first well way even new want because any these give day most us".split() + COMMON_SEEDS["en"],
    "ru": "и в не на я быть с он что а этот к это по ты они мы она который то из но все у за свой же весь год вы мочь человек о один такой какой только себя ее тот как сказать дело сам для когда очень время вот чтобы до место иметь раз если жизнь уж под где ни слово быть даже идти там мочь сейчас лицо друг глаз теперь тоже здесь кто потом стать ли ничто работа дом надо голова стоять первый".split() + COMMON_SEEDS["ru"],
    "he": "את ב של לא ה ל זה כי גם היה עם על אני מה כן אם הוא כל אבל יש לא רק או מי זה אתה איך מתי איפה שם כאן למה מי היה כדי פעם תמיד טוב יום בית איש דבר עולם חיים משפחה אהבה זמן עכשיו יותר מאוד רוצה צריך יכול עושה רואה יודע חושב אומר בא דרך מים לחם שמש ירח ארץ עיר ספר ילד".split() + COMMON_SEEDS["he"]
}

CLASSES = [
    'ru', 'en', 'he',
    'ru_from_en', 'he_from_en',
    'en_from_ru', 'en_from_he',
    'he_from_ru', 'ru_from_he'
]

def load_layout_map(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # We need to build char->char maps for layout conversion.
    # Map key: (source_layout, target_layout) -> {source_char: target_char}
    
    # Primary layouts to use
    # Primary layouts to use (Lists to support multiple variants)
    layouts = {
        'en': ['en_us'],
        'ru': ['ru_pc', 'ru_phonetic_yasherty'],
        'he': ['he_standard', 'he_qwerty', 'he_pc'] # Support ALL common Hebrew layouts
    }
    
    maps = {}
    
    key_map = data['map']
    
    def get_char(k, l_id, mod='n'):
        val = key_map.get(k, {}).get(l_id, {})
        if val:
            return val.get(mod)
        return None

    # Build maps between all pairs
    # Since we have lists of layouts, we generate a map for each specific layout pair
    # and store them in a list under the language pair key.
    
    for src_lang, src_layout_list in layouts.items():
        for tgt_lang, tgt_layout_list in layouts.items():
            if src_lang == tgt_lang: continue
            
            # We want to support: User intends src_lang, but is typing on tgt_layout.
            # Wait, the class naming is "tgt_from_src" (e.g., "ru_from_en").
            # This means: "Detected as RU, but coming from EN layout input".
            # My logic in generate_sample:
            # intended_lang = ru
            # typed_layout_lang = en
            # We need map: RU -> EN.
            # i.e., what keys does user press to type RU word?
            # And what characters do those keys produce on EN layout?
            
            # The user presses a physical key.
            # If user intends RU (e.g. "привет"), they press keys G, H, ...
            # Wait. "привет" is typed on `ru_pc`.
            # Keys: G (п), H (р), B (и), ...
            # Make sure we use the CORRECT RU layout they utilize.
            # If they use `ru_pc`, they press `KeyG`.
            # If they are on `en_us` layout, `KeyG` produces `g`.
            
            # So, for each possible intended layout (e.g. `ru_pc`):
            # And each possible actual layout (e.g. `en_us`):
            # We create a map.
            
            pair_key = f"{tgt_lang}_from_{src_lang}" # e.g. en_from_ru (EN chars from RU intention)
            
            if pair_key not in maps:
                maps[pair_key] = []
            
            for s_layout in src_layout_list:
                for t_layout in tgt_layout_list:
                    
                    mapping = {}
                    for key_code in key_map:
                        # Character produced by key in INTENDED layout (s_layout)
                        # This works backwards:
                        # We have intended char (e.g. 'п').
                        # We find key code that produces it in s_layout (KeyG).
                        # We find char produced by that key code in t_layout ('g').
                        
                        # Optimization: Layouts.json map is Key -> Layout -> Char.
                        # So for each KEY, we map s_char -> t_char
                        
                        # Normal
                        s_char = get_char(key_code, s_layout, 'n')
                        t_char = get_char(key_code, t_layout, 'n')
                        if s_char and t_char:
                            mapping[s_char] = t_char
                        
                        # Shift
                        s_char_s = get_char(key_code, s_layout, 's')
                        t_char_s = get_char(key_code, t_layout, 's')
                        if s_char_s and t_char_s:
                            mapping[s_char_s] = t_char_s
                    
                    maps[pair_key].append(mapping)
            
    return maps

def convert_text(text, mapping):
    return "".join(mapping.get(c, c) for c in text)

def generate_sample(class_name, maps):
    # Determine source language and transformation
    if class_name in ['ru', 'en', 'he']:
        src_lang = class_name
        text = random.choice(SEEDS[src_lang])
        return text, class_name
    
    parts = class_name.split('_from_') # e.g. ['ru', 'en']
    intended_lang = parts[0]
    typed_layout_lang = parts[1]
    
    # We need a map Intended -> Typed.
    # Logic revision from step 308:
    # "ru_from_en" means "It LOOKS like RU, but comes from EN layout"?
    # NO. The classes are defined in ticket 17 as:
    # "ru_from_en": Russian text that was typed on English layout (nonsense EN chars).
    # Wait, let's double check this definition. It's crucial.
    # Most language detectors output the LANGUAGE.
    # If I type "ghbdtn", the detector should say "Russian".
    # But here we have specific classes like `ru_from_en`.
    # Why?
    # Because "ghbdtn" is NOT Russian text. It is English text ("g", "h", ...).
    # So a standard detector says "English".
    # Our `ru_from_en` class means: "This is garbage English that maps to valid Russian".
    # So the LABEL `ru_from_en` allows the Router to say: "Ah, this is 'Russian from English layout'".
    # So input is EN chars. Intention is RU.
    # So we map RU seeds -> EN chars.
    
    # Map key: `typed_from_intended`
    # e.g. `en_from_ru` in my maps dict logic.
    
    map_key = f"{typed_layout_lang}_from_{intended_lang}"
    available_maps = maps.get(map_key, [])
    
    if not available_maps:
        return "x", class_name
        
    # Randomly choose one mapping combination (e.g. ru_pc -> en_us)
    # This ensures we train on ALL variants.
    mapping = random.choice(available_maps)
        
    word = random.choice(SEEDS[intended_lang])
    
    # Fixed length handling (1-3 words)
    num_words = random.randint(1, 2)
    for _ in range(num_words - 1):
        word += " " + random.choice(SEEDS[intended_lang])
        
    converted = convert_text(word, mapping)
    return converted, class_name

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='training_data.csv')
    parser.add_argument('--count', type=int, default=10000)
    parser.add_argument('--layouts', default='../../.sdd/layouts.json')
    parser.add_argument('--corpus_dir', default=None, help="Directory with {lang}.txt corpus files")
    args = parser.parse_args()
    
    maps = load_layout_map(args.layouts)
    
    # Load corpus words if provided
    if args.corpus_dir:
        print(f"Loading corpus from {args.corpus_dir}...")
        for lang in ['ru', 'en', 'he']:
            path = os.path.join(args.corpus_dir, f"{lang}.txt")
            if os.path.exists(path):
                print(f"  Loading {lang}.txt...", end='')
                with open(path, 'r', encoding='utf-8') as f:
                    # Read phrases and split into words/short phrases
                    words = []
                    for i, line in enumerate(f):
                        # Simple tokenizer: split by space
                        parts = line.strip().split()
                        words.extend([p for p in parts if len(p) > 2]) # Filter very short noise
                        # Removed limit to use full corpus
                    
                    if words:
                        SEEDS[lang] = words
                        print(f" {len(words)} words loaded.")
                    else:
                        print(" Empty or error.")
            else:
                print(f"  Warning: {path} not found. Using default seeds.")
    
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write("text,label\n")
        for _ in range(args.count):
            cls = random.choice(CLASSES)
            text, label = generate_sample(cls, maps)
            # Simple CSV escaping
            if ',' in text or '"' in text:
                text = f'"{text.replace("\"", "\"\"")}"'
            f.write(f"{text},{label}\n")
            
    print(f"Generated {args.count} samples to {args.output}")

if __name__ == "__main__":
    main()
