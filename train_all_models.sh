#!/bin/bash
set -e

echo "🎯 OMFK Master Training Script"
echo "======================================"
echo ""
echo "Этот скрипт обучает ВСЕ модели для OMFK:"
echo "  1. N-gram модели (RU/EN/HE) — для быстрого определения языка"
echo "  2. CoreML модель — для сложных случаев (Deep Path)"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Options
QUICK_MODE=false
if [[ "$1" == "--quick" ]]; then
    QUICK_MODE=true
    echo -e "${YELLOW}⚡ Быстрый режим (синтетические данные)${NC}"
    echo ""
fi

# ============================================
# Part 1: N-gram Models
# ============================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[Часть 1/2] N-gram модели${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd Tools/NgramTrainer

echo "Проверяю существующие модели..."
if [ -f "../../OMFK/Sources/Resources/LanguageModels/ru_trigrams.json" ] && \
   [ -f "../../OMFK/Sources/Resources/LanguageModels/en_trigrams.json" ] && \
   [ -f "../../OMFK/Sources/Resources/LanguageModels/he_trigrams.json" ]; then
    echo -e "${GREEN}✓${NC} N-gram модели уже существуют"
    echo ""
    read -p "Переобучить? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Пропускаю N-gram обучение."
    else
        echo "Обучаю N-gram модели..."
        python3 train_ngrams.py --lang ru --input corpora/ru_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/ru_trigrams.json
        python3 train_ngrams.py --lang en --input corpora/en_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/en_trigrams.json
        python3 train_ngrams.py --lang he --input corpora/he_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/he_trigrams.json
        echo -e "${GREEN}✓${NC} N-gram модели обновлены"
    fi
else
    echo "Обучаю N-gram модели (первый запуск)..."
    python3 train_ngrams.py --lang ru --input corpora/ru_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/ru_trigrams.json
    python3 train_ngrams.py --lang en --input corpora/en_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/en_trigrams.json
    python3 train_ngrams.py --lang he --input corpora/he_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/he_trigrams.json
    echo -e "${GREEN}✓${NC} N-gram модели созданы"
fi

echo ""

# ============================================
# Part 2: CoreML Model
# ============================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}[Часть 2/2] CoreML модель${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd ../CoreMLTrainer

if [ "$QUICK_MODE" = true ]; then
    ./train_quick.sh
else
    echo "Выберите режим обучения CoreML:"
    echo "  1) Быстрый (10K примеров, 5 эпох, ~5 минут)"
    echo "  2) Полный (100K примеров, 20 эпох, ~30-60 минут)"
    echo ""
    read -p "Ваш выбор (1/2): " -n 1 -r
    echo
    
    if [[ $REPLY == "1" ]]; then
        ./train_quick.sh
    else
        ./train_full.sh
    fi
fi

# ============================================
# Final Steps
# ============================================
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Финальная проверка${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cd ../..

echo "Запускаю тесты..."
swift test

echo ""
echo "======================================"
echo -e "${GREEN}✅ ВСЁ ГОТОВО!${NC}"
echo ""
echo "Модели установлены:"
echo "  • N-gram (RU/EN/HE): OMFK/Sources/Resources/LanguageModels/"
echo "  • CoreML: OMFK/Sources/Resources/LayoutClassifier.mlmodel"
echo ""
echo "Теперь можно собрать и запустить приложение:"
echo "  swift build"
echo "  swift run"
