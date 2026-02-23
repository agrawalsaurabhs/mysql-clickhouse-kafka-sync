#!/bin/bash
# Sink Connector Setup Script
# Builds the binary (if missing) and starts the connector process.
# Requires ClickHouse and Kafka to already be running.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="$SCRIPT_DIR/mysql-clickhouse-sink"

echo "=== Sink Connector Setup ==="

# -----------------------------------------
# 1. Check Go is available
# -----------------------------------------
if ! command -v go &> /dev/null; then
    echo "ERROR: Go is not installed. Install it from https://go.dev/dl/"
    exit 1
fi
echo "Go $(go version | awk '{print $3}') found."

# -----------------------------------------
# 2. Build binary if not present
# -----------------------------------------
if [ ! -f "$BINARY" ]; then
    echo "Building sink connector..."
    cd "$SCRIPT_DIR"
    go mod tidy
    go build -o mysql-clickhouse-sink .
    echo "Build complete."
else
    echo "Binary already present. Skipping build."
fi

# -----------------------------------------
# 3. Start connector (skip if already running)
# -----------------------------------------
if [ -f "$SCRIPT_DIR/sink.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/sink.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Sink connector is already running (PID $PID)."
        exit 0
    else
        rm -f "$SCRIPT_DIR/sink.pid"
    fi
fi

echo "Starting sink connector..."
cd "$SCRIPT_DIR"
nohup "$BINARY" > "$SCRIPT_DIR/sink.log" 2>&1 &
echo $! > "$SCRIPT_DIR/sink.pid"

echo "Sink connector started (PID $(cat "$SCRIPT_DIR/sink.pid"))."
echo ""
echo "=== Setup Complete ==="
echo "  Config : $SCRIPT_DIR/config.hjson"
echo "  Logs   : $SCRIPT_DIR/sink.log"
echo "  PID    : $SCRIPT_DIR/sink.pid"
