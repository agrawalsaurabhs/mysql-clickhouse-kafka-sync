#!/bin/bash
# Stops the sink connector and removes the binary and all auto-generated files,
# leaving only main.go, go.mod, config.hjson, install.sh and cleanup.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Sink Connector Cleanup ==="

# Stop process if running
if [ -f "$SCRIPT_DIR/sink.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/sink.pid")
    if kill "$PID" 2>/dev/null; then
        echo "Connector stopped (PID $PID)."
    else
        echo "Process $PID already gone."
    fi
    rm -f "$SCRIPT_DIR/sink.pid"
else
    echo "No PID file — connector not running."
fi

# Remove binary, logs and generated Go files
rm -f "$SCRIPT_DIR/mysql-clickhouse-sink" \
      "$SCRIPT_DIR/sink.log" \
      "$SCRIPT_DIR/go.sum"

echo "Done. Remaining files:"
ls "$SCRIPT_DIR"
