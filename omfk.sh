#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROCESSED_DIR="${OMFK_PROCESSED_DIR:-"${ROOT_DIR}/data/processed"}"
RAW_DIR="${OMFK_RAW_DIR:-"${ROOT_DIR}/data/raw"}"
RESOURCES_DIR="${OMFK_RESOURCES_DIR:-"${ROOT_DIR}/OMFK/Sources/Resources"}"
LANG_MODELS_DIR="${RESOURCES_DIR}/LanguageModels"

NGRAM_DIR="${ROOT_DIR}/Tools/NgramTrainer"
COREML_DIR="${ROOT_DIR}/Tools/CoreMLTrainer"

COLOR_GREEN=$'\033[0;32m'
COLOR_BLUE=$'\033[0;34m'
COLOR_YELLOW=$'\033[1;33m'
COLOR_RED=$'\033[0;31m'
COLOR_RESET=$'\033[0m'

say() { printf "%s\n" "$*"; }
info() { say "${COLOR_BLUE}$*${COLOR_RESET}"; }
ok() { say "${COLOR_GREEN}$*${COLOR_RESET}"; }
success() { say "${COLOR_GREEN}✅ $*${COLOR_RESET}"; }
warn() { say "${COLOR_YELLOW}$*${COLOR_RESET}"; }
err() { say "${COLOR_RED}$*${COLOR_RESET}" >&2; }
die() { err "ERROR: $*"; exit 1; }

file_mtime() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf "%s" "-"
    return
  fi
  stat -f "%Sm" "$path" 2>/dev/null || stat -c "%y" "$path" 2>/dev/null || printf "%s" "?"
}

file_size() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    printf "%s" "-"
    return
  fi
  stat -f "%z" "$path" 2>/dev/null || stat -c "%s" "$path" 2>/dev/null || printf "%s" "?"
}

ensure_dir() {
  local path="$1"
  [[ -d "$path" ]] || mkdir -p "$path"
}

usage() {
  cat <<'EOF'
omfk.sh — unified CLI for OMFK training / evaluation / release

Usage:
  ./omfk.sh <command> [subcommand] [options]
  ./omfk.sh              # Interactive menu

Commands:
  status                 Show project status and guidance
  test                   Run Swift tests
  run [--logs]           Build and run OMFK
  eval synthetic         Run synthetic evaluation
  train ngrams           Train n-gram language models
  train coreml [opts]    Train CoreML classifier
  train all [opts]       Train everything
  corpus download-subtitles [--limit N]
  corpus extract-wikipedia --lang ru|en|he
  corpus import-telegram --file result.json
  logs stream            Stream system logs
  release build --version X.Y.Z

Environment:
  OMFK_ULTRA=1           Enable ultra training mode
  OMFK_FORCE_RETRAIN=1   Force model retraining
EOF
}

# Interactive menu using fzf or fallback to select
interactive_menu() {
  local options=(
    "🚀 run            → Build and run OMFK"
    "📊 status         → Show project status"
    "🧪 test           → Run Swift tests"
    "📈 eval synthetic → Run synthetic evaluation"
    "🔤 train ngrams   → Train n-gram models"
    "🧠 train coreml   → Train CoreML model"
    "⚡ train all      → Train everything"
    "📥 corpus download-subtitles → Download OpenSubtitles"
    "📜 logs stream    → Stream debug logs"
    "📦 release build  → Build DMG release"
    "🌐 release github → Trigger GitHub release"
    "❌ quit           → Exit"
  )

  local choice
  if command -v fzf &>/dev/null; then
    choice=$(printf '%s\n' "${options[@]}" | fzf --height=15 --reverse --prompt="OMFK> " --header="Select action:" --ansi)
  else
    echo ""
    echo "${COLOR_BLUE}═══════════════════════════════════════${COLOR_RESET}"
    echo "${COLOR_BLUE}       OMFK — Keyboard Layout Fixer    ${COLOR_RESET}"
    echo "${COLOR_BLUE}═══════════════════════════════════════${COLOR_RESET}"
    echo ""
    PS3=$'\n'"${COLOR_GREEN}Select option: ${COLOR_RESET}"
    select opt in "${options[@]}"; do
      choice="$opt"
      break
    done
  fi

  [[ -z "$choice" ]] && exit 0

  # Extract command from choice
  local cmd
  cmd=$(echo "$choice" | sed 's/^[^ ]* //' | cut -d'→' -f1 | xargs)

  case "$cmd" in
    "run") cmd_run ;;
    "status") cmd_status ;;
    "test") cmd_test ;;
    "eval synthetic") cmd_eval_synthetic ;;
    "train ngrams") cmd_train_ngrams ;;
    "train coreml")
      echo ""
      read -rp "Use ULTRA mode? (y/N): " ultra
      if [[ "$ultra" =~ ^[Yy]$ ]]; then
        cmd_train_coreml --ultra
      else
        cmd_train_coreml
      fi
      ;;
    "train all")
      echo ""
      read -rp "Use ULTRA mode? (y/N): " ultra
      if [[ "$ultra" =~ ^[Yy]$ ]]; then
        cmd_train_all --ultra
      else
        cmd_train_all
      fi
      ;;
    "corpus download-subtitles") cmd_corpus_download_subtitles ;;
    "logs stream") cmd_logs_stream ;;
    "release build")
      echo ""
      read -rp "Version (e.g. 1.0.0): " ver
      [[ -n "$ver" ]] && cmd_release_build --version "$ver"
      ;;
    "release github") cmd_release_github ;;
    "quit") exit 0 ;;
    *) die "Unknown selection" ;;
  esac
}

cmd_status() {
  say "=== OMFK STATUS ==="
  say "Repo:        ${ROOT_DIR}"
  say "Processed:   ${PROCESSED_DIR}"
  say "Resources:   ${RESOURCES_DIR}"
  say ""

  say "Corpora:"
  local corp_ru="${PROCESSED_DIR}/ru.txt"
  local corp_en="${PROCESSED_DIR}/en.txt"
  local corp_he="${PROCESSED_DIR}/he.txt"
  for f in "${PROCESSED_DIR}/ru.txt" "${PROCESSED_DIR}/en.txt" "${PROCESSED_DIR}/he.txt"; do
    say "  - $(basename "$f"): exists=$([[ -f "$f" ]] && echo yes || echo no) size=$(file_size "$f") mtime=$(file_mtime "$f")"
  done
  for f in "${PROCESSED_DIR}/subtitles_ru.txt" "${PROCESSED_DIR}/subtitles_he.txt"; do
    if [[ -f "$f" ]]; then
      warn "  ! Found residual subtitles file: $(basename "$f") (recommended: merge then delete)"
    fi
  done
  say ""

  say "Language models (resources):"
  local tri_ru="${LANG_MODELS_DIR}/ru_trigrams.json"
  local tri_en="${LANG_MODELS_DIR}/en_trigrams.json"
  local tri_he="${LANG_MODELS_DIR}/he_trigrams.json"
  local uni_ru="${LANG_MODELS_DIR}/ru_unigrams.tsv"
  local uni_en="${LANG_MODELS_DIR}/en_unigrams.tsv"
  local uni_he="${LANG_MODELS_DIR}/he_unigrams.tsv"
  for f in "${LANG_MODELS_DIR}/ru_trigrams.json" "${LANG_MODELS_DIR}/en_trigrams.json" "${LANG_MODELS_DIR}/he_trigrams.json" \
           "${LANG_MODELS_DIR}/ru_unigrams.tsv" "${LANG_MODELS_DIR}/en_unigrams.tsv" "${LANG_MODELS_DIR}/he_unigrams.tsv"; do
    say "  - $(basename "$f"): exists=$([[ -f "$f" ]] && echo yes || echo no) size=$(file_size "$f") mtime=$(file_mtime "$f")"
  done
  say ""

  say "CoreML model (resources):"
  local ml="${RESOURCES_DIR}/LayoutClassifier.mlmodel"
  say "  - LayoutClassifier.mlmodel: exists=$([[ -f "$ml" ]] && echo yes || echo no) size=$(file_size "$ml") mtime=$(file_mtime "$ml")"
  say ""

  say "CoreML trainer artifacts:"
  local ds="${COREML_DIR}/training_data_combined.csv"
  local pth_base="${COREML_DIR}/model_production.pth"
  local pth_he="${COREML_DIR}/model_production_he_qwerty.pth"
  local pth_ultra="${COREML_DIR}/model_ultra.pth"
  for f in "${COREML_DIR}/training_data_combined.csv" "${COREML_DIR}/model_production.pth" "${COREML_DIR}/model_production_he_qwerty.pth" "${COREML_DIR}/model_ultra.pth"; do
    say "  - $(basename "$f"): exists=$([[ -f "$f" ]] && echo yes || echo no) size=$(file_size "$f") mtime=$(file_mtime "$f")"
  done
  say ""

  say "Quick guidance:"
  if [[ ! -f "${tri_ru}" || ! -f "${tri_en}" || ! -f "${tri_he}" || ! -f "${uni_ru}" || ! -f "${uni_en}" || ! -f "${uni_he}" ]]; then
    warn "  - N-grams/unigrams missing → run: ./omfk.sh train ngrams"
  else
    if [[ -f "${corp_ru}" && ( "${corp_ru}" -nt "${tri_ru}" || "${corp_ru}" -nt "${uni_ru}" ) ]]; then
      warn "  - RU corpus newer than RU models → run: ./omfk.sh train ngrams"
    fi
    if [[ -f "${corp_en}" && ( "${corp_en}" -nt "${tri_en}" || "${corp_en}" -nt "${uni_en}" ) ]]; then
      warn "  - EN corpus newer than EN models → run: ./omfk.sh train ngrams"
    fi
    if [[ -f "${corp_he}" && ( "${corp_he}" -nt "${tri_he}" || "${corp_he}" -nt "${uni_he}" ) ]]; then
      warn "  - HE corpus newer than HE models → run: ./omfk.sh train ngrams"
    fi
  fi
  if [[ ! -f "${RESOURCES_DIR}/LayoutClassifier.mlmodel" ]]; then
    warn "  - CoreML model missing → run: ./omfk.sh train coreml"
  else
    local layouts_spec_sdd="${ROOT_DIR}/.sdd/layouts.json"
    local layouts_spec_res="${RESOURCES_DIR}/layouts.json"
    if [[ -f "${layouts_spec_sdd}" && "${layouts_spec_sdd}" -nt "${ml}" ]]; then
      warn "  - .sdd/layouts.json newer than CoreML model → run: ./omfk.sh train coreml"
    fi
    if [[ -f "${layouts_spec_res}" && "${layouts_spec_res}" -nt "${ml}" ]]; then
      warn "  - Resources/layouts.json newer than CoreML model → run: ./omfk.sh train coreml"
    fi
    if [[ -f "${ds}" && "${ds}" -nt "${ml}" ]]; then
      warn "  - training_data_combined.csv newer than CoreML model → run: ./omfk.sh train coreml (and maybe OMFK_FORCE_RETRAIN=1)"
    fi
    if [[ ! -f "${pth_base}" && ! -f "${pth_he}" && ! -f "${pth_ultra}" ]]; then
      warn "  - No CoreMLTrainer checkpoints (.pth). App can run, but further fine-tuning requires retrain."
    elif [[ -f "${pth_ultra}" && ! -f "${pth_base}" ]]; then
      ok "  - Found model_ultra.pth (Beam Cloud trained). To use as base: cp model_ultra.pth model_production.pth"
    fi
  fi
  ok "  - Run tests: ./omfk.sh test"
  ok "  - Run synthetic eval: OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC=98 ./omfk.sh eval synthetic"
}

cmd_test() {
  info "Running Swift tests..."
  (cd "${ROOT_DIR}" && swift test)
}

cmd_eval_synthetic() {
  info "Running synthetic evaluation..."
  local cases="${OMFK_SYNTH_EVAL_CASES_PER_LANG:-500}"
  local seed="${OMFK_SYNTH_EVAL_SEED:-42}"
  local min="${OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC:-}"
  say "Env:"
  say "  OMFK_SYNTH_EVAL_CASES_PER_LANG=${cases}"
  say "  OMFK_SYNTH_EVAL_SEED=${seed}"
  [[ -n "${min}" ]] && say "  OMFK_SYNTH_EVAL_MIN_OUTPUT_ACC=${min}"
  (cd "${ROOT_DIR}" && OMFK_RUN_SYNTH_EVAL=1 swift test --filter SyntheticEvaluationTests/testSyntheticEvaluationIfEnabled)
}

cmd_train_ngrams() {
  ensure_dir "${LANG_MODELS_DIR}"
  local top="${OMFK_UNIGRAM_TOP:-200000}"

  info "Training trigram + unigram models from processed corpora..."
  say "  processed=${PROCESSED_DIR}"
  say "  top_unigrams=${top}"

  (cd "${NGRAM_DIR}" && \
    [[ -f "${PROCESSED_DIR}/ru.txt" ]] && python3 train_ngrams.py --lang ru --input "${PROCESSED_DIR}/ru.txt" --output "${LANG_MODELS_DIR}/ru_trigrams.json"; \
    [[ -f "${PROCESSED_DIR}/en.txt" ]] && python3 train_ngrams.py --lang en --input "${PROCESSED_DIR}/en.txt" --output "${LANG_MODELS_DIR}/en_trigrams.json"; \
    [[ -f "${PROCESSED_DIR}/he.txt" ]] && python3 train_ngrams.py --lang he --input "${PROCESSED_DIR}/he.txt" --output "${LANG_MODELS_DIR}/he_trigrams.json"; \
    [[ -f "${PROCESSED_DIR}/ru.txt" ]] && python3 train_unigrams.py --lang ru --top "${top}" --input "${PROCESSED_DIR}/ru.txt" --output "${LANG_MODELS_DIR}/ru_unigrams.tsv"; \
    [[ -f "${PROCESSED_DIR}/en.txt" ]] && python3 train_unigrams.py --lang en --top "${top}" --input "${PROCESSED_DIR}/en.txt" --output "${LANG_MODELS_DIR}/en_unigrams.tsv"; \
    [[ -f "${PROCESSED_DIR}/he.txt" ]] && python3 train_unigrams.py --lang he --top "${top}" --input "${PROCESSED_DIR}/he.txt" --output "${LANG_MODELS_DIR}/he_unigrams.tsv" \
  )
  ok "N-gram models updated: ${LANG_MODELS_DIR}"
}

coreml_activate_venv() {
  if [[ ! -d "${COREML_DIR}/venv" ]]; then
    info "Creating CoreMLTrainer venv..."
    (cd "${COREML_DIR}" && python3 -m venv venv)
  fi
  # shellcheck disable=SC1091
  source "${COREML_DIR}/venv/bin/activate"
}

cmd_train_coreml() {
  local ultra="${OMFK_ULTRA:-0}"
  local yes=0
  local skip_finetune="${OMFK_SKIP_HE_QWERTY_FINETUNE:-0}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ultra) ultra=1; shift ;;
      --yes|-y) yes=1; shift ;;
      --skip-finetune) skip_finetune=1; shift ;;
      *) die "Unknown flag for train coreml: $1" ;;
    esac
  done

  info "--- Training CoreML model (ensemble) ---"
  coreml_activate_venv
  (cd "${COREML_DIR}" && pip install -q -r requirements.txt)
  (cd "${COREML_DIR}" && pip uninstall -y scikit-learn >/dev/null 2>&1 || true)

  local base_model="${COREML_DIR}/model_production.pth"
  local finetuned_model="${COREML_DIR}/model_production_he_qwerty.pth"
  local layouts_spec="${ROOT_DIR}/.sdd/layouts.json"

  local base_samples="${OMFK_BASE_SAMPLES:-5000000}"
  local base_epochs="${OMFK_BASE_EPOCHS:-100}"
  local base_batch="${OMFK_BASE_BATCH_SIZE:-512}"
  local base_lr="${OMFK_BASE_LR:-0.001}"
  local base_patience="${OMFK_BASE_PATIENCE:-15}"

  local he_samples="${OMFK_HE_QWERTY_SAMPLES:-500000}"
  local he_epochs="${OMFK_HE_QWERTY_EPOCHS:-20}"
  local he_batch="${OMFK_HE_QWERTY_BATCH_SIZE:-512}"
  local he_lr="${OMFK_HE_QWERTY_LR:-0.0001}"
  local he_patience="${OMFK_HE_QWERTY_PATIENCE:-5}"

  local max_corpus_words="${OMFK_MAX_CORPUS_WORDS:-2000000}"
  local corpus_sample_mode="${OMFK_CORPUS_SAMPLE_MODE:-reservoir}"
  local force_retrain="${OMFK_FORCE_RETRAIN:-0}"
  local force_regen_data="${OMFK_FORCE_REGEN_DATA:-0}"
  local skip_retrain_on_layout_change="${OMFK_SKIP_BASE_RETRAIN_ON_LAYOUT_CHANGE:-0}"
  local base_dataset="${OMFK_BASE_DATASET:-training_data_combined.csv}"

  if [[ "${ultra}" == "1" ]]; then
    warn "OMFK_ULTRA=1 enabled → maximizing training sizes (expect long runtimes)."
    base_samples="${OMFK_BASE_SAMPLES:-20000000}"
    base_epochs="${OMFK_BASE_EPOCHS:-120}"
    base_patience="${OMFK_BASE_PATIENCE:-20}"
    he_samples="${OMFK_HE_QWERTY_SAMPLES:-2000000}"
    he_epochs="${OMFK_HE_QWERTY_EPOCHS:-30}"
    he_patience="${OMFK_HE_QWERTY_PATIENCE:-8}"
    max_corpus_words="${OMFK_MAX_CORPUS_WORDS:-0}"
  fi

  say "Config:"
  say "  base_dataset=${base_dataset}"
  say "  base_samples=${base_samples} base_epochs=${base_epochs} base_batch=${base_batch} base_lr=${base_lr} base_patience=${base_patience}"
  say "  he_qwerty_samples=${he_samples} he_epochs=${he_epochs} he_batch=${he_batch} he_lr=${he_lr} he_patience=${he_patience}"
  say "  max_corpus_words=${max_corpus_words} corpus_sample_mode=${corpus_sample_mode}"
  say "  force_retrain=${force_retrain} force_regen_data=${force_regen_data} skip_he_qwerty_finetune=${skip_finetune}"

  local should_train_base=0
  if [[ "${force_retrain}" == "1" ]]; then
    warn "OMFK_FORCE_RETRAIN=1 → will retrain base model."
    should_train_base=1
  fi

  if [[ "${should_train_base}" == "0" && -f "${base_model}" && -f "${layouts_spec}" && "${skip_retrain_on_layout_change}" != "1" ]]; then
    if [[ "${layouts_spec}" -nt "${base_model}" ]]; then
      warn "Base model is older than layouts spec → retraining base model (set OMFK_SKIP_BASE_RETRAIN_ON_LAYOUT_CHANGE=1 to skip)."
      should_train_base=1
    fi
  fi

  if [[ "${should_train_base}" == "0" && -f "${base_model}" ]]; then
    (cd "${COREML_DIR}" && python3 - <<'PY') || should_train_base=1
