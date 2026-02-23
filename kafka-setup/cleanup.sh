#!/bin/bash
# Stops the Kafka broker and removes all auto-generated files,
# leaving only install.sh and cleanup.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Kafka Cleanup ==="

# Stop broker — try PID file first, then fall back to pgrep
if [ -f "$SCRIPT_DIR/kafka.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/kafka.pid")
    if kill "$PID" 2>/dev/null; then
        echo "Kafka stopped (PID $PID)."
    else
        echo "Process $PID already gone."
    fi
    rm -f "$SCRIPT_DIR/kafka.pid"
elif pgrep -f "kafka.Kafka" &>/dev/null; then
    pkill -f "kafka.Kafka" && echo "Kafka stopped."
else
    echo "Kafka is not running."
fi

# Remove all auto-generated files
rm -f  "$SCRIPT_DIR/server.properties" \
       "$SCRIPT_DIR/kafka.log"
rm -rf "$SCRIPT_DIR/kafka-logs"

echo "Done. Remaining files:"
ls "$SCRIPT_DIR"
