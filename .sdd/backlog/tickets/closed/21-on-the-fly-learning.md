# Ticket 21: On-the-Fly Learning from Alt Corrections

Spec version: v1.0

## Context

When users press Alt to manually correct text, this signals that the automatic detection failed. This feedback is valuable for improving the model over time.

## Objective

1. **Log all Alt-key corrections** to a local file for later analysis
2. **Optionally fine-tune models** based on accumulated corrections
3. **Adjust user-specific thresholds** based on correction patterns

## Definition of Done

### Phase 1: Logging Alt Corrections

- [ ] **Correction Log File** (`~/.omfk/corrections.jsonl`):
  ```jsonl
  {"ts":"2024-12-21T14:00:00Z","original":"ghbdtn","final":"привет","auto_attempted":"ru","user_selected":"ru","app":"com.cursor"}
  {"ts":"2024-12-21T14:00:05Z","original":"не понимаю","final":"не понимаю","auto_attempted":"en","user_selected":null,"app":"com.cursor"}
  ```

- [ ] **Fields to Log**:
  - `ts`: Timestamp
  - `original`: Original text before any correction
  - `final`: Final text after user confirmed/cycled
  - `auto_attempted`: What the system tried to do automatically
  - `user_selected`: What the user manually selected (null if reverted to original)
  - `app`: Bundle ID of active application

### Phase 2: Batch Fine-Tuning (Future)

- [ ] **Export Script** (`Tools/Training/export_corrections.py`):
  - Read `corrections.jsonl`
  - Convert to training data format (text,label)
  - Merge with existing training data

- [ ] **Retrain with User Data**:
  - Add option to `train_master.sh`: "Include user corrections"
  - Weight user corrections higher in training

### Phase 3: Real-Time Adaptation

- [ ] **UserLanguageProfile Enhancement**:
  - Track per-word patterns: "ghbdtn usually means ru_from_en"
  - Lower threshold for frequently corrected patterns
  - Raise threshold for frequently reverted patterns

## Files to Create/Modify

- `OMFK/Sources/Core/CorrectionLogger.swift` — **NEW**
- `OMFK/Sources/Engine/CorrectionEngine.swift` — log corrections
- `OMFK/Sources/Core/UserLanguageProfile.swift` — learn from corrections
- `Tools/Training/export_corrections.py` — **NEW**
- `train_master.sh` — add option for user data

## Data Storage

- **Location**: `~/.omfk/corrections.jsonl`
- **Format**: JSON Lines (one JSON object per line)
- **Rotation**: Keep last 10,000 corrections (FIFO)
- **Privacy**: All data stays local, never uploaded

## Dependencies

- Ticket 20 (Alt-key cycling)

## Priority

**P2 — MEDIUM** — Enables long-term improvement but not blocking core functionality.
