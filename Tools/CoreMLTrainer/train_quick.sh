#!/usr/bin/env bash
set -euo pipefail

# Deprecated wrapper (kept for compatibility).
# Canonical entrypoint: `./omfk.sh train coreml`

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Quick preset: smaller dataset/epochs, usually enough for smoke-testing the pipeline.
export OMFK_BASE_SAMPLES="${OMFK_BASE_SAMPLES:-500000}"
export OMFK_BASE_EPOCHS="${OMFK_BASE_EPOCHS:-20}"
export OMFK_BASE_PATIENCE="${OMFK_BASE_PATIENCE:-8}"
export OMFK_HE_QWERTY_SAMPLES="${OMFK_HE_QWERTY_SAMPLES:-150000}"
export OMFK_HE_QWERTY_EPOCHS="${OMFK_HE_QWERTY_EPOCHS:-10}"
export OMFK_MAX_CORPUS_WORDS="${OMFK_MAX_CORPUS_WORDS:-500000}"

exec "${ROOT_DIR}/omfk.sh" train coreml

