# OMFK Force Switch / Manual Correction Logic

## Текущая реализация (v1.0)

### Триггер: Option (Alt) Key Tap

**Хоткей**: Left Option (keyCode 58) — нажать и отпустить без других клавиш.

**Детекция**: Через `flagsChanged` event в CGEventTap:
- При нажатии Option: `optionKeyWasPressed = true`
- При отпускании Option (если не было других клавиш): триггерим `handleHotkeyPress()`
- Если нажата другая клавиша пока Option зажат: сбрасываем флаг (это не tap)

### Что переключается

**Только последнее слово** (или выделенный текст):

1. **Если есть cycling state** (недавняя автокоррекция или предыдущее нажатие хоткея):
   - Циклически переключаем между альтернативами
   - Таймаут cycling state: 10 секунд

2. **Если нет cycling state**:
   - Пытаемся получить текст в таком порядке:
     1. Выделенный текст (Cmd+C)
     2. `lastCorrectedText` (последний автоисправленный текст)
     3. Содержимое буфера (если не очищен)
     4. Выделяем слово назад (Option+Shift+Left → Cmd+C)

### Как работает cycling

**Генерация альтернатив** (`correctLastWord`):
```
Оригинал: "wloM"
Альтернативы:
  [0] "wloM"     — оригинал
  [1] "цдщь"     — EN→RU (если wloM были бы русские клавиши)
  [2] "שלום"     — EN→HE (если wloM были бы ивритские клавиши)
  [3] ...        — другие конверсии если уникальны
```

**Порядок конверсий**:
1. EN → RU
2. EN → HE
3. RU → EN
4. RU → HE
5. HE → EN
6. HE → RU

**Cycling**:
- `currentIndex` начинается с 0
- Каждый вызов `cycleCorrection()` вызывает `next()` который инкрементирует индекс
- При достижении конца — возврат к началу (циклично)

### Проблемы текущей реализации

1. ~~**Не переключает всю последовательность**~~ — ✅ Решено: Shift+Option для phrase
2. ~~**Нет отмены автокоррекции**~~ — ✅ Решено: undo-first семантика
3. ~~**Порядок альтернатив нелогичен**~~ — ✅ Решено: sorted by score
4. **Нет визуальной обратной связи** — пользователь не видит какие варианты доступны
5. ~~**Буфер очищается после автокоррекции**~~ — ✅ Решено: phraseBuffer сохраняется
6. ~~**Таймаут 10 сек слишком короткий**~~ — ✅ Решено: 60 секунд
7. ~~**Clipboard как primary path**~~ — ✅ Решено: buffer-first + AX API

### Как получаем текст для коррекции

```swift
getSelectedOrLastWord():
  1. lastCorrectedText (если есть) — свой буфер, самый надёжный
  2. buffer (если не пустой) — свой буфер набора
  3. Accessibility API (kAXSelectedTextAttribute) — без clipboard
  4. Cmd+C → clipboard (fallback для Electron/web)
  5. Option+Shift+Left + Cmd+C (выделяем слово назад)
```

**Преимущества нового подхода**:
- Свой буфер имеет приоритет — не зависим от внешних API
- Accessibility API работает без порчи clipboard
- Clipboard только как fallback для приложений где AX не работает

### Как заменяем текст

```swift
replaceText(with:originalLength:):
  1. Backspace × originalLength (удаляем символы)
  2. Печатаем новый текст через CGEvent с Unicode
```

**Проблемы**:
- Backspace может не работать если курсор не в конце
- Нет проверки что удалили правильный текст
- Медленно для длинного текста

### Автокоррекция vs Ручная коррекция

| Аспект | Автокоррекция | Ручная (хоткей) |
|--------|---------------|-----------------|
| Триггер | Пробел/Enter после слова | Option tap |
| Что корректирует | Содержимое буфера | Выделение или последнее слово |
| Cycling | Да (10 сек) | Да (10 сек) |
| Trailing space | Добавляет | Не добавляет |
| Первый вариант | Автоопределённый | Первая конверсия |

### Состояние cycling

