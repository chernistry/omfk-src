#!/bin/bash
set -e

echo "🚀 OMFK CoreML Full Training Pipeline"
echo "======================================"
echo ""
echo "⚠️  ВНИМАНИЕ: Это полный пайплайн для production."
echo "    Займет ~30-60 минут."
echo ""
echo "Для быстрого теста используйте train_quick.sh"
echo ""
read -p "Продолжить? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 1
fi

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Step 1: Setup
echo -e "${BLUE}[1/6]${NC} Проверка виртуального окружения..."
if [ ! -d "venv" ]; then
    echo "  → Создаю venv..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -q -r requirements.txt
echo -e "${GREEN}✓${NC} Окружение готово"
echo ""

# Step 2: Download corpus (TODO)
echo -e "${BLUE}[2/6]${NC} Скачивание Wikipedia корпусов..."
echo -e "${YELLOW}⚠${NC}  download_corpus.py еще не реализован."
echo "  Используем расширенные синтетические данные."
echo ""

# Step 3: Generate large dataset
DATASET="${OMFK_DATASET:-training_data_combined.csv}"
if [ -f "$DATASET" ]; then
    echo -e "${BLUE}[3/6]${NC} Используем существующий датасет: ${DATASET}"
else
    DATASET="training_data_large.csv"
    echo -e "${BLUE}[3/6]${NC} Генерация большого датасета (100,000 примеров) → ${DATASET}..."
    python3 generate_data.py --count 100000 --output "$DATASET"
    echo -e "${GREEN}✓${NC} Данные сгенерированы: ${DATASET}"
fi
echo ""

# Step 4: Train with more epochs
echo -e "${BLUE}[4/6]${NC} Обучение модели (20 эпох, ~15-20 минут)..."
python3 train.py --epochs 20 --ensemble --augment --mixup --data "$DATASET" --model_out model_production.pth
echo -e "${GREEN}✓${NC} Модель обучена: model_production.pth"
echo ""

# Step 5: Export
echo -e "${BLUE}[5/6]${NC} Экспорт в CoreML..."
python3 export.py --model_in model_production.pth --output LayoutClassifier.mlmodel --ensemble
echo -e "${GREEN}✓${NC} CoreML модель создана"
echo ""

# Step 6: Install
echo -e "${BLUE}[6/6]${NC} Установка в проект..."
cp LayoutClassifier.mlmodel ../../OMFK/Sources/Resources/
echo -e "${GREEN}✓${NC} Модель установлена"
echo ""

echo "======================================"
echo -e "${GREEN}✅ Production модель готова!${NC}"
echo ""
echo "Запустите тесты для проверки:"
echo "  cd ../.."
echo "  swift test"
