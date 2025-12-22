<div align="center">

# O.M.F.K — Oh My F*cking Keyboard

### Stop typing gibberish. Start typing genius.

*The smartest keyboard layout corrector for macOS — powered by on-device ML*

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10+-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-Proprietary-red)]()

<img src="assets/hero.png" width="600" alt="OMFK in action">

</div>

---

## The Problem

You're deep in flow, typing away... then you look up:

```
Ghbdtn? rfr ltkf&   →   Should be: Привет, как дела?
ру|дщ цщкдв          →   Should be: hello world
```

**Sound familiar?** You forgot to switch keyboard layouts. Again.

Other tools make you manually select text and press hotkeys. OMFK fixes it **automatically, in real-time, as you type**.

---

## Why OMFK?

| Feature | OMFK | Punto Switcher | Caramba |
|---------|------|----------------|---------|
| Real-time auto-correction | ✅ | ❌ | ❌ |
| On-device ML (no cloud) | ✅ | ❌ | ❌ |
| Per-segment smart correction | ✅ | ❌ | ❌ |
| Hebrew support | ✅ | ❌ | ❌ |
| Native macOS (SwiftUI) | ✅ | ❌ | ✅ |
| Privacy-first (no logging) | ✅ | ❌ | ✅ |
| Liquid Glass UI (macOS 26) | ✅ | ❌ | ❌ |

---

## Features

### 🧠 Smart Per-Segment Correction
Unlike dumb "convert everything" tools, OMFK analyzes **each word separately**:

```
Input:  "текст в котором ytrjnjhst xfcnb были написаны wrong"
Output: "текст в котором некоторые части были написаны wrong"
                        ↑ fixed      ↑ fixed         ↑ kept (intentional English)
```

### ⚡ Real-Time Auto-Correction
Type naturally. OMFK detects wrong layouts on word boundaries and fixes them instantly — **under 50ms latency**.

### 🔄 Hotkey Cycling
Press `⌥ Option` to cycle through all possible interpretations:
- Original text (undo)
- Smart correction (per-segment)
- Full RU conversion
- Full EN conversion  
- Full HE conversion

### 🔒 Privacy-First
- **100% on-device** — no network calls, ever
- **No persistent logging** — text buffers cleared immediately after correction
- **No telemetry** — we don't know what you type

### 🌍 Trilingual Support
First-class support for the three-layout nightmare:
- 🇺🇸 English (QWERTY)
- 🇷🇺 Russian (ЙЦУКЕН, Phonetic)
- 🇮🇱 Hebrew (Standard, QWERTY)

---

## How It Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CGEventTap (System-wide)                 │
│              Captures every keystroke globally              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                     EventMonitor (Actor)                    │
│         Thread-safe event processing with Swift 6           │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────────┐ ┌───────────────┐ ┌─────────────────┐
│ CoreML Classifier│ │LayoutMapper   │ │ConfidenceRouter │
│  (13MB model)   │ │ (JSON-driven) │ │ (Ensemble logic)│
└─────────────────┘ └───────────────┘ └─────────────────┘
          │               │               │
          └───────────────┴───────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   CorrectionEngine (Actor)                  │
