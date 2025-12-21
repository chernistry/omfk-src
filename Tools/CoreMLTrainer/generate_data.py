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
    layouts = {
        'en': 'en_us',
        'ru': 'ru_pc',
        'he': 'he_qwerty' # Switched to he_qwerty based on user feedback/logs (phonetic mapping)
    }
    
    maps = {}
    
    key_map = data['map']
    
    def get_char(k, l_id, mod='n'):
        val = key_map.get(k, {}).get(l_id, {})
        if val:
            return val.get(mod)
        return None

    # Build maps between all pairs
    for src_lang, src_layout in layouts.items():
        for tgt_lang, tgt_layout in layouts.items():
            if src_lang == tgt_lang: continue
            
            mapping = {}
            for key_code in key_map:
                # Normal
                s_char = get_char(key_code, src_layout, 'n')
                t_char = get_char(key_code, tgt_layout, 'n')
                if s_char and t_char:
                    mapping[s_char] = t_char
                
                # Shift
                s_char_s = get_char(key_code, src_layout, 's')
                t_char_s = get_char(key_code, tgt_layout, 's')
                if s_char_s and t_char_s:
                    mapping[s_char_s] = t_char_s
            
            maps[f"{tgt_lang}_from_{src_lang}"] = mapping # e.g. ru_from_en maps en chars to ru
            
    return maps

def convert_text(text, mapping):
    return "".join(mapping.get(c, c) for c in text)

def generate_sample(class_name, maps):
    # Determine source language and transformation
    if class_name in ['ru', 'en', 'he']:
        src_lang = class_name
        text = random.choice(SEEDS[src_lang])
        return text, class_name
    
    # Negative classes: key is like "ru_from_en" (Russian typed on EN layout)
    # This means the USER MEANT Russian, but WAS ON English layout.
    # So the input characters are English, but the latent meaning is Russian.
    # Wait, let's verify definition.
    # architect.md: "ruFromEnLayout" -> Input is EN chars, intended is RU.
    # ticket 17: 'ru_from_en' # Russian typed on EN layout (ghbdtn -> привет)
    # The INPUT to the classifier will be "ghbdtn".
    # So we take a RU word, and reverse-map it to EN keys?
    # Or do we take a RU word (intended) and map it to EN (typed)?
    
    # "Russian typed on EN layout" implies:
    # Intention: Russian word "привет"
    # Physical keys pressed: G, H, B, D, T, N (on QWERTY)
    # Screen shows: "ghbdtn"
    # So we need to map RU -> EN.
    
    # Logic:
    # Target Class: ru_from_en
    # Source Word (Intended): from SEEDS['ru']
    # Output Text (Screen): Map RU chars to EN chars.
    
    parts = class_name.split('_from_') # e.g. ['ru', 'en']
    intended_lang = parts[0]
    typed_layout_lang = parts[1]
    
    # We need a map Intended -> Typed.
    # The maps dict keys are named "tgt_from_src". This naming is tricky.
    # My load_layout_map logic: `maps[f"{tgt_lang}_from_{src_lang}"] = mapping`
    # maps en chars to ru.
    # So `maps['ru_from_en']` converts 'ghbdtn' -> 'привет'.
    # We want the REVERSE generation here.
    # We start with 'привет' (RU id) and want to generate 'ghbdtn' (EN id).
    # So we need `maps['en_from_ru']`.
    
    # Example: "ru_from_en" (Class)
    # Intention: RU. Typed: EN.
    # Sample generator: Pick RU word. Convert using RU->EN map.
    # RU->EN map name in my dict: "en_from_ru"
    
    map_key = f"{typed_layout_lang}_from_{intended_lang}"
    mapping = maps.get(map_key)
    
    if not mapping:
        # Fallback if map missing (shouldn't happen with full layouts)
        return "x", class_name
        
    word = random.choice(SEEDS[intended_lang])
    # Optional: combine words to make phrases?
    # The classifier input is fixed length (12 chars). 
    # Let's make 1-3 word phrases.
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
                        if i > 50000: break # Limit memory usage for now
                    
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
