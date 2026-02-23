#!/bin/bash
# Stops Kafka Connect and removes all auto-generated files,
# leaving only install.sh, cleanup.sh and mysql-connector.json.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Debezium Cleanup ==="

# Delete connector via REST API (best-effort)
if curl -sf http://localhost:8083/ &>/dev/null; then
    echo "Deleting connector..."
    curl -sf -X DELETE http://localhost:8083/connectors/mysql-inventory-connector || true
fi

# Stop Kafka Connect
if [ -f "$SCRIPT_DIR/debezium.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/debezium.pid")
    if kill "$PID" 2>/dev/null; then
        echo "Kafka Connect stopped (PID $PID)."
    else
        echo "Process $PID already gone."
    fi
    rm -f "$SCRIPT_DIR/debezium.pid"
elif pgrep -f "connect-distributed" &>/dev/null; then
    pkill -f "connect-distributed" && echo "Kafka Connect stopped."
else
    echo "Kafka Connect is not running."
fi

# Remove generated and downloaded files
rm -f  "$SCRIPT_DIR/connect-distributed.properties" \
       "$SCRIPT_DIR/debezium.log"
rm -rf "$SCRIPT_DIR/plugins" \
       "$SCRIPT_DIR/debezium-connector-mysql"

echo "Done. Remaining files:"
ls "$SCRIPT_DIR"
