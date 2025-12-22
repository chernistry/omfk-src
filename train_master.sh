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

# Non-interactive mode: `./train_master.sh 3` or `./train_master.sh --run 3`
AUTO_CHOICE=""
if [[ "${1:-}" == "--run" ]]; then
    AUTO_CHOICE="${2:-}"
elif [[ "${1:-}" =~ ^[1-6]$ ]]; then
    AUTO_CHOICE="${1:-}"
fi

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
    echo "  6) 🎬 Download OpenSubtitles (conversational HE/RU data)"
    echo "  q) Quit"
    echo ""
    if [ -n "$AUTO_CHOICE" ]; then
        choice="$AUTO_CHOICE"
        echo "Option: $choice (non-interactive)"
    else
        read -p "Option: " choice
    fi
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
            # Avoid noisy coremltools warnings for unsupported scikit-learn versions.
            pip uninstall -y scikit-learn >/dev/null 2>&1 || true

            echo "Syncing layouts.json into app resources..."
            if [ -f "../../.sdd/layouts.json" ]; then
                if [ ! -f "../../$RESOURCES_DIR/layouts.json" ] || ! cmp -s "../../.sdd/layouts.json" "../../$RESOURCES_DIR/layouts.json"; then
                    cp "../../.sdd/layouts.json" "../../$RESOURCES_DIR/layouts.json"
                fi
            fi

            BASE_MODEL="model_production.pth"
            FINETUNED_MODEL="model_production_he_qwerty.pth"
            LAYOUTS_SPEC="../../.sdd/layouts.json"

            # Ultra mode: crank up dataset + corpus usage for maximum quality (will take longer).
            ULTRA="${OMFK_ULTRA:-0}"
            if [ "$ULTRA" = "1" ]; then
                echo -e "${YELLOW}OMFK_ULTRA=1 enabled → maximizing training sizes (expect long runtimes).${NC}"
                : "${OMFK_BASE_SAMPLES:=20000000}"
                : "${OMFK_BASE_EPOCHS:=120}"
                : "${OMFK_BASE_PATIENCE:=20}"
                : "${OMFK_HE_QWERTY_SAMPLES:=2000000}"
                : "${OMFK_HE_QWERTY_EPOCHS:=30}"
                : "${OMFK_HE_QWERTY_PATIENCE:=8}"
                : "${OMFK_MAX_CORPUS_WORDS:=0}"
            fi

            BASE_SAMPLES="${OMFK_BASE_SAMPLES:-5000000}"
            BASE_EPOCHS="${OMFK_BASE_EPOCHS:-100}"
            BASE_BATCH_SIZE="${OMFK_BASE_BATCH_SIZE:-512}"
            BASE_LR="${OMFK_BASE_LR:-0.001}"
            BASE_PATIENCE="${OMFK_BASE_PATIENCE:-15}"

            HE_QWERTY_SAMPLES="${OMFK_HE_QWERTY_SAMPLES:-500000}"
            HE_QWERTY_EPOCHS="${OMFK_HE_QWERTY_EPOCHS:-20}"
            HE_QWERTY_BATCH_SIZE="${OMFK_HE_QWERTY_BATCH_SIZE:-512}"
            HE_QWERTY_LR="${OMFK_HE_QWERTY_LR:-0.0001}"
            HE_QWERTY_PATIENCE="${OMFK_HE_QWERTY_PATIENCE:-5}"

            MAX_CORPUS_WORDS="${OMFK_MAX_CORPUS_WORDS:-2000000}"
            FORCE_RETRAIN="${OMFK_FORCE_RETRAIN:-0}"
            SKIP_RETRAIN_ON_LAYOUT_CHANGE="${OMFK_SKIP_BASE_RETRAIN_ON_LAYOUT_CHANGE:-0}"

            echo -e "${BLUE}Training config:${NC} base_samples=${BASE_SAMPLES} he_qwerty_samples=${HE_QWERTY_SAMPLES} max_corpus_words=${MAX_CORPUS_WORDS}"

            should_train_base=0
            if [ "$FORCE_RETRAIN" = "1" ]; then
                echo -e "${YELLOW}OMFK_FORCE_RETRAIN=1 → will retrain base model.${NC}"
                should_train_base=1
            fi

            # If layouts spec is newer than the base model, the base model is considered stale.
            if [ "$should_train_base" = "0" ] && [ -f "$BASE_MODEL" ] && [ -f "$LAYOUTS_SPEC" ] && [ "$SKIP_RETRAIN_ON_LAYOUT_CHANGE" != "1" ]; then
                if [ "$LAYOUTS_SPEC" -nt "$BASE_MODEL" ]; then
                    echo -e "${YELLOW}Base model is older than layouts spec → retraining base model (set OMFK_SKIP_BASE_RETRAIN_ON_LAYOUT_CHANGE=1 to skip).${NC}"
                    should_train_base=1
                fi
            fi

            # Verify the checkpoint loads into current architecture; otherwise retrain.
            if [ "$should_train_base" = "0" ] && [ -f "$BASE_MODEL" ]; then
                python3 - <<'PY' || should_train_base=1
