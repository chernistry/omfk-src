# OMFK — Обучение Моделей

## 🚀 Быстрый старт

Для обучения **всех моделей** одной командой:

```bash
./train_all_models.sh
```

Или в быстром режиме (без вопросов):
```bash
./train_all_models.sh --quick
```

---

## 📚 Что включено?

### 1. **N-gram модели** (Fast Path)
- **Где**: `Tools/NgramTrainer/`
- **Что делают**: Быстрое определение языка по триграммам
- **Модели**: RU, EN, HE
- **Размер**: ~50-100 KB каждая

### 2. **CoreML модель** (Deep Path)
- **Где**: `Tools/CoreMLTrainer/`
- **Что делает**: Определение сложных случаев (неправильная раскладка)
- **Размер**: ~150 KB

---

## 🎯 Пошаговое обучение

### Вариант 1: N-gram модели

```bash
cd Tools/NgramTrainer
python3 train_ngrams.py --lang ru --input corpora/ru_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/ru_trigrams.json
python3 train_ngrams.py --lang en --input corpora/en_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/en_trigrams.json
python3 train_ngrams.py --lang he --input corpora/he_sample.txt --output ../../OMFK/Sources/Resources/LanguageModels/he_trigrams.json
```

### Вариант 2: CoreML модель

**Быстро (MVP)**:
```bash
cd Tools/CoreMLTrainer
./train_quick.sh
```

**Production**:
```bash
cd Tools/CoreMLTrainer
./train_full.sh
```

---

## ✅ Проверка

После обучения запустите тесты:

```bash
swift test
```

Вы должны увидеть:
```
✔ Test Suite 'All tests' passed
```

### 🧪 Synthetic evaluation (автотест “как юзер печатает в неправильной раскладке”)

Запускает большой синтетический набор кейсов для всех 9 комбинаций EN/RU/HE (включая “уже правильно”, чтобы ловить ложные срабатывания):

```bash
./train_master.sh 7
```

Переменные окружения:
- `OMFK_SYNTH_EVAL_CASES_PER_LANG` (по умолчанию `300`)
- `OMFK_SYNTH_EVAL_SEED` (по умолчанию `42`)
- `OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC` (опционально, процент, чтобы фейлить тест при деградации)

---

## 📁 Структура файлов

```
OMFK/
├── train_all_models.sh          ← Мастер-скрипт (запускайте его!)
├── Tools/
│   ├── NgramTrainer/
│   │   ├── README.md             ← Документация N-gram
│   │   ├── train_ngrams.py       ← Скрипт обучения
│   │   └── corpora/              ← Корпуса текстов
│   └── CoreMLTrainer/
│       ├── README.md             ← Документация CoreML
│       ├── train_quick.sh        ← Быстрое обучение
│       ├── train_full.sh         ← Полное обучение
│       ├── generate_data.py      ← Генерация данных
│       ├── train.py              ← Обучение PyTorch
│       └── export.py             ← Экспорт в CoreML
└── OMFK/Sources/Resources/
    ├── LanguageModels/           ← N-gram модели (JSON)
    │   ├── ru_trigrams.json
    │   ├── en_trigrams.json
    │   └── he_trigrams.json
    └── LayoutClassifier.mlmodel  ← CoreML модель
```

---

## 🔧 Требования

- **Python 3.8+** (для обучения)
- **Swift 5.10+** (для сборки)
- **macOS 14+** (для запуска)

### Python зависимости (CoreML):
```bash
cd Tools/CoreMLTrainer
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## 💡 Для production

### N-gram модели:
1. Скачайте большие корпуса (Wikipedia, OpenSubtitles)
2. Обучите модели на них
3. Замените файлы в `OMFK/Sources/Resources/LanguageModels/`

### CoreML модель:
1. Реализуйте `download_corpus.py` для Wikipedia
2. Увеличьте `--count` до 100K+
3. Увеличьте `--epochs` до 20+
4. Запустите `./train_full.sh`

---

## 🐛 Troubleshooting

**"Model not found"**
→ Убедитесь, что модели скопированы в `OMFK/Sources/Resources/`

**"Module 'torch' not found"**
→ Активируйте venv: `source Tools/CoreMLTrainer/venv/bin/activate`

**Низкая точность**
→ Используйте больше данных и эпох обучения

**Тесты падают**
→ Проверьте, что все модели на месте: `ls -l OMFK/Sources/Resources/`