import torch
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

  (cd "${COREML_DIR}" && \
    if [[ "${should_train_base}" == "1" || ! -f "model_production.pth" ]]; then
      warn "Training base model from scratch..."
      if [[ -f "${base_dataset}" && "${force_regen_data}" != "1" ]]; then
        ok "Found base dataset: ${base_dataset} (set OMFK_FORCE_REGEN_DATA=1 to regenerate)"
      else
        info "Generating base dataset from corpora..."
        python3 generate_data.py \
          --count "${base_samples}" \
          --balance 0.5 \
          --max-phrase-len 5 \
          --max-corpus-words "${max_corpus_words}" \
          --corpus-sample-mode "${corpus_sample_mode}" \
          --output "${base_dataset}" \
          --corpus_dir "${PROCESSED_DIR}"
      fi
      info "Training base checkpoint..."
      python3 train.py \
        --epochs "${base_epochs}" --batch_size "${base_batch}" --lr "${base_lr}" --patience "${base_patience}" \
        --ensemble --augment --mixup \
        --data "${base_dataset}" --model_out "model_production.pth"
    else
      ok "Found base model: model_production.pth"
    fi \
  )

  local model_for_export="${base_model}"
  if [[ "${skip_finetune}" != "1" ]]; then
    (cd "${COREML_DIR}" && \
      info "--- Fine-tuning for Hebrew QWERTY sofits (Ticket 23) ---" && \
      python3 generate_data.py \
        --count "${he_samples}" \
        --balance 0.3 \
        --max-phrase-len 5 \
        --max-corpus-words "${max_corpus_words}" \
        --corpus-sample-mode "${corpus_sample_mode}" \
        --output "training_data_he_qwerty.csv" \
        --corpus_dir "${PROCESSED_DIR}" \
        --focus-layout "he_qwerty" && \
      python3 train.py \
        --epochs "${he_epochs}" --batch_size "${he_batch}" --lr "${he_lr}" --patience "${he_patience}" \
        --ensemble --finetune --model_in "model_production.pth" --augment \
        --data "training_data_he_qwerty.csv" --model_out "model_production_he_qwerty.pth" \
    )
    model_for_export="${finetuned_model}"
  else
    warn "Skipping he_qwerty fine-tune (OMFK_SKIP_HE_QWERTY_FINETUNE=1)."
  fi

  (cd "${COREML_DIR}" && \
    info "Exporting to CoreML..." && \
    python3 export.py --model_in "${model_for_export}" --output "LayoutClassifier.mlmodel" --ensemble && \
    info "Validating CoreML export vs PyTorch..." && \
    python3 validate_export.py --ensemble --model_in "${model_for_export}" --mlmodel "LayoutClassifier.mlmodel" --samples 20 --tol 0.01 \
  )

  info "Installing CoreML model into app resources..."
  cp "${COREML_DIR}/LayoutClassifier.mlmodel" "${RESOURCES_DIR}/LayoutClassifier.mlmodel"
  ok "Installed: ${RESOURCES_DIR}/LayoutClassifier.mlmodel"

  if [[ "${yes}" == "0" ]]; then
    info "Running Swift tests (can be skipped with --yes)..."
    cmd_test
  fi
}

cmd_train_all() {
  local ultra=0
  local yes=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ultra) ultra=1; shift ;;
      --yes|-y) yes=1; shift ;;
      *) die "Unknown flag for train all: $1" ;;
    esac
  done

  if [[ "${ultra}" == "1" ]]; then
    export OMFK_ULTRA=1
  fi
  cmd_train_ngrams
  cmd_train_coreml --yes
  if [[ "${yes}" == "0" ]]; then
    cmd_test
  fi
}

cmd_corpus_download_subtitles() {
  local limit="${OMFK_SUBTITLES_LIMIT:-2000000}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) die "Unknown flag for corpus download-subtitles: $1" ;;
    esac
  done
  coreml_activate_venv
  (cd "${COREML_DIR}" && pip install -q -r requirements.txt)
  info "Downloading OpenSubtitles (he_mono, ru_mono) limit=${limit}..."
  (cd "${COREML_DIR}" && python3 download_subtitles.py --only he_mono ru_mono --limit "${limit}")
  info "Merging subtitles into main corpus (idempotent)..."
  OMFK_ROOT_DIR="${ROOT_DIR}" python3 - <<'PY'
from pathlib import Path

root = Path.cwd()
env_root = __import__("os").environ.get("OMFK_ROOT_DIR")
if env_root:
    root = Path(env_root)
PROCESSED = root / "data" / "processed"

def merge(main_path: Path, sub_path: Path) -> None:
    if not sub_path.exists():
        return
    if not main_path.exists():
        main_path.write_bytes(sub_path.read_bytes())
        sub_path.unlink(missing_ok=True)
        print(f"  Created {main_path} from {sub_path.name}")
        return

    ms = main_path.stat().st_size
    ss = sub_path.stat().st_size

    # If subtitles are already appended, delete the duplicate file.
    if ms >= ss:
        chunk = min(256 * 1024, ss)
        with main_path.open('rb') as mf, sub_path.open('rb') as sf:
            mf.seek(ms - chunk)
            sf.seek(ss - chunk)
            if mf.read(chunk) == sf.read(chunk):
                sub_path.unlink(missing_ok=True)
                print(f"  Already merged: {sub_path.name} (deleted)")
                return

    # Ensure main ends with newline.
    with main_path.open('rb') as mf:
        mf.seek(max(0, ms - 1))
        last = mf.read(1)
    with main_path.open('ab') as mf:
        if last not in (b'\n', b'\r'):
            mf.write(b'\n')
        with sub_path.open('rb') as sf:
            while True:
                buf = sf.read(1024 * 1024)
                if not buf:
                    break
                mf.write(buf)

    sub_path.unlink(missing_ok=True)
    print(f"  Merged and deleted: {sub_path.name} -> {main_path.name}")

merge(PROCESSED / "he.txt", PROCESSED / "subtitles_he.txt")
merge(PROCESSED / "ru.txt", PROCESSED / "subtitles_ru.txt")
PY
  ok "Subtitles imported and merged into ${PROCESSED_DIR}."
}

cmd_corpus_extract_wikipedia() {
  local lang=""
  local input=""
  local output=""
  local limit="${OMFK_WIKI_LIMIT:-50000}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang) lang="$2"; shift 2 ;;
      --input) input="$2"; shift 2 ;;
      --output) output="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *) die "Unknown flag for corpus extract-wikipedia: $1" ;;
    esac
  done
  [[ -n "${lang}" ]] || die "corpus extract-wikipedia requires --lang {ru|en|he}"
  [[ "${lang}" == "ru" || "${lang}" == "en" || "${lang}" == "he" ]] || die "Unsupported lang: ${lang}"

  ensure_dir "${PROCESSED_DIR}"

  if [[ -z "${input}" ]]; then
    case "${lang}" in
      ru) input="${RAW_DIR}/ruwiki-latest-pages-articles-multistream1.xml-p1p224167.bz2" ;;
      en) input="${RAW_DIR}/enwiki-latest-pages-articles-multistream1.xml-p1p41242.bz2" ;;
      he) input="${RAW_DIR}/hewiki-latest-pages-articles-multistream.xml.bz2" ;;
    esac
  fi

  if [[ -z "${output}" ]]; then
    output="${PROCESSED_DIR}/${lang}.txt"
  fi

  [[ -f "${input}" ]] || die "Wikipedia dump not found: ${input}"

  info "Extracting ${lang} Wikipedia corpus..."
  say "  input=${input}"
  say "  output=${output}"
  say "  limit=${limit}"
  python3 "${ROOT_DIR}/Tools/Shared/extract_corpus.py" --input "${input}" --output "${output}" --limit "${limit}"
  ok "Extracted: ${output}"
}

cmd_corpus_import_telegram() {
  ensure_dir "${PROCESSED_DIR}"
  local outdir="${PROCESSED_DIR}"
  local files=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output-dir) outdir="$2"; shift 2 ;;
      --file) files+=("$2"); shift 2 ;;
      *) die "Unknown flag for corpus import-telegram: $1" ;;
    esac
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    die "corpus import-telegram requires one or more --file /path/to/result.json"
  fi

  local existing=()
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      existing+=("$f")
    else
      warn "Skipping (not found): $f"
    fi
  done
  [[ ${#existing[@]} -gt 0 ]] || die "No Telegram export files found."

  info "Importing Telegram exports into ${outdir}..."
  python3 "${ROOT_DIR}/Tools/Shared/extract_telegram.py" "${existing[@]}" --output-dir "${outdir}"
  ok "Telegram data imported."
}

cmd_release_build() {
  local version=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version="$2"; shift 2 ;;
      *) die "Unknown flag for release build: $1" ;;
    esac
  done
  [[ -n "${version}" ]] || die "release build requires --version X.Y.Z"
  info "Building release DMG..."
  (cd "${ROOT_DIR}/releases" && ./build_release.sh "${version}")
}

cmd_release_github() {
  local release_type="patch"
  local version=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) release_type="$2"; shift 2 ;;
      --version) version="$2"; shift 2 ;;
      *) die "Unknown flag: $1. Use --type [patch|minor|major] or --version X.Y.Z" ;;
    esac
  done
  
  # Check gh CLI
  if ! command -v gh &>/dev/null; then
    die "GitHub CLI (gh) not installed. Run: brew install gh"
  fi
  
  # Check auth
  if ! gh auth status &>/dev/null; then
    die "Not authenticated. Run: gh auth login"
  fi
  
  # Get latest tag and suggest next version
  local latest=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
  latest=${latest#v}
  
  IFS='.' read -r major minor patch <<< "$latest"
  
  case "$release_type" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
  esac
  
  local suggested="${major}.${minor}.${patch}"
  
  if [[ -z "$version" ]]; then
    echo ""
    info "Latest release: ${COLOR_YELLOW}v${latest}${COLOR_RESET}"
    info "Suggested next (${release_type}): ${COLOR_GREEN}v${suggested}${COLOR_RESET}"
    echo ""
    read -p "Version to release [${suggested}]: " version
    version=${version:-$suggested}
  fi
  
  info "Triggering GitHub Actions release for v${version}..."
  
  gh workflow run release.yml \
    --field version="${version}" \
    --field release_type="${release_type}"
  
  success "Release workflow triggered!"
  info "Watch progress: gh run watch"
  echo ""
  info "Or open: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions"
}

