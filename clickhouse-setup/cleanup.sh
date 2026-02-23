#!/bin/bash
# Stops the ClickHouse server and removes the binary and all auto-generated files,
# leaving only install.sh and cleanup.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== ClickHouse Cleanup ==="

# Stop server if running
if [ -f "$SCRIPT_DIR/clickhouse.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/clickhouse.pid")
    if kill "$PID" 2>/dev/null; then
        echo "Server stopped (PID $PID)."
    else
        echo "Process $PID already gone."
    fi
    rm -f "$SCRIPT_DIR/clickhouse.pid"
else
    echo "No PID file — server not running (or started externally)."
fi

# Remove binary and all auto-generated runtime files
rm -f  "$SCRIPT_DIR/clickhouse" \
       "$SCRIPT_DIR/server.log" \
       "$SCRIPT_DIR/uuid" \
       "$SCRIPT_DIR/status" \
       "$SCRIPT_DIR/config.xml"

rm -rf "$SCRIPT_DIR/data" \
       "$SCRIPT_DIR/store" \
       "$SCRIPT_DIR/metadata" \
       "$SCRIPT_DIR/metadata_dropped" \
       "$SCRIPT_DIR/preprocessed_configs" \
       "$SCRIPT_DIR/format_schemas" \
       "$SCRIPT_DIR/access" \
       "$SCRIPT_DIR/flags" \
       "$SCRIPT_DIR/tmp" \
       "$SCRIPT_DIR/user_files"

echo "Done. Remaining files:"
ls "$SCRIPT_DIR"
