#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Paths
RAW_DIR="data/raw"
PROCESSED_DIR="data/processed"
TOOLS_DIR="Tools"
RESOURCES_DIR="OMFK/Sources/Resources"

echo -e "${BLUE}==============================================${NC}"
echo -e "${GREEN}   OMFK Interactive Training Master ${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# Ensure processed dir exists
mkdir -p "$PROCESSED_DIR"

while true; do
    echo "Files available in processed data:"
    if [ -f "$PROCESSED_DIR/ru.txt" ]; then echo -e "  ${GREEN}✓${NC} ru.txt"; else echo -e "  ${RED}✗${NC} ru.txt"; fi
    if [ -f "$PROCESSED_DIR/en.txt" ]; then echo -e "  ${GREEN}✓${NC} en.txt"; else echo -e "  ${RED}✗${NC} en.txt"; fi
    if [ -f "$PROCESSED_DIR/he.txt" ]; then echo -e "  ${GREEN}✓${NC} he.txt"; else echo -e "  ${RED}✗${NC} he.txt"; fi
    echo ""
    
    echo "Choose an action:"
    echo "  1) 📦 Extract Raw Wikipedia Dumps (prepare real data)"
    echo "  2) 📊 Train N-gram Models (requires extracted data)"
    echo "  3) 🧠 Train CoreML Model (requires extracted data for best results)"
    echo "  4) ✅ Run Tests"
    echo "  5) 💬 Import Telegram Chat Exports (append to corpus)"
    echo "  q) Quit"
    echo ""
    read -p "Option: " choice
    echo ""
    
    case $choice in
        1)
            echo -e "${BLUE}--- Extracting Dumps ---${NC}"
            # RU
            if [ -f "$RAW_DIR/ruwiki-latest-pages-articles-multistream1.xml-p1p224167.bz2" ]; then
                echo "Extracting Russian dump (limit 50k articles)..."
                python3 Tools/Shared/extract_corpus.py --input "$RAW_DIR/ruwiki-latest-pages-articles-multistream1.xml-p1p224167.bz2" --output "$PROCESSED_DIR/ru.txt" --limit 50000
            else
                echo -e "${RED}Russian dump not found in $RAW_DIR${NC}"
            fi
            
            # EN
            if [ -f "$RAW_DIR/enwiki-latest-pages-articles-multistream1.xml-p1p41242.bz2" ]; then
                echo "Extracting English dump (limit 50k articles)..."
                python3 Tools/Shared/extract_corpus.py --input "$RAW_DIR/enwiki-latest-pages-articles-multistream1.xml-p1p41242.bz2" --output "$PROCESSED_DIR/en.txt" --limit 50000
            else
                echo -e "${RED}English dump not found in $RAW_DIR${NC}"
            fi
            
            # HE
             if [ -f "$RAW_DIR/hewiki-latest-pages-articles-multistream.xml.bz2" ]; then
                echo "Extracting Hebrew dump (limit 50k articles)..."
                python3 Tools/Shared/extract_corpus.py --input "$RAW_DIR/hewiki-latest-pages-articles-multistream.xml.bz2" --output "$PROCESSED_DIR/he.txt" --limit 50000
            else
                echo -e "${RED}Hebrew dump not found in $RAW_DIR${NC}"
            fi
            echo -e "${GREEN}Extraction complete!${NC}"
            ;;
            
        2)
            echo -e "${BLUE}--- Training N-grams ---${NC}"
            cd Tools/NgramTrainer
            if [ -f "../../$PROCESSED_DIR/ru.txt" ]; then python3 train_ngrams.py --lang ru --input "../../$PROCESSED_DIR/ru.txt" --output "../../$RESOURCES_DIR/LanguageModels/ru_trigrams.json"; fi
            if [ -f "../../$PROCESSED_DIR/en.txt" ]; then python3 train_ngrams.py --lang en --input "../../$PROCESSED_DIR/en.txt" --output "../../$RESOURCES_DIR/LanguageModels/en_trigrams.json"; fi
            if [ -f "../../$PROCESSED_DIR/he.txt" ]; then python3 train_ngrams.py --lang he --input "../../$PROCESSED_DIR/he.txt" --output "../../$RESOURCES_DIR/LanguageModels/he_trigrams.json"; fi
            cd ../..
            echo -e "${GREEN}N-gram models updated successfully.${NC}"
            ;;
            
        3)
            echo -e "${BLUE}--- Training CoreML Model ---${NC}"
            cd Tools/CoreMLTrainer
            # Setup venv if needed
             if [ ! -d "venv" ]; then python3 -m venv venv; fi
            source venv/bin/activate
            # Ensure deps
            pip install -q -r requirements.txt
            
            # Generate data
            echo "Generating training data from corpus (this may take a moment)..."
            # Path to corpus is ../../data/processed relative to Tools/CoreMLTrainer
            python3 generate_data.py --count 100000 --output training_data_real.csv --corpus_dir "../../$PROCESSED_DIR"
            
            # Train
            echo "Training (20 epochs)..."
            python3 train.py --epochs 20 --data training_data_real.csv --model_out model_production.pth
            
            # Export
            echo "Exporting..."
            python3 export.py --model_in model_production.pth --output LayoutClassifier.mlmodel
            
            # Install
            cp LayoutClassifier.mlmodel "../../$RESOURCES_DIR/"
            
            cd ../..
            echo -e "${GREEN}CoreML model trained and installed!${NC}"
            ;;
            
        4)
            echo -e "${BLUE}--- Running Verification Tests ---${NC}"
            swift test
            ;;
            
        5)
            echo -e "${BLUE}--- Importing Telegram Chat Exports ---${NC}"
            # Hardcoded paths from user request. Add more as needed.
            TELEGRAM_FILES=(
                "/Users/sasha/IdeaProjects/allthedocs/media/telegram_exports/telegramexport/result.json"
                "/Users/sasha/IdeaProjects/allthedocs/media/telegram_exports/Чат с Сашей/ChatExport_2024-08-31/result.json"
                "/Users/sasha/Desktop/m/result.json"
            )
            EXISTING_FILES=()
            for f in "${TELEGRAM_FILES[@]}"; do
                if [ -f "$f" ]; then
                    EXISTING_FILES+=("$f")
                else
                    echo -e "${YELLOW}Skipping (not found): $f${NC}"
                fi
            done
            if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
                echo "Found ${#EXISTING_FILES[@]} Telegram export file(s). Extracting..."
                python3 Tools/Shared/extract_telegram.py "${EXISTING_FILES[@]}" --output-dir "$PROCESSED_DIR"
                echo -e "${GREEN}Telegram data imported to $PROCESSED_DIR!${NC}"
            else
                echo -e "${RED}No Telegram export files found.${NC}"
            fi
            ;;
            
        q)
            echo "Exiting."
            exit 0
            ;;
            
        *)
            echo "Invalid option."
            ;;
    esac
    echo ""
    read -p "Press Enter to continue..."
    echo ""
done
