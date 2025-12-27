#!/bin/bash

# ClickHouse Management Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLICKHOUSE_CONFIG="$PROJECT_DIR/clickhouse-config/config.xml"
CLICKHOUSE_DATA="$PROJECT_DIR/clickhouse-data"
PID_FILE="$CLICKHOUSE_DATA/clickhouse.pid"

function start_clickhouse() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "ClickHouse is already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi
    
    echo "Starting ClickHouse server..."
    clickhouse server --config-file="$CLICKHOUSE_CONFIG" --daemon --pid-file="$PID_FILE"
    sleep 2
    
    if clickhouse client --query "SELECT 1" > /dev/null 2>&1; then
        echo "✅ ClickHouse started successfully"
        echo "   - Native protocol: 127.0.0.1:9000"
        echo "   - HTTP interface:  127.0.0.1:8123"
    else
        echo "❌ ClickHouse failed to start"
        return 1
    fi
}

function stop_clickhouse() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping ClickHouse (PID: $pid)..."
            kill "$pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force killing ClickHouse..."
                kill -9 "$pid"
            fi
            rm -f "$PID_FILE"
            echo "✅ ClickHouse stopped"
        else
            echo "ClickHouse is not running"
            rm -f "$PID_FILE"
        fi
    else
        echo "ClickHouse is not running"
    fi
}

function status_clickhouse() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "✅ ClickHouse is running (PID: $(cat "$PID_FILE"))"
        clickhouse client --query "SELECT version()" | sed 's/^/   Version: /'
    else
        echo "❌ ClickHouse is not running"
        return 1
    fi
}

case "$1" in
    start)
        start_clickhouse
        ;;
    stop)
        stop_clickhouse
        ;;
    restart)
        stop_clickhouse
        sleep 1
        start_clickhouse
        ;;
    status)
        status_clickhouse
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac