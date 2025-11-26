#!/bin/bash

echo "Building and running OMFK with log streaming..."
echo "Press Ctrl+C to stop"
echo ""

# Build first
swift build

# Run app in background
.build/debug/OMFK &
APP_PID=$!

# Wait a bit for app to start
sleep 2

# Stream logs
echo "Streaming logs from com.chernistry.omfk..."
log stream --predicate 'subsystem == "com.chernistry.omfk"' --level debug &
LOG_PID=$!

# Wait for user interrupt
trap "kill $APP_PID $LOG_PID 2>/dev/null; exit" INT TERM

wait
