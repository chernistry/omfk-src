# OMFK Bug Fixing Session - 2024-12-30

## Контекст
Провели E2E тестирование OMFK (keyboard layout auto-switcher). Результат: 60 passed, 101 failed.

## Созданы GitHub Issues
1. **#1 Comma/period inside words** 🔴 HIGH - `k.,k.` → `люблю`, `,tp` → `без`
2. **#2 Single-letter prepositions e→у, r→к** 🔴 HIGH - `e vtyz` → `у меня`
3. **#3 Punctuation word boundaries** 🟡 MEDIUM - `?`, `;`, brackets не триггерят

## Документация проблем
- `/Users/sasha/IdeaProjects/personal_projects/omfk/.sdd/backlog/wrongs.md` - полный список с таблицами

## Улучшения тестов
- Добавлен F10 для остановки теста
- Добавлено убийство лишних OMFK инстансов при старте

## Порядок фиксов
1. Issue #1: Comma/period in words (блокирует люблю, без, буду, об)
2. Issue #2: Prepositions e→у, r→к (блокирует "у меня", "к сожалению")
3. Issue #3: Punctuation boundaries

## Ключевые файлы
- `OMFK/Sources/Core/LayoutMapper.swift` - конверсия символов
- `OMFK/Sources/Core/ConfidenceRouter.swift` - scoring и prepositions
- `OMFK/Sources/Engine/CorrectionEngine.swift` - основная логика
- `OMFK/Sources/Resources/language_data.json` - punctuation sets, mappings
- `scripts/comprehensive_test.py` - E2E тесты

## Команды
```bash
# Запуск тестов
cd /Users/sasha/IdeaProjects/personal_projects/omfk && python3 scripts/comprehensive_test.py

# Билд
swift build

# Конкретная категория тестов
python3 scripts/comprehensive_test.py context_boost_hard
```
