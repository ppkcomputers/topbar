#!/usr/bin/env bash

# Automatically resolve the directory of this script, making it 100% portable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPBAR_PATH="$SCRIPT_DIR/topbar.qml"
TRIGGER_FILE="/tmp/topbar_visible_$USER"

# Initialize file if it doesn't exist
if [ ! -f "$TRIGGER_FILE" ]; then
    echo "0" > "$TRIGGER_FILE"
fi

# 1. Ensure quickshell is running this dynamic path
if ! pgrep -f "quickshell.*$TOPBAR_PATH" > /dev/null; then
    quickshell -p "$TOPBAR_PATH" > /dev/null 2>&1 &
    sleep 0.2
fi

# 2. Toggle the state
CURRENT_STATE=$(cat "$TRIGGER_FILE")

if [ "$CURRENT_STATE" = "1" ]; then
    echo "0" > "$TRIGGER_FILE"
else
    echo "1" > "$TRIGGER_FILE"
fi