```swift
struct CyclingState {
    let originalText: String           // Исходный текст
    let alternatives: [Alternative]    // Все варианты
    var currentIndex: Int              // Текущий индекс
    let wasAutomatic: Bool             // Автокоррекция или ручная
    let autoHypothesis: LanguageHypothesis?
    let timestamp: Date                // Для таймаута
    let hadTrailingSpace: Bool         // Был ли пробел в конце
}
```

### Файлы

- `EventMonitor.swift` — детекция хоткея, получение текста, замена
- `CorrectionEngine.swift` — логика cycling, генерация альтернатив
- `LayoutMapper.swift` — конверсия между раскладками

---

## Вопросы для ресерча

1. **Punto Switcher**: Как работает Pause/Break? Переключает всё или последнее слово?
2. **Punto Switcher**: Есть ли cycling или только toggle между двумя раскладками?
3. **Caramba Switcher**: Какой UX у ручного переключения?
4. **Как определяют границы "последнего слова"?**
5. **Используют ли Accessibility API вместо clipboard hacks?**
6. **Есть ли визуальный preview вариантов?**
7. **Как обрабатывают undo (Cmd+Z)?**






[![Комбинация Shift + Break уже используется? — Хабр Q\&A](https://tse2.mm.bing.net/th/id/OIP.sC5Fan5Jh4UdkAsg7UFO4gHaKq?cb=ucfimg2\&pid=Api\&ucfimg=1)](https://qna.habr.com/q/1354702?utm_source=chatgpt.com)

## Что по факту делают “Pause/Break / Double Shift” у популярных свитчеров

### 1) Punto Switcher: “отмена/конвертация” через Break(Pause)

По описаниям горячих клавиш в пользовательских гайдах/скриншотах настроек, Break (Pause/Break) в Punto обычно привязан к действию **“Отменить конвертацию раскладки”** — то есть **вернуть слово в состояние “как было набрано изначально”**, если автоконвертация сработала неправильно. Также часто упоминаются:

* **Shift+Break** — **смена раскладки выделенного текста**
* **Alt+Break** — **смена регистра выделенного текста**
* **Alt+Scroll Lock** — **транслитерация выделенного текста** ([it.wikireading.ru][1])

Важно: публичная страница Яндекса про Punto подтверждает лишь, что **горячие клавиши настраиваемые**, но без детального списка по умолчанию. ([Yandex][2])

**Вывод для твоего дизайна:** у Punto “Break” семантически ближе к **undo последней конвертации**, а не к “циклу по множеству вариантов”.

---

### 2) Caramba Switcher: Double Shift / Pause Break = ручная правка (и это явно “undo”-семантика)

Caramba прямо пишет:

* **DoubleShift** или **один Pause Break** — “отмена конвертации” (ручная правка) ([caramba-switcher.com][3])
* В macOS-версии: **Double Shift** — исправление **только что набранного слова**, и **то же для выделенного текста**; **Single Shift** может переключать текущую раскладку одним нажатием. ([App Store][4])
* Ограничение: **только RU/EN** и стандартные раскладки (на их сайте). ([caramba-switcher.com][3])

**UX-узор Caramba:**

* “Double Shift” = **быстро откатить/перекинуть последнее слово/выделение**
* “Single Shift” = **переключить текущую раскладку** (без конвертации текста)

---

### 3) Mahou (Windows): классический “Punto-like”, но с line/phrase и режимом cycle

Mahou в README фиксирует схему хоткеев:

* **Pause** — convert last input
* **Shift+Pause** — convert last inputted line
* **Scroll** — convert selected text
* Есть **Cycle Mode** (переключение по кругу), плюс дополнительные фичи вроде “Convert Multiple last words” и “TEXT auto-backup feature for convert selection”. ([GitHub][5])

**Вывод:** Mahou — один из немногих, кто явно поддерживает **cycle-mode** и отдельный хоткей на **последнюю строку/фразу**.

---

### 4) Linux-аналоги (xswitcher / easy-switcher / xneur): “backspace last word → switch layout → retype”

Это повторяется почти везде, потому что работает “в любом поле ввода”:

* xswitcher (описание поведения): **Pause/Break → backspace последнее слово → переключить раскладку → напечатать заново**. ([ProHoster][6])
* easy-switcher: **Break — последнее слово**, **Shift+Break — последняя фраза**. ([linux.org.ru][7])
* xneur: в manual-mode “convert last typed word or selected text using hotkeys”. ([freshports.org][8])

**Вывод:** твой текущий “Option+Shift+Left + Cmd+C” — частный случай того же класса хака, но многие тулзы вообще не трогают selection/clipboard, а держатся на “delete+retype”.

---

## Ответы на твои вопросы (по пунктам)

### 1) Punto Switcher: как работает Pause/Break — всё или последнее слово?

По публичным описаниям: Break (Pause/Break) в первую очередь используется как **“отменить конвертацию” последнего сконвертированного фрагмента** (обычно — последнее слово), а для **выделенного** используется Shift+Break. ([it.wikireading.ru][1])
Про “всё предложение” отдельного стандартного хоткея в найденных описаниях нет; у аналогов это обычно отдельная комбинация (см. Mahou/easy-switcher). ([GitHub][5])

### 2) Punto Switcher: cycling или только toggle?

Я не нашёл подтверждений “циклинга вариантов” в духе твоего списка альтернатив. Найденные описания говорят про **одно действие: отменить/вернуть** (и отдельные действия для selection/case/translit). ([it.wikireading.ru][1])
Если и есть “toggle”, то фактически это **двухсостояние** (сконвертировано ↔ как было набрано), а не N-вариантный цикл.

### 3) Caramba Switcher: какой UX у ручного переключения?

* **Double Shift** (и/или Pause Break) — **ручная правка последнего слова**; также работает для **выделенного текста**. ([App Store][4])
* **Single Shift** может быть “layout toggle” (без конвертации текста). ([App Store][4])

### 4) Как определяют границы “последнего слова”?

Типовой промышленный подход: “последнее слово” = токен **после последнего разделителя** (space/enter/tab/punct), и при ручной конвертации делают: **Backspace N символов → смена раскладки → retype**. ([ProHoster][6])
Это объясняет, почему многие обходятся без selection API и без clipboard.

### 5) Используют ли Accessibility API вместо clipboard hacks?

На macOS это возможно: можно читать/писать выделенный текст через Accessibility атрибуты:

* `kAXSelectedTextAttribute` (выделенный текст) ([Apple Developer][9])
* `kAXSelectedTextRangeAttribute` (диапазон выделения) ([Apple Developer][10])
* доступ через `AXUIElementCopyAttributeValue` / `AXUIElementSetAttributeValue`. ([Apple Developer][11])

Но есть реальность: не все приложения корректно отдают/принимают выделение через AX (особенно Electron/web areas), поэтому многие тулзы всё равно держат fallback на delete+retype или clipboard. ([GitHub][12])

### 6) Есть ли визуальный preview вариантов?

У части тулзов есть хотя бы минимальная индикация: например, Mahou упоминает “small tip which displays current layout” и другие визуальные подсказки. ([GitHub][5])
У Punto/Caramba в найденных публичных описаниях акцент больше на хоткеях и автологике, чем на “preview списка вариантов”.

### 7) Как обрабатывают undo (Cmd+Z)?

Частый паттерн (xswitcher/easy-switcher класс): они симулируют **удаление + ввод**, поэтому “undo” у приложений может работать непредсказуемо (иногда откатывает посимвольно, иногда группирует, иногда ломается). Тулзы, которые заботятся об этом, добавляют “backup” (Mahou прямо упоминает **TEXT auto-backup for convert selection**). ([GitHub][5])

---

## Что улучшить в OMFK, если целишься в “Punto/Caramba-grade” UX

### A) Сделай “undo-first” как основную семантику хоткея

Твоя боль №2 (“нет отмены автокоррекции первым действием”) решается правилом:

1. Если последний action был **автокоррекция** и курсор/контекст ещё совместимы → **первое нажатие** возвращает `originalText` (undo).
2. Второе нажатие → возвращает “самый вероятный” (твой autoHypothesis).
3. Только дальше — опциональный цикл по остальным (если вообще нужен).

Это совпадает с тем, как пользователи “мыслят” Break/DoubleShift в Punto/Caramba. ([it.wikireading.ru][1])

### B) Раздели хоткеи: last-word vs last-phrase vs selection (как у Mahou/easy-switcher)

У многих “каноническая” сетка:

* last word (Pause/Break)
* last phrase/line (Shift+Pause/Break)
* selection (Scroll / отдельный хоткей) ([GitHub][5])

Для OMFK это даёт предсказуемость и убирает желание “угадать, что именно ты сейчас конвертишь”.

### C) Убери зависимость от clipboard как primary path (оставь как fallback)

На macOS лучший первичный путь для selection:

* пытаться читать/писать выделение через AX (`kAXSelectedTextAttribute`, `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`). ([Apple Developer][9])
  Clipboard оставь как fallback для приложений, где AX не работает (Electron/web views). ([GitHub][12])

### D) Для “последнего слова/фразы” не извлекай текст из приложения — держи свой буфер

Практика Linux/Win тулзов показывает, почему это устойчиво: они просто знают, что было набрано, и делают delete+retype. ([ProHoster][6])
Для тебя это ещё важнее, потому что RU/HE и EN/HE сложнее и ты всё равно трекаешь поток символов.

Минимальный критерий инвалидировать буфер: смена приложения, mouse click, навигационные клавиши, явный selection-change, backspace/delete, IME-композиция.

### E) Сделай порядок альтернатив детерминированным и “объяснимым”

Вместо фиксированного EN→RU→HE… лучше:

1. `original` (undo target)
2. `bestGuess` (по твоей language hypothesis)
3. Остальные — сортировать по score (или хотя бы по “наиболее вероятное направление из текущей раскладки”), а не по жёсткому списку направлений.

### F) Таймаут cycling state

10 секунд почти всегда мало. У Mahou цикл/доп.режимы существуют отдельно и UX рассчитан на “успел подумать”. ([GitHub][5])
Практичнее: TTL 30–60с **или** сброс по явному “контекст сменился” (caret move/app switch).

Если хочешь — могу предложить конкретную схему state machine для `CyclingState` (какие поля добавить, какие события сбрасывают state) под твою текущую архитектуру `EventMonitor / CorrectionEngine / LayoutMapper`, без переписывания всего на AX.

[1]: https://it.wikireading.ru/42148?utm_source=chatgpt.com "7.3. Программы автоматического переключения раскладки ..."
[2]: https://yandex.ru/soft/punto/win/?utm_source=chatgpt.com "Punto Switcher — программа для переключения раскладки"
[3]: https://caramba-switcher.com/ "Caramba Switcher — переключатель раскладки клавиатуры для Windows и Mac"
[4]: https://apps.apple.com/us/app/caramba-switcher-%D0%BA%D0%B0%D1%80%D0%B0%D0%BC%D0%B1%D0%B0/id1565826179 "‎Caramba Switcher • Карамба App - App Store"
[5]: https://github.com/iamkarlson/Mahou "GitHub - iamkarlson/Mahou: Mahou(魔法) - The magic layout switcher."
[6]: https://prohoster.info/en/blog/administrirovanie/novyj-analog-punto-switcher-dlya-linux-xswitcher "New analogue of Punto Switcher for Linux: xswitcher | ProHoster"
[7]: https://www.linux.org.ru/forum/desktop/17194487?utm_source=chatgpt.com "Easy Switcher - переключатель раскладки клавиатуры"
[8]: https://www.freshports.org/deskutils/xneur/?utm_source=chatgpt.com "deskutils/xneur: Auto keyboard switcher"
[9]: https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute?changes=_7&utm_source=chatgpt.com "kAXSelectedTextAttribute | Apple Developer Documentation"
[10]: https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute?changes=l_2&language=objc&utm_source=chatgpt.com "kAXSelectedTextRangeAttribute"
[11]: https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue?utm_source=chatgpt.com "AXUIElementCopyAttributeValue(_:_:_:)"
[12]: https://github.com/electron/electron/issues/36337?utm_source=chatgpt.com "[Bug]: Text selection via accessibility on macOS broken ..."