cmd_logs_stream() {
  info "Streaming logs (Ctrl+C to stop)..."
  log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug --style compact
}

cmd_run() {
  local with_logs=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --logs) with_logs=1; shift ;;
      *) die "Unknown flag for run: $1" ;;
    esac
  done

  info "Building (debug)..."
  (cd "${ROOT_DIR}" && swift build -c debug)

  if pgrep -x "OMFK" >/dev/null 2>&1; then
    warn "OMFK is already running. Killing existing process..."
    pkill -x "OMFK" || true
    sleep 1
  fi

  info "Starting OMFK..."
  (cd "${ROOT_DIR}" && ./.build/debug/OMFK) &
  local app_pid=$!

  sleep 2
  if ! kill -0 "${app_pid}" >/dev/null 2>&1; then
    die "App failed to start. Check permissions: Accessibility + Input Monitoring."
  fi

  if [[ "${with_logs}" == "1" ]]; then
    trap 'kill "${app_pid}" 2>/dev/null || true' INT TERM
    cmd_logs_stream
  else
    wait "${app_pid}"
  fi
}

main() {
  local cmd="${1:-}"
  shift || true

  # No args = interactive menu
  if [[ -z "${cmd}" ]]; then
    interactive_menu
    exit 0
  fi

  case "${cmd}" in
    "-h"|"--help"|"help") usage ;;
    "-i"|"--interactive"|"menu") interactive_menu ;;
    status) cmd_status ;;
    test) cmd_test ;;
    eval)
      case "${1:-}" in
        synthetic) shift; cmd_eval_synthetic "$@" ;;
        *) die "Unknown eval subcommand. Use: eval synthetic" ;;
      esac
      ;;
    train)
      case "${1:-}" in
        ngrams) shift; cmd_train_ngrams "$@" ;;
        coreml) shift; cmd_train_coreml "$@" ;;
        all) shift; cmd_train_all "$@" ;;
        *) die "Unknown train subcommand. Use: train ngrams|coreml|all" ;;
      esac
      ;;
    corpus)
      case "${1:-}" in
        download-subtitles) shift; cmd_corpus_download_subtitles "$@" ;;
        extract-wikipedia) shift; cmd_corpus_extract_wikipedia "$@" ;;
        import-telegram) shift; cmd_corpus_import_telegram "$@" ;;
        *) die "Unknown corpus subcommand. Use: corpus download-subtitles|extract-wikipedia|import-telegram" ;;
      esac
      ;;
    release)
      case "${1:-}" in
        build) shift; cmd_release_build "$@" ;;
        github) shift; cmd_release_github "$@" ;;
        *) die "Unknown release subcommand. Use: release build|github" ;;
      esac
      ;;
    logs)
      case "${1:-}" in
        stream) shift; cmd_logs_stream "$@" ;;
        *) die "Unknown logs subcommand. Use: logs stream" ;;
      esac
      ;;
    run) cmd_run "$@" ;;
    *)
      die "Unknown command: ${cmd}. Use --help."
      ;;
  esac
}

main "$@"
