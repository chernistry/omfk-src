#!/bin/bash
set -e

echo "🚀 OMFK CoreML Quick Training Pipeline"
echo "======================================"
echo ""
echo "Это быстрый вариант для MVP (синтетические данные)."
echo "Для production используйте train_full.sh"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Setup venv
echo -e "${BLUE}[1/5]${NC} Проверка виртуального окружения..."
if [ ! -d "venv" ]; then
    echo "  → Создаю venv..."
    python3 -m venv venv
fi

echo "  → Активирую venv..."
source venv/bin/activate

echo "  → Устанавливаю зависимости..."
pip install -q -r requirements.txt
echo -e "${GREEN}✓${NC} Окружение готово"
echo ""

# Step 2: Generate data
DATASET="${OMFK_DATASET:-training_data_combined.csv}"
if [ -f "$DATASET" ]; then
    echo -e "${BLUE}[2/5]${NC} Используем существующий датасет: ${DATASET}"
else
    DATASET="training_data_quick.csv"
    echo -e "${BLUE}[2/5]${NC} Генерация тренировочных данных (10,000 примеров) → ${DATASET}..."
    python3 generate_data.py --count 10000 --output "$DATASET"
    echo -e "${GREEN}✓${NC} Данные сгенерированы: ${DATASET}"
fi
echo ""

# Step 3: Train
echo -e "${BLUE}[3/5]${NC} Обучение модели (5 эпох, ~2-3 минуты)..."
python3 train.py --epochs 5 --ensemble --augment --mixup --data "$DATASET" --model_out model.pth
echo -e "${GREEN}✓${NC} Модель обучена: model.pth"
echo ""

# Step 4: Export
echo -e "${BLUE}[4/5]${NC} Экспорт в CoreML..."
python3 export.py --model_in model.pth --output LayoutClassifier.mlmodel --ensemble
echo -e "${GREEN}✓${NC} CoreML модель создана: LayoutClassifier.mlmodel"
echo ""

# Step 5: Copy to project
echo -e "${BLUE}[5/5]${NC} Копирование в проект..."
cp LayoutClassifier.mlmodel ../../OMFK/Sources/Resources/
echo -e "${GREEN}✓${NC} Модель установлена в проект"
echo ""

echo "======================================"
echo -e "${GREEN}✅ Готово!${NC}"
echo ""
echo "Теперь запустите тесты:"
echo "  cd ../.."
echo "  swift test --filter CoreMLLayoutClassifierTests"
echo ""
echo "Или соберите проект:"
echo "  swift build"