│    Per-segment analysis • Cycling state • History           │
└─────────────────────────────────────────────────────────────┘
```

### The ML Model

OMFK uses a custom-trained **neural network** running entirely on-device via CoreML.

**Model Architecture:**
- Embedding layer (vocab: 200+ chars including Cyrillic, Hebrew, Latin)
- 2x Transformer encoder blocks with multi-head attention
- Global average pooling → Dense → 9-class softmax

**Training Data:**
- **20 million examples** generated from Wikipedia corpora (RU/EN/HE)
- Synthetic "wrong layout" samples created by character mapping
- Data augmentation: typos, case changes, character swaps

**Classes Detected:**
```
ru, en, he                    — correct layout
ru_from_en, he_from_en        — typed on EN keyboard
en_from_ru, en_from_he        — typed on RU/HE keyboard  
he_from_ru, ru_from_he        — cross-layout errors
```

**Performance:**
- Model size: **13.8 MB** (quantized)
- Inference: **<5ms** on Apple Silicon
- Accuracy: **>95%** on held-out test set

### Layout Mapping

Character conversion uses **JSON-driven mapping tables** supporting multiple layout variants:

```json
{
  "en_us": { "q": {...}, "w": {...}, ... },
  "ru_pc": { "й": {...}, "ц": {...}, ... },
  "ru_phonetic": { "я": {...}, "ш": {...}, ... },
  "he_standard": { "ש": {...}, "ד": {...}, ... },
  "he_qwerty": { ... }
}
```

Adding a new layout = adding JSON. No code changes required.

### Confidence Routing

OMFK uses an **ensemble approach** combining:

1. **CoreML classifier** — primary signal (neural network)
2. **NLLanguageRecognizer** — Apple's built-in detector
3. **Character-set heuristics** — Unicode range analysis
4. **N-gram frequency** — statistical language patterns

The `ConfidenceRouter` weighs these signals and only corrects when confidence exceeds threshold (default: 0.6).

---

## Installation

### Requirements
- macOS Sonoma (14.0) or later
- Accessibility permission (for keyboard monitoring)

### Build from Source

```bash
git clone https://github.com/chernistry/omfk.git
cd omfk
swift build -c release
```

### Run

```bash
swift run
```

Or open in Xcode:
```bash
open Package.swift
```

### Grant Permissions

On first launch, grant these in **System Settings → Privacy & Security**:
1. **Accessibility** — required to monitor keyboard events
2. **Input Monitoring** — required to read typed characters

---

## Usage

1. **Launch OMFK** — appears in menu bar
2. **Toggle auto-correction** — click menu bar icon
3. **Type normally** — corrections happen automatically
4. **Press ⌥ Option** — cycle through alternatives if needed
5. **Configure exclusions** — disable for specific apps (terminals, password managers)

---

## Training Your Own Model

Want to customize the ML model? Full training pipeline included:

```bash
cd Tools/CoreMLTrainer

# Quick training (5 min, synthetic data)
./train_quick.sh

# Full training (1 hour, Wikipedia corpus)
./train_full.sh
```

**Pipeline steps:**
1. `download_corpus.py` — fetch Wikipedia dumps
2. `generate_data.py` — create training examples with layout simulation
3. `train.py` — train PyTorch model with augmentation
4. `export.py` — convert to CoreML format
5. Copy `.mlmodel` to `OMFK/Sources/Resources/`

---

## Technical Specs

| Metric | Value |
|--------|-------|
| Detection latency | <50ms end-to-end |
| Memory usage | <100MB |
| Model size | 13.8MB |
| Training data | 20M examples |
| Supported layouts | 6 variants |
| Languages | EN, RU, HE |
| Swift version | 5.10+ (Swift 6 ready) |
| Concurrency | Actor-based (thread-safe) |

---

## Roadmap

- [x] Real-time auto-correction
- [x] CoreML language detection
- [x] Per-segment smart correction
- [x] Hotkey cycling
- [x] Liquid Glass UI (macOS 26)
- [ ] User-trainable corrections
- [ ] Additional languages (UA, AR, etc.)
- [ ] iOS/iPadOS version

---

## Contributing

Found a bug? Have a feature idea? 

1. Check existing issues
2. Open a new issue with reproduction steps
3. PRs welcome for non-core features

---

## License

Copyright © 2025 Chernistry. All rights reserved.

---

<div align="center">

**Stop fighting your keyboard. Let OMFK handle it.**

[Download](https://github.com/chernistry/omfk/releases) · [Report Bug](https://github.com/chernistry/omfk/issues) · [Request Feature](https://github.com/chernistry/omfk/issues)

</div>
