### Таблица соответствий (base layer, без Shift/Option)

Ниже — **CSV**, где каждая строка = *физическая клавиша по позиции на QWERTY* (как в вашем примере: `qwertyuiop[]`, `asdfghjkl;'\`, `zxcvbnm,./`), а столбцы — символ в каждой раскладке.

```csv
Key,US QWERTY,ABC (macOS),RU PC (ЙЦУКЕН),RU Mac (Apple 'Russian'),RU Phonetic (YaShert),HE Standard (SI-1452),HE PC,HE QWERTY
Q,q,q,й,й,я,/,/,ק
W,w,w,ц,ц,ш,׳,',ש
E,e,e,у,у,е,ק,ק,ע
R,r,r,к,к,р,ר,ר,ר
T,t,t,е,е,т,א,א,ת
Y,y,y,н,н,ы,ט,ט,ט
U,u,u,г,г,у,ו,ו,ו
I,i,i,ш,ш,и,ן,ן,י
O,o,o,щ,щ,о,ם,ם,ו
P,p,p,з,з,п,פ,פ,פ
[,[,[,х,х,ю,],],'
],],],ъ,ъ,щ,[,[,ײַ
A,a,a,ф,ф,а,ש,ש,א
S,s,s,ы,ы,с,ד,ד,ס
D,d,d,в,в,д,ג,ג,ד
F,f,f,а,а,ф,כ,כ,פ
G,g,g,п,п,г,ע,ע,ג
H,h,h,р,р,ч,י,י,ה
J,j,j,о,о,й,ח,ח,ח
K,k,k,л,л,к,ל,ל,כ
L,l,l,д,д,л,ך,ך,ל
;,;,;,ж,ж,ь,ף,ף,;
',',',э,э,ж,",",,",",׳
\,\,\,\,\,э,ֿ,\,ֿ
Z,z,z,я,я,з,ז,ז,ז
X,x,x,ч,ч,х,ס,ס,ח
C,c,c,с,с,ц,ב,ב,צ
V,v,v,м,м,в,ה,ה,ו
B,b,b,и,и,б,נ,נ,ב
N,n,n,т,т,н,מ,מ,נ
M,m,m,ь,ь,м,צ,צ,מ
",",",",б,б,",",ת,ת,,
.,.,.,ю,ю,.,ץ,ץ,.
/,/,/,. ,/,/,.,.,/
```

**Важно про HE QWERTY:** в вашей строке для `]` получилось **двухсимвольное** `ײַ` (это нормально: раскладки могут выдавать *мультирунные* последовательности, диакритики, dead keys).

---

## Отмеченные различия/неоднозначности (где чаще всего “ломается” корректор)

### 1) RU Mac (Apple “Russian”) vs RU PC (“Russian - PC”)

На macOS есть **две разные русские раскладки**: “Russian” и “Russian - PC”. Пользователи регулярно путают их; Apple прямо советует выбирать “Russian PC”, если нужна “нормальная (PC)” пунктуация. ([Apple Support Communities][1])
Классическая разница: **пунктуация** (например, `.`/`,` могут быть вынесены на цифры с Shift), что отражено и в обсуждениях/репортах (например, про `Shift-7` для точки и `Shift-6` для запятой). ([GitHub][2])

В таблице я показал **минимально важную для base-layer** разницу, которая часто встречается в Apple “Russian”: на клавише `/` в base может быть `/`, а не `.` (в PC-варианте чаще ожидают `.`). Но для надёжности это место лучше подтверждать **программно** (см. ниже).

### 2) Hebrew Standard (SI-1452) vs Hebrew PC

У вас это уже видно:

* `W`: **geresh** `׳` vs ASCII `'`
* `\`: **rafe** `ֿ` vs ASCII `\`
* в SI-1452/macOS часто встречается “перевёрнутые” `[`/`]` как `][` (у вас именно так).

Для “PC” отличия можно сверять по виндовым раскладкам/схемам. ([Muhlenberg College][3])
Сам стандарт SI-1452 — израильский (Институт стандартов Израиля). ([SII][4])

### 3) RU Phonetic/YaShert — есть варианты

“Фонетическая” русская раскладка — не одна. В таблице дан распространённый вариант “Russian (US, phonetic)” (YaShert/Popov) из XKB-описания (полезен как эталон для проверки логики). ([Gist][5])
macOS “Russian – QWERTY / Russian-Phonetic” может отличаться в нескольких клавишах (особенно вокруг `X/C`, `;/'`, и поведения пунктуации).

### 4) ISO vs ANSI (физическая клавиатура)

На ISO есть дополнительная клавиша (обычно между Left Shift и Z: `< > |`). В вашей схеме её нет — вы просили именно “по позиции на QWERTY” как в примере, поэтому я дал **строго те 34 клавиши**, что соответствуют вашим строкам.

---

## Источники (куда смотреть “официально” и около-официально)

1. Apple: низкоуровневое преобразование keycode → Unicode через **UCKeyTranslate/UCKeyboardLayout** и привязка к input source.
2. Apple: различие “Russian” vs “Russian PC” в системных input sources (практическое подтверждение пользователями).
3. Apple: список идентификаторов встроенных раскладок (в т.ч. `com.apple.keylayout.Russian`, `...RussianWin`, `...Russian-Phonetic`).
4. Hebrew SI-1452: страница стандарта Института стандартов Израиля.
5. Hebrew PC: схемы раскладки Windows (удобно для сравнения символов `'`/`\` vs `׳`/`ֿ`).
6. Russian phonetic (YaShert): эталонное XKB-описание соответствий.
7. Для “RU PC (ЙЦУКЕН)” как референс Windows-совместимого маппинга удобно сверять, например, по kbdlayout-справочникам.

---

## Как получить эти данные программно на macOS (рекомендуемый путь для OMFK)

### Вариант A (надёжный): TIS + UCKeyTranslate

1. Получить нужный input source (раскладку) через **Text Input Source Services**:

   * `TISCreateInputSourceList` (список)
   * или `TISCopyCurrentKeyboardLayoutInputSource` (текущая)
2. Взять `kTISPropertyUnicodeKeyLayoutData` → `CFData` → `UCKeyboardLayout*`.
3. Для каждого **виртуального keycode** и набора модификаторов вызвать `UCKeyTranslate(...)`:

   * отдельно для base/Shift/Option/Shift+Option (и т.п.)
   * учесть `deadKeyState` (dead keys) и `keyboardType` (`LMGetKbdType()`).

Документационный якорь по структурам/вызовам:

Почему это лучше:

* не нужно вручную поддерживать “варианты” раскладок;
* корректно для ANSI/ISO/JIS;
* автоматически учитывает обновления Apple.

### Вариант B (оффлайн/инспекция): парсить `.keylayout` файлы

* Системные раскладки обычно лежат внутри `/System/Library/Keyboard Layouts/` (внутри `.bundle`).
* Пользовательские: `/Library/Keyboard Layouts/` и `~/Library/Keyboard Layouts/`.
* Формат `.keylayout` — XML с `keyMapSet`/`modifierMap`/`actions` (нужно аккуратно обрабатывать modifier maps и dead keys).

---

## Практическая пометка для корректора OMFK

Для “исправления раскладки” вам почти всегда достаточно:

* **буквенных** клавиш (A–Z) + базовой пунктуации,
* причём корректнее строить маппинг как:

  * `layoutId + hardwareKeycode + modifiers -> producedString`
  * и уже из этого делать обратные таблицы “не та раскладка → правильная”.

Если нужно, могу выдать готовую структуру данных (JSON/TS) в виде:

* `layout -> { keyPosition -> output }` (как выше),
* и/или `keyPosition -> { layout -> output }`,
* плюс список keycodes для ANSI/ISO (чтобы это напрямую легло в вашу реализацию UCKeyTranslate).

```json
{
  "schema_version": "1.0",
  "generated_at": "2025-12-21",
  "modifiers": {
    "n": "none",
    "s": "shift",
    "a": "alt (Option ⌥ on macOS)",
    "sa": "shift+alt (Shift+Option ⇧⌥ on macOS)",
    "implicit_null": [
      "ctrl",
      "ctrl_shift",
      "ctrl_alt",
      "ctrl_shift_alt"
    ]
  },
  "layouts": {
    "en_us": {
      "name": "English (US) - QWERTY",
      "platform": "macOS",
      "source": "Apple Keyboard Viewer / common US layout"
    },
    "ru_pc": {
      "name": "Russian - PC (ЙЦУКЕН)",
      "platform": "Windows/Linux (reference) / macOS",
      "note": "Base row from user; shift for \\/ verified against Windows KBDRU."
    },
    "ru_phonetic_yasherty": {
      "name": "Russian - Phonetic (ЯШЕРТЫ) [approx]",
      "platform": "various",
      "note": "There are multiple phonetic variants; verify before relying in production."
    },
    "he_standard": {
      "name": "Hebrew - Standard (SI-1452) [as observed on macOS]",
      "platform": "macOS",
      "note": "Based on user's manual mapping; modifiers for punctuation may vary."
    },
    "he_pc": {
      "name": "Hebrew - PC (as observed on macOS)",
      "platform": "macOS",
      "note": "Based on user's manual mapping; differs from he_standard on some keys."
    },
    "he_qwerty": {
      "name": "Hebrew - QWERTY phonetic (as observed on macOS)",
      "platform": "macOS",
      "note": "Based on user's manual mapping."
    }
  },
  "layout_aliases": {
    "en_abc": "en_us",
    "ru_mac": "ru_pc"
  },
  "keys": [
    {
      "code": "KeyQ",
      "qwerty_label": "Q"
    },
    {
      "code": "KeyW",
      "qwerty_label": "W"
    },
    {
      "code": "KeyE",
      "qwerty_label": "E"
    },
    {
      "code": "KeyR",
      "qwerty_label": "R"
    },
    {
      "code": "KeyT",
      "qwerty_label": "T"
    },
    {
      "code": "KeyY",
      "qwerty_label": "Y"
    },
    {
      "code": "KeyU",
      "qwerty_label": "U"
    },
    {
      "code": "KeyI",
      "qwerty_label": "I"
    },
    {
      "code": "KeyO",
      "qwerty_label": "O"
    },
    {
      "code": "KeyP",
      "qwerty_label": "P"
    },
    {
      "code": "BracketLeft",
      "qwerty_label": "["
    },
    {
      "code": "BracketRight",
      "qwerty_label": "]"
    },
    {
      "code": "KeyA",
      "qwerty_label": "A"
    },
    {
      "code": "KeyS",
      "qwerty_label": "S"
    },
    {
      "code": "KeyD",
      "qwerty_label": "D"
    },
    {
      "code": "KeyF",
      "qwerty_label": "F"
    },
    {
      "code": "KeyG",
      "qwerty_label": "G"
    },
    {
      "code": "KeyH",
      "qwerty_label": "H"
    },
    {
      "code": "KeyJ",
      "qwerty_label": "J"
    },
    {
      "code": "KeyK",
      "qwerty_label": "K"
    },
    {
      "code": "KeyL",
      "qwerty_label": "L"
    },
    {
      "code": "Semicolon",
      "qwerty_label": ";"
    },
    {
      "code": "Quote",
      "qwerty_label": "'"
    },
    {
      "code": "Backslash",
      "qwerty_label": "\\"
    },
    {
      "code": "KeyZ",
      "qwerty_label": "Z"
    },
    {
      "code": "KeyX",
      "qwerty_label": "X"
    },
    {
      "code": "KeyC",
      "qwerty_label": "C"
    },
    {
      "code": "KeyV",
      "qwerty_label": "V"
    },
    {
      "code": "KeyB",
      "qwerty_label": "B"
    },
    {
      "code": "KeyN",
      "qwerty_label": "N"
    },
    {
      "code": "KeyM",
      "qwerty_label": "M"
    },
    {
      "code": "Comma",
      "qwerty_label": ","
    },
    {
      "code": "Period",
      "qwerty_label": "."
    },
    {
      "code": "Slash",
      "qwerty_label": "/"
    }
  ],
  "dead_key_combos": [
    {
      "layout": "en_us",
      "key": "KeyE",
      "modifier": "alt",
      "dead_key": "acute"
    },
    {
      "layout": "en_us",
      "key": "KeyE",
      "modifier": "shift_alt",
      "dead_key": "acute"
    },
    {
      "layout": "en_us",
      "key": "KeyU",
      "modifier": "alt",
      "dead_key": "diaeresis"
    },
    {
      "layout": "en_us",
      "key": "KeyU",
      "modifier": "shift_alt",
      "dead_key": "diaeresis"
    },
    {
      "layout": "en_us",
      "key": "KeyI",
      "modifier": "alt",
      "dead_key": "circumflex"
    },
    {
      "layout": "en_us",
      "key": "KeyI",
      "modifier": "shift_alt",
      "dead_key": "circumflex"
    },
    {
      "layout": "en_us",
      "key": "KeyN",
      "modifier": "alt",
      "dead_key": "tilde"
    },
    {
      "layout": "en_us",
      "key": "KeyN",
      "modifier": "shift_alt",
      "dead_key": "tilde"
    },
    {
      "layout": "en_us",
      "key": "KeyH",
      "modifier": "alt",
      "dead_key": "dot_above"
    },
    {
      "layout": "en_us",
      "key": "KeyH",
      "modifier": "shift_alt",
      "dead_key": "dot_above"
    },
    {
      "layout": "en_us",
      "key": "KeyK",
      "modifier": "alt",
      "dead_key": "ring_above"
    }
  ],
  "ambiguities": [
    {
      "layout": "he_qwerty",
      "key": "BracketRight",
      "modifier": "none",
      "reason": "multi_char_output",
      "out": "ײַ"
    },
    {
      "layout": "he_qwerty",
      "key": "BracketRight",
      "modifier": "shift",
      "reason": "multi_char_output",
      "out": "ײַ"
    }
  ],
  "map": {
    "KeyQ": {
      "en_us": {
        "n": "q",
        "s": "Q",
        "a": "œ",
        "sa": "Œ"
      },
      "ru_pc": {
        "n": "й",
        "s": "Й",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "я",
        "s": "Я",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "/",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "/",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ק",
        "s": "ק",
        "a": null,
        "sa": null
      }
    },
    "KeyW": {
      "en_us": {
        "n": "w",
        "s": "W",
        "a": "∑",
        "sa": null
      },
      "ru_pc": {
        "n": "ц",
        "s": "Ц",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ш",
        "s": "Ш",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "׳",
        "s": "׳",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "'",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ש",
        "s": "ש",
        "a": null,
        "sa": null
      }
    },
    "KeyE": {
      "en_us": {
        "n": "e",
        "s": "E",
        "a": "´",
        "sa": null
      },
      "ru_pc": {
        "n": "у",
        "s": "У",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "е",
        "s": "Е",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ק",
        "s": "ק",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ק",
        "s": "ק",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ע",
        "s": "ע",
        "a": null,
        "sa": null
      }
    },
    "KeyR": {
      "en_us": {
        "n": "r",
        "s": "R",
        "a": "®",
        "sa": null
      },
      "ru_pc": {
        "n": "к",
        "s": "К",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "р",
        "s": "Р",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ר",
        "s": "ר",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ר",
        "s": "ר",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ר",
        "s": "ר",
        "a": null,
        "sa": null
      }
    },
    "KeyT": {
      "en_us": {
        "n": "t",
        "s": "T",
        "a": "†",
        "sa": null
      },
      "ru_pc": {
        "n": "е",
        "s": "Е",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "т",
        "s": "Т",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "א",
        "s": "א",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "א",
        "s": "א",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ת",
        "s": "ת",
        "a": null,
        "sa": null
      }
    },
    "KeyY": {
      "en_us": {
        "n": "y",
        "s": "Y",
        "a": "¥",
        "sa": null
      },
      "ru_pc": {
        "n": "н",
        "s": "Н",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ы",
        "s": "Ы",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ט",
        "s": "ט",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ט",
        "s": "ט",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ט",
        "s": "ט",
        "a": null,
        "sa": null
      }
    },
    "KeyU": {
      "en_us": {
        "n": "u",
        "s": "U",
        "a": "¨",
        "sa": null
      },
      "ru_pc": {
        "n": "г",
        "s": "Г",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "у",
        "s": "У",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ו",
        "s": "ו",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ו",
        "s": "ו",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ו",
        "s": "ו",
        "a": null,
        "sa": null
      }
    },
    "KeyI": {
      "en_us": {
        "n": "i",
        "s": "I",
        "a": "ˆ",
        "sa": null
      },
      "ru_pc": {
        "n": "ш",
        "s": "Ш",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "и",
        "s": "И",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ן",
        "s": "ן",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ן",
        "s": "ן",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "י",
        "s": "י",
        "a": null,
        "sa": null
      }
    },
    "KeyO": {
      "en_us": {
        "n": "o",
        "s": "O",
        "a": "ø",
        "sa": "Ø"
      },
      "ru_pc": {
        "n": "щ",
        "s": "Щ",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "о",
        "s": "О",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ם",
        "s": "ם",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ם",
        "s": "ם",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ו",
        "s": "ו",
        "a": null,
        "sa": null
      }
    },
    "KeyP": {
      "en_us": {
        "n": "p",
        "s": "P",
        "a": "π",
        "sa": null
      },
      "ru_pc": {
        "n": "з",
        "s": "З",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "п",
        "s": "П",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "פ",
        "s": "פ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "פ",
        "s": "פ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "פ",
        "s": "פ",
        "a": null,
        "sa": null
      }
    },
    "BracketLeft": {
      "en_us": {
        "n": "[",
        "s": "{",
        "a": "“",
        "sa": "”"
      },
      "ru_pc": {
        "n": "х",
        "s": "Х",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ю",
        "s": "Ю",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "]",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "]",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "'",
        "s": "\"",
        "a": null,
        "sa": null
      }
    },
    "BracketRight": {
      "en_us": {
        "n": "]",
        "s": "}",
        "a": "‘",
        "sa": "’"
      },
      "ru_pc": {
        "n": "ъ",
        "s": "Ъ",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "щ",
        "s": "Щ",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "[",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "[",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ײַ",
        "s": "ײַ",
        "a": null,
        "sa": null
      }
    },
    "KeyA": {
      "en_us": {
        "n": "a",
        "s": "A",
        "a": "å",
        "sa": "Å"
      },
      "ru_pc": {
        "n": "ф",
        "s": "Ф",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "а",
        "s": "А",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ש",
        "s": "ש",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ש",
        "s": "ש",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "א",
        "s": "א",
        "a": null,
        "sa": null
      }
    },
    "KeyS": {
      "en_us": {
        "n": "s",
        "s": "S",
        "a": "ß",
        "sa": null
      },
      "ru_pc": {
        "n": "ы",
        "s": "Ы",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "с",
        "s": "С",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ד",
        "s": "ד",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ד",
        "s": "ד",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ס",
        "s": "ס",
        "a": null,
        "sa": null
      }
    },
    "KeyD": {
      "en_us": {
        "n": "d",
        "s": "D",
        "a": "∂",
        "sa": null
      },
      "ru_pc": {
        "n": "в",
        "s": "В",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "д",
        "s": "Д",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ג",
        "s": "ג",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ג",
        "s": "ג",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ד",
        "s": "ד",
        "a": null,
        "sa": null
      }
    },
    "KeyF": {
      "en_us": {
        "n": "f",
        "s": "F",
        "a": "ƒ",
        "sa": null
      },
      "ru_pc": {
        "n": "а",
        "s": "А",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ф",
        "s": "Ф",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "כ",
        "s": "כ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "כ",
        "s": "כ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "פ",
        "s": "פ",
        "a": null,
        "sa": null
      }
    },
    "KeyG": {
      "en_us": {
        "n": "g",
        "s": "G",
        "a": "©",
        "sa": null
      },
      "ru_pc": {
        "n": "п",
        "s": "П",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "г",
        "s": "Г",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ע",
        "s": "ע",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ע",
        "s": "ע",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ג",
        "s": "ג",
        "a": null,
        "sa": null
      }
    },
    "KeyH": {
      "en_us": {
        "n": "h",
        "s": "H",
        "a": "˙",
        "sa": null
      },
      "ru_pc": {
        "n": "р",
        "s": "Р",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "х",
        "s": "Х",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "י",
        "s": "י",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "י",
        "s": "י",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ה",
        "s": "ה",
        "a": null,
        "sa": null
      }
    },
    "KeyJ": {
      "en_us": {
        "n": "j",
        "s": "J",
        "a": "∆",
        "sa": null
      },
      "ru_pc": {
        "n": "о",
        "s": "О",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "й",
        "s": "Й",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ח",
        "s": "ח",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ח",
        "s": "ח",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ח",
        "s": "ח",
        "a": null,
        "sa": null
      }
    },
    "KeyK": {
      "en_us": {
        "n": "k",
        "s": "K",
        "a": "˚",
        "sa": ""
      },
      "ru_pc": {
        "n": "л",
        "s": "Л",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "к",
        "s": "К",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ל",
        "s": "ל",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ל",
        "s": "ל",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "כ",
        "s": "כ",
        "a": null,
        "sa": null
      }
    },
    "KeyL": {
      "en_us": {
        "n": "l",
        "s": "L",
        "a": "¬",
        "sa": null
      },
      "ru_pc": {
        "n": "д",
        "s": "Д",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "л",
        "s": "Л",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ך",
        "s": "ך",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ך",
        "s": "ך",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ל",
        "s": "ל",
        "a": null,
        "sa": null
      }
    },
    "Semicolon": {
      "en_us": {
        "n": ";",
        "s": ":",
        "a": "…",
        "sa": null
      },
      "ru_pc": {
        "n": "ж",
        "s": "Ж",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ь",
        "s": "Ь",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ף",
        "s": "ף",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ף",
        "s": "ף",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": ";",
        "s": ":",
        "a": null,
        "sa": null
      }
    },
    "Quote": {
      "en_us": {
        "n": "'",
        "s": "\"",
        "a": "æ",
        "sa": "Æ"
      },
      "ru_pc": {
        "n": "э",
        "s": "Э",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ж",
        "s": "Ж",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": ",",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": ",",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "׳",
        "s": "׳",
        "a": null,
        "sa": null
      }
    },
    "Backslash": {
      "en_us": {
        "n": "\\",
        "s": "|",
        "a": "«",
        "sa": "»"
      },
      "ru_pc": {
        "n": "\\",
        "s": "/",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "э",
        "s": "Э",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ֿ",
        "s": "ֿ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "\\",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ֿ",
        "s": "ֿ",
        "a": null,
        "sa": null
      }
    },
    "KeyZ": {
      "en_us": {
        "n": "z",
        "s": "Z",
        "a": "Ω",
        "sa": null
      },
      "ru_pc": {
        "n": "я",
        "s": "Я",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "з",
        "s": "З",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ז",
        "s": "ז",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ז",
        "s": "ז",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ז",
        "s": "ז",
        "a": null,
        "sa": null
      }
    },
    "KeyX": {
      "en_us": {
        "n": "x",
        "s": "X",
        "a": "≈",
        "sa": null
      },
      "ru_pc": {
        "n": "ч",
        "s": "Ч",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ч",
        "s": "Ч",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ס",
        "s": "ס",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ס",
        "s": "ס",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ח",
        "s": "ח",
        "a": null,
        "sa": null
      }
    },
    "KeyC": {
      "en_us": {
        "n": "c",
        "s": "C",
        "a": "ç",
        "sa": "Ç"
      },
      "ru_pc": {
        "n": "с",
        "s": "С",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "ц",
        "s": "Ц",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ב",
        "s": "ב",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ב",
        "s": "ב",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "צ",
        "s": "צ",
        "a": null,
        "sa": null
      }
    },
    "KeyV": {
      "en_us": {
        "n": "v",
        "s": "V",
        "a": "√",
        "sa": null
      },
      "ru_pc": {
        "n": "м",
        "s": "М",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "в",
        "s": "В",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ה",
        "s": "ה",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ה",
        "s": "ה",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ו",
        "s": "ו",
        "a": null,
        "sa": null
      }
    },
    "KeyB": {
      "en_us": {
        "n": "b",
        "s": "B",
        "a": "∫",
        "sa": null
      },
      "ru_pc": {
        "n": "и",
        "s": "И",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "б",
        "s": "Б",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "נ",
        "s": "נ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "נ",
        "s": "נ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "ב",
        "s": "ב",
        "a": null,
        "sa": null
      }
    },
    "KeyN": {
      "en_us": {
        "n": "n",
        "s": "N",
        "a": "˜",
        "sa": null
      },
      "ru_pc": {
        "n": "т",
        "s": "Т",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "н",
        "s": "Н",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "מ",
        "s": "מ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "מ",
        "s": "מ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "נ",
        "s": "נ",
        "a": null,
        "sa": null
      }
    },
    "KeyM": {
      "en_us": {
        "n": "m",
        "s": "M",
        "a": "µ",
        "sa": null
      },
      "ru_pc": {
        "n": "ь",
        "s": "Ь",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "м",
        "s": "М",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "צ",
        "s": "צ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "צ",
        "s": "צ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "מ",
        "s": "מ",
        "a": null,
        "sa": null
      }
    },
    "Comma": {
      "en_us": {
        "n": ",",
        "s": "<",
        "a": "≤",
        "sa": null
      },
      "ru_pc": {
        "n": "б",
        "s": "Б",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": ",",
        "s": "<",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ת",
        "s": "ת",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ת",
        "s": "ת",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": ",",
        "s": "<",
        "a": null,
        "sa": null
      }
    },
    "Period": {
      "en_us": {
        "n": ".",
        "s": ">",
        "a": "≥",
        "sa": null
      },
      "ru_pc": {
        "n": "ю",
        "s": "Ю",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": ".",
        "s": ">",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": "ץ",
        "s": "ץ",
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": "ץ",
        "s": "ץ",
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": ".",
        "s": ">",
        "a": null,
        "sa": null
      }
    },
    "Slash": {
      "en_us": {
        "n": "/",
        "s": "?",
        "a": "÷",
        "sa": "¿"
      },
      "ru_pc": {
        "n": ".",
        "s": ",",
        "a": null,
        "sa": null
      },
      "ru_phonetic_yasherty": {
        "n": "/",
        "s": "?",
        "a": null,
        "sa": null
      },
      "he_standard": {
        "n": ".",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_pc": {
        "n": ".",
        "s": null,
        "a": null,
        "sa": null
      },
      "he_qwerty": {
        "n": "/",
        "s": "?",
        "a": null,
        "sa": null
      }
    }
  }
}
```

Sources for verification/extraction (if you want to auto-generate the full ⇧⌥ layers per installed layout/version): Apple Keyboard Viewer ; programmatic extraction via TIS + UCKeyTranslate ; RU PC shift-states (e.g., `\`→`/`, `.` key→`,` with Shift) from Microsoft KBDRU tables ; Apple logo `` on ⇧⌥K .



[1]: https://discussions.apple.com/thread/251888939?utm_source=chatgpt.com "Russian keyboard layout"
[2]: https://github.com/pqrs-org/Karabiner-archived/issues/832?utm_source=chatgpt.com "Russian keyboard needs extra options · Issue #832"
[3]: https://www.muhlenberg.edu/media/contentassets/pdf/academics/llc/online-resources/hebrew/TypingGuides_printout_HBW_layout_win_aligned.pdf?utm_source=chatgpt.com "Hebrew Keyboard Layouts on Windows"
[4]: https://www.sii.org.il/lobby/standardization/standard-page/?id=e9166c38-c384-4a5b-8e91-bbb4f08003d3&utm_source=chatgpt.com "ת\"י 1452"
[5]: https://gist.github.com/joshm21/1d2a01112c3c3bae7e101b433c814106 "Russian Phonetic (Student, AATSEEL, YaShert, яшерт) Keyboard for Linux · GitHub"
