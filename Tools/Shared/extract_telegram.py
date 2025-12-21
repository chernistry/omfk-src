import json
import argparse
import os
import re

def detect_language(text):
    # Simple heuristic based on character set
    ru_chars = set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
    he_chars = set("אבגדהוזחטיכלמנסעפצקרשתךםןףץ")
    
    count_ru = sum(1 for c in text.lower() if c in ru_chars)
    count_he = sum(1 for c in text.lower() if c in he_chars)
    count_en = sum(1 for c in text.lower() if 'a' <= c <= 'z')
    
    total = len(text.replace(" ", ""))
    if total == 0: return None
    
    if count_ru > count_en and count_ru > count_he: return "ru"
    if count_he > count_en and count_he > count_ru: return "he"
    if count_en > count_ru and count_en > count_he: return "en"
    return None

def extract_telegram(input_files, output_dir):
    print(f"Extracting Telegram messages from {len(input_files)} files...")
    
    extracted = {"ru": [], "en": [], "he": []}
    
    for input_file in input_files:
        if not os.path.exists(input_file):
            print(f"Skipping {input_file} (not found)")
            continue
            
        print(f"Processing {input_file}...")
        try:
            with open(input_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
                
            messages = []
            # Handle different export formats (some have "messages" at root, some in "chats.list[].messages")
            if "messages" in data:
                messages = data["messages"]
            elif "chats" in data and "list" in data["chats"]:
                for chat in data["chats"]["list"]:
                    if "messages" in chat:
                        messages.extend(chat["messages"])
            
            print(f"  Found {len(messages)} messages.")
            
            for msg in messages:
                # Extract text content (can be string or list of entities)
                text = msg.get("text", "")
                if isinstance(text, list):
                    # Combine text entities
                    full_text = ""
                    for entity in text:
                        if isinstance(entity, str):
                            full_text += entity
                        elif isinstance(entity, dict):
                            full_text += entity.get("text", "")
                    text = full_text
                
                if not isinstance(text, str): continue
                
                text = text.strip()
                if not text: continue
                
                # Language detection
                lang = detect_language(text)
                if lang:
                    # Clean text slightly (remove newlines)
                    clean = re.sub(r'\s+', ' ', text)
                    if len(clean) > 2:
                        extracted[lang].append(clean)
                        
        except Exception as e:
            print(f"Error reading {input_file}: {e}")
            
    # Write to output files (append mode)
    for lang, lines in extracted.items():
        if not lines: continue
        
        outfile = os.path.join(output_dir, f"{lang}.txt")
        print(f"Appending {len(lines)} {lang} lines to {outfile}...")
        
        with open(outfile, 'a', encoding='utf-8') as f:
            for line in lines:
                f.write(line + "\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('inputs', nargs='+', help="Input JSON files")
    parser.add_argument('--output-dir', required=True, help="Directory to append {lang}.txt files")
    args = parser.parse_args()
    
    extract_telegram(args.inputs, args.output_dir)
