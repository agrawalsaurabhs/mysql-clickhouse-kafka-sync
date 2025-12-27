#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SINK_DIR="$SCRIPT_DIR/../sink-connector"

function start_sink() {
    echo "Starting MySQL to ClickHouse sink connector..."
    cd "$SINK_DIR"
    if [ ! -f "main.go" ]; then
        echo "Error: main.go not found in $SINK_DIR"
        return 1
    fi
    
    # Build and run the sink connector
    go build -o mysql-clickhouse-sink main.go
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build sink connector"
        return 1
    fi
    
    echo "Built sink connector successfully"
    echo "Running sink connector..."
    ./mysql-clickhouse-sink
}

function stop_sink() {
    echo "Stopping sink connector..."
    pkill -f "mysql-clickhouse-sink"
    echo "Sink connector stopped"
}

function status_sink() {
    echo "Checking sink connector status..."
    if pgrep -f "mysql-clickhouse-sink" > /dev/null; then
        echo "✅ Sink connector is running"
        echo "Process info:"
        ps aux | grep "mysql-clickhouse-sink" | grep -v grep
    else
        echo "❌ Sink connector is not running"
    fi
}

function build_sink() {
    echo "Building sink connector..."
    cd "$SINK_DIR"
    go build -o mysql-clickhouse-sink main.go
    if [ $? -eq 0 ]; then
        echo "✅ Sink connector built successfully"
    else
        echo "❌ Failed to build sink connector"
        return 1
    fi
}

function clean_sink() {
    echo "Cleaning sink connector..."
    cd "$SINK_DIR"
    rm -f mysql-clickhouse-sink
    echo "✅ Cleaned build artifacts"
}

function logs_sink() {
    echo "Showing sink connector logs..."
    if pgrep -f "mysql-clickhouse-sink" > /dev/null; then
        echo "Sink connector is running. Press Ctrl+C to stop viewing logs."
        tail -f "$SINK_DIR/sink.log" 2>/dev/null || echo "No log file found. Running in console mode."
    else
        echo "❌ Sink connector is not running"
    fi
}

function test_clickhouse() {
    echo "Testing ClickHouse connection and checking tables..."
    
    # Check if ClickHouse is running
    if ! curl -s http://127.0.0.1:8123/ping > /dev/null; then
        echo "❌ ClickHouse is not running"
        return 1
    fi
    
    echo "✅ ClickHouse is running"
    
    # Check tables
    echo "Checking ClickHouse tables:"
    echo "SHOW TABLES" | curl -s 'http://127.0.0.1:8123/' --data-binary @-
    
    echo ""
    echo "Sample queries:"
    echo "SELECT count() FROM customers" | curl -s 'http://127.0.0.1:8123/' --data-binary @-
    echo " customers"
    echo "SELECT count() FROM products" | curl -s 'http://127.0.0.1:8123/' --data-binary @-
    echo " products"
    echo "SELECT count() FROM orders" | curl -s 'http://127.0.0.1:8123/' --data-binary @-
    echo " orders"
}

function show_help() {
    echo "MySQL to ClickHouse Sink Connector Management"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start              Start the sink connector"
    echo "  stop               Stop the sink connector"
    echo "  restart            Restart the sink connector"
    echo "  status             Check connector status"
    echo "  build              Build the connector binary"
    echo "  clean              Clean build artifacts"
    echo "  logs               View connector logs"
    echo "  test-clickhouse    Test ClickHouse connection and show table stats"
    echo "  help               Show this help message"
    echo ""
}

# Main command handling
case "$1" in
    "start")
        start_sink
        ;;
    "stop")
        stop_sink
        ;;
    "restart")
        stop_sink
        sleep 2
        start_sink
        ;;
    "status")
        status_sink
        ;;
    "build")
        build_sink
        ;;
    "clean")
        clean_sink
        ;;
    "logs")
        logs_sink
        ;;
    "test-clickhouse")
        test_clickhouse
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    "")
        echo "No command specified"
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac