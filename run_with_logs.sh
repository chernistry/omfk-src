#!/bin/bash

# OMFK Quick Start with Live Logging
# This script builds, runs the app, and shows live logs

set -e

echo "=== OMFK Quick Start ==="
echo ""

# Build the app
echo "📦 Building OMFK..."
swift build -c debug
echo "✅ Build complete"
echo ""

# Check if app is already running
if pgrep -x "OMFK" > /dev/null; then
    echo "⚠️  OMFK is already running. Killing existing process..."
    pkill -x "OMFK"
    sleep 1
fi

# Start the app in background
echo "🚀 Starting OMFK..."
./.build/debug/OMFK &
APP_PID=$!
echo "✅ OMFK started (PID: $APP_PID)"
echo ""

# Wait a moment for app to initialize
sleep 2

# Check if app is still running
if ! kill -0 $APP_PID 2>/dev/null; then
    echo "❌ App failed to start. Check permissions:"
    echo "   System Settings → Privacy & Security → Accessibility"
    echo "   System Settings → Privacy & Security → Input Monitoring"
    exit 1
fi

echo "📊 Streaming logs (Press Ctrl+C to stop)..."
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