import sys, torch
from train import EnsembleModel
path = "model_production.pth"
try:
    state = torch.load(path, map_location="cpu", weights_only=True)
except TypeError:
    state = torch.load(path, map_location="cpu")
model = EnsembleModel()
model.load_state_dict(state, strict=True)
print("Base model checkpoint OK:", path)
PY
            fi
            
            # Generate data
            if [ "$should_train_base" = "1" ] || [ ! -f "$BASE_MODEL" ]; then
                echo -e "${YELLOW}Base model not found (${BASE_MODEL}). Training from scratch...${NC}"
                echo "Generating training data from corpus (${BASE_SAMPLES} samples, balanced, up to 5 words)..."
                # Path to corpus is ../../data/processed relative to Tools/CoreMLTrainer
                python3 generate_data.py \
                    --count "$BASE_SAMPLES" \
                    --balance 0.5 \
                    --max-phrase-len 5 \
                    --max-corpus-words "$MAX_CORPUS_WORDS" \
                    --output training_data_real.csv \
                    --corpus_dir "../../$PROCESSED_DIR"
                
                # Train with ALL advanced techniques
                echo "Training base model (ensemble, augmentation, mixup)..."
                echo "This will take 30-60 minutes..."
                python3 train.py --epochs "$BASE_EPOCHS" --batch_size "$BASE_BATCH_SIZE" --lr "$BASE_LR" --patience "$BASE_PATIENCE" \
                    --ensemble --augment --mixup \
                    --data training_data_real.csv --model_out "$BASE_MODEL"
            else
                echo -e "${GREEN}Found base model: ${BASE_MODEL}${NC}"
            fi

            echo -e "${BLUE}--- Fine-tuning for Hebrew QWERTY sofits (Ticket 23) ---${NC}"
            echo "Generating focused he_qwerty data (${HE_QWERTY_SAMPLES} samples)..."
            python3 generate_data.py \
                --count "$HE_QWERTY_SAMPLES" \
                --balance 0.3 \
                --max-phrase-len 5 \
                --max-corpus-words "$MAX_CORPUS_WORDS" \
                --output training_data_he_qwerty.csv \
                --corpus_dir "../../$PROCESSED_DIR" \
                --focus-layout he_qwerty

            echo "Fine-tuning (lr=${HE_QWERTY_LR}, epochs=${HE_QWERTY_EPOCHS})..."
            python3 train.py --epochs "$HE_QWERTY_EPOCHS" --batch_size "$HE_QWERTY_BATCH_SIZE" --lr "$HE_QWERTY_LR" --patience "$HE_QWERTY_PATIENCE" \
                --ensemble --finetune --model_in "$BASE_MODEL" --augment \
                --data training_data_he_qwerty.csv --model_out "$FINETUNED_MODEL"
            
            # Export
            echo "Exporting to CoreML..."
            python3 export.py --model_in "$FINETUNED_MODEL" --output LayoutClassifier.mlmodel --ensemble

            echo "Validating CoreML export vs PyTorch..."
            python3 validate_export.py --ensemble --model_in "$FINETUNED_MODEL" --mlmodel LayoutClassifier.mlmodel --samples 20 --tol 0.01
            
            # Install
            cp LayoutClassifier.mlmodel "../../$RESOURCES_DIR/"
            
            cd ../..
            echo "Running Swift test suite..."
            swift test
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
            
        6)
            echo -e "${BLUE}--- Downloading OpenSubtitles (conversational data) ---${NC}"
            cd Tools/CoreMLTrainer
            source venv/bin/activate 2>/dev/null || python3 -m venv venv && source venv/bin/activate
            python3 download_subtitles.py --only he_mono ru_mono --limit 2000000
            
            echo -e "${YELLOW}Merging subtitles into main corpus...${NC}"
            cd ../..
            if [ -f "$PROCESSED_DIR/subtitles_he.txt" ]; then
                cat "$PROCESSED_DIR/subtitles_he.txt" >> "$PROCESSED_DIR/he.txt"
                echo -e "${GREEN}  Merged Hebrew subtitles into he.txt${NC}"
            fi
            if [ -f "$PROCESSED_DIR/subtitles_ru.txt" ]; then
                cat "$PROCESSED_DIR/subtitles_ru.txt" >> "$PROCESSED_DIR/ru.txt"
                echo -e "${GREEN}  Merged Russian subtitles into ru.txt${NC}"
            fi
            echo -e "${GREEN}OpenSubtitles data imported!${NC}"
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
    if [ -n "$AUTO_CHOICE" ]; then
        exit 0
    fi
    read -p "Press Enter to continue..."
    echo ""
done
