#!/bin/bash

# OMFK Real-time Log Viewer
# This script streams all OMFK logs from the unified logging system

echo "=== OMFK Log Viewer ==="
echo "Streaming logs from subsystem: com.chernistry.omfk"
echo "Categories: app, engine, detection, events, inputSource, hotkey"
echo ""
echo "Press Ctrl+C to stop"
echo "========================================"
echo ""

# Stream logs with color highlighting
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug --style compact | \
  sed -E \
    -e 's/(===.*===)/\x1b[1;36m\1\x1b[0m/g' \
    -e 's/(✅)/\x1b[1;32m\1\x1b[0m/g' \
    -e 's/(❌)/\x1b[1;31m\1\x1b[0m/g' \
    -e 's/(⚠️)/\x1b[1;33m\1\x1b[0m/g' \
    -e 's/(🔥)/\x1b[1;35m\1\x1b[0m/g' \
    -e 's/(🔍|🔄|📍|⌨️|📱|🎯|📖|🧹)/\x1b[1;34m\1\x1b[0m/g'
