#!/bin/bash
# Quick debug runner - starts OMFK with logging and tails the log
# Usage: ./scripts/debug_run.sh

OMFK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$HOME/.omfk/debug.log"

echo "Building OMFK..."
cd "$OMFK_DIR"
swift build || exit 1

# Kill existing
pkill -f ".build/debug/OMFK" 2>/dev/null || true
sleep 0.3

# Clear log
mkdir -p "$HOME/.omfk"
> "$LOG_FILE"

echo "Starting OMFK with debug logging..."
echo "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo "---"

# Start OMFK in background
OMFK_DEBUG_LOG=1 .build/debug/OMFK &
OMFK_PID=$!

cleanup() {
    echo ""
    echo "Stopping OMFK..."
    kill $OMFK_PID 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# Tail the log
sleep 1
tail -f "$LOG_FILE"
