#!/bin/bash

# ClickHouse Management Script - Self-sufficient setup
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a  # automatically export all variables
    source "$PROJECT_DIR/.env"
    set +a  # stop automatically exporting
fi

# Configuration with environment variable fallbacks
CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-127.0.0.1}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-9000}"
CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-default}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-}"

# Executable paths with fallbacks
CLICKHOUSE_BIN="${CLICKHOUSE_BIN:-clickhouse}"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

CLICKHOUSE_CONFIG="$PROJECT_DIR/clickhouse-config/config.xml"
CLICKHOUSE_DATA="$PROJECT_DIR/clickhouse-data"
PID_FILE="$CLICKHOUSE_DATA/clickhouse.pid"

function check_dependencies() {
    echo "🔍 Checking ClickHouse dependencies..."
    
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew is required but not installed"
        exit 1
    fi
    
    echo "✅ Homebrew is available"
}

function install_clickhouse() {
    echo "📦 Installing ClickHouse..."
    
    if command -v clickhouse &> /dev/null; then
        echo "✅ ClickHouse is already installed"
        clickhouse --version
        return 0
    fi
    
    echo "⬇️ Installing ClickHouse via Homebrew..."
    brew install clickhouse
    
    echo "✅ ClickHouse installed successfully"
    clickhouse --version
}

function setup_clickhouse_dirs() {
    echo "📂 Setting up ClickHouse directories..."
    
    mkdir -p "$CLICKHOUSE_DATA"
    mkdir -p "$CLICKHOUSE_DATA/data"
    mkdir -p "$CLICKHOUSE_DATA/logs"
    mkdir -p "$CLICKHOUSE_DATA/tmp"
    
    echo "✅ ClickHouse directories ready"
}

function initialize_database() {
    echo "🗄️ Initializing ClickHouse database..."
    
    # Wait for ClickHouse to be ready
    local attempts=0
    local max_attempts=30
    
    while ! clickhouse client --query "SELECT 1" > /dev/null 2>&1 && [ $attempts -lt $max_attempts ]; do
        sleep 2
        attempts=$((attempts + 1))
        echo "   Waiting for ClickHouse... ($attempts/$max_attempts)"
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo "❌ ClickHouse not responding"
        return 1
    fi
    
    # Create database and check if tables exist
    $CLICKHOUSE_BIN client --query "CREATE DATABASE IF NOT EXISTS mysql_sync"
    
    local table_count=$(clickhouse client --query "SELECT count() FROM system.tables WHERE database = 'mysql_sync'" 2>/dev/null)
    
    if [ "$table_count" -gt 0 ]; then
        echo "✅ Database already initialized with $table_count tables"
        return 0
    fi
    
    if [ -f "$PROJECT_DIR/clickhouse/init.sql" ]; then
        echo "📝 Running initialization script..."
        clickhouse client < "$PROJECT_DIR/clickhouse/init.sql"
        echo "✅ Database initialized with schema"
    else
        echo "⚠️  No init.sql found, database created without schema"
    fi
}

function setup_clickhouse() {
    echo "🏗️ Setting up ClickHouse for CDC pipeline..."
    echo ""
    
    check_dependencies
    install_clickhouse
    setup_clickhouse_dirs
    start_clickhouse
    initialize_database
    
    echo ""
    echo "✅ ClickHouse setup completed successfully!"
    echo ""
    echo "📊 Connection Details:"
    echo "   Native protocol: localhost:9000"
    echo "   HTTP interface:  localhost:8123"
    echo "   Data directory:  $CLICKHOUSE_DATA"
    echo "   Config file:     $CLICKHOUSE_CONFIG"
    echo ""
}

function diagnose_clickhouse() {
    echo "🔍 ClickHouse Setup Diagnostics"
    echo "=============================="
    echo ""
    
    echo "📋 Installation Status:"
    if command -v clickhouse &> /dev/null; then
        echo "   ✅ ClickHouse installed: $(clickhouse --version 2>/dev/null | head -1)"
    else
        echo "   ❌ ClickHouse not installed"
    fi
    
    if [ -d "$CLICKHOUSE_DATA" ]; then
        echo "   ✅ Data directory exists: $CLICKHOUSE_DATA"
    else
        echo "   ❌ Data directory missing"
    fi
    
    if [ -f "$CLICKHOUSE_CONFIG" ]; then
        echo "   ✅ Config file exists: $CLICKHOUSE_CONFIG"
    else
        echo "   ⚠️  Config file missing (will use defaults)"
    fi
    
    echo ""
    echo "📋 Service Status:"
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "   ✅ ClickHouse running (PID: $(cat "$PID_FILE"))"
    else
        echo "   ❌ ClickHouse not running"
    fi
    
    echo ""
    echo "📋 Connection Test:"
    if clickhouse client --query "SELECT 1" > /dev/null 2>&1; then
        echo "   ✅ Can connect to ClickHouse"
        echo "   📊 Version: $($CLICKHOUSE_BIN client --query "SELECT version()")"
    else
        echo "   ❌ Cannot connect to ClickHouse"
    fi
    
    echo ""
    echo "💡 Recommended Actions:"
    if ! command -v $CLICKHOUSE_BIN &> /dev/null; then
        echo "   → Run: $0 setup"
    elif ! [[ -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "   → Run: $0 start"
    else
        echo "   → Everything looks good! Try: $0 status"
    fi
}

function start_clickhouse() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "ClickHouse is already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi
    
    echo "Starting ClickHouse server..."
    $CLICKHOUSE_BIN server --config-file="$CLICKHOUSE_CONFIG" --daemon --pid-file="$PID_FILE"
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
        $CLICKHOUSE_BIN client --query "SELECT version()" | sed 's/^/   Version: /'
    else
        echo "❌ ClickHouse is not running"
        return 1
    fi
}

case "$1" in
    setup)
        setup_clickhouse
        ;;
    install)
        install_clickhouse
        ;;
    diagnose)
        diagnose_clickhouse
        ;;
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
        echo "Usage: $0 {setup|install|diagnose|start|stop|restart|status}"
        echo ""
        echo "Setup Commands:"
        echo "  setup    - Complete ClickHouse setup (install, configure, initialize)"
        echo "  install  - Install ClickHouse via Homebrew"
        echo "  diagnose - Run diagnostic checks"
        echo ""
        echo "Service Commands:"
        echo "  start    - Start ClickHouse server"
        echo "  stop     - Stop ClickHouse server"
        echo "  restart  - Restart ClickHouse server"
        echo "  status   - Show service status"
        echo ""
        echo "🚀 For first-time setup, run: $0 setup"
        exit 1
        ;;
esac