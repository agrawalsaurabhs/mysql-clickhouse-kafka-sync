#!/bin/bash

# Debezium Kafka Connect Management Script - Self-sufficient setup
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
KAFKA_HOST="${KAFKA_HOST:-localhost}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
DEBEZIUM_REST_PORT="${DEBEZIUM_REST_PORT:-8083}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-debezium}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-debezium_password}"

# Use Homebrew Kafka installation
KAFKA_LIBEXEC="${KAFKA_LIBEXEC:-$(brew --prefix kafka)/libexec}"
CONNECT_CONFIG="$PROJECT_DIR/debezium/connect-distributed.properties"
CONNECTOR_CONFIG="$PROJECT_DIR/debezium/mysql-connector.json"
CONNECT_LOG="$PROJECT_DIR/kafka-data/connect.log"
DEBEZIUM_VERSION="2.4.0.Final"
DEBEZIUM_CONNECTOR_DIR="$PROJECT_DIR/debezium/debezium-connector-mysql"
DEBEZIUM_URL="https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/$DEBEZIUM_VERSION/debezium-connector-mysql-$DEBEZIUM_VERSION-plugin.tar.gz"
function check_dependencies() {
    echo "🔍 Checking Debezium dependencies..."
    
    if [ ! -d "$KAFKA_LIBEXEC" ]; then
        echo "❌ Kafka not found at $KAFKA_LIBEXEC"
        echo "💡 Install Kafka: brew install kafka"
        exit 1
    fi
    
    echo "✅ Kafka installation found"
}

function download_debezium() {
    echo "⬇️ Downloading Debezium MySQL connector..."
    
    local temp_dir="/tmp/debezium_download"
    mkdir -p "$temp_dir"
    
    if [ ! -f "$temp_dir/debezium-connector.tar.gz" ]; then
        echo "📥 Downloading Debezium connector $DEBEZIUM_VERSION..."
        curl -L "$DEBEZIUM_URL" -o "$temp_dir/debezium-connector.tar.gz"
    fi
    
    echo "📦 Extracting Debezium connector..."
    rm -rf "$DEBEZIUM_CONNECTOR_DIR"
    mkdir -p "$PROJECT_DIR/debezium"
    tar -xzf "$temp_dir/debezium-connector.tar.gz" -C "$PROJECT_DIR/debezium/"
    
    # The extracted folder might have a different name, let's find it and rename
    local extracted_dir=$(find "$PROJECT_DIR/debezium" -name "debezium-connector-mysql*" -type d | head -1)
    if [ "$extracted_dir" != "$DEBEZIUM_CONNECTOR_DIR" ]; then
        mv "$extracted_dir" "$DEBEZIUM_CONNECTOR_DIR"
    fi
    
    echo "✅ Debezium connector downloaded and extracted"
}

function install_debezium() {
    echo "📦 Installing Debezium MySQL connector..."
    
    if [ -d "$DEBEZIUM_CONNECTOR_DIR" ]; then
        echo "✅ Debezium connector is already installed at $DEBEZIUM_CONNECTOR_DIR"
        return 0
    fi
    
    check_dependencies
    download_debezium
    
    echo "✅ Debezium connector installation completed"
}

function setup_debezium() {
    echo "🏗️ Setting up Debezium for CDC pipeline..."
    echo ""
    
    check_dependencies
    install_debezium
    
    echo ""
    echo "✅ Debezium setup completed successfully!"
    echo ""
    echo "📊 Installation Details:"
    echo "   Connector Path: $DEBEZIUM_CONNECTOR_DIR"
    echo "   Config File: $CONNECT_CONFIG"
    echo "   Connector Config: $CONNECTOR_CONFIG"
    echo ""
}

function diagnose_debezium() {
    echo "🔍 Debezium Setup Diagnostics"
    echo "============================="
    echo ""
    
    echo "📋 Installation Status:"
    if [ -d "$KAFKA_LIBEXEC" ]; then
        echo "   ✅ Kafka found at: $KAFKA_LIBEXEC"
    else
        echo "   ❌ Kafka not found"
    fi
    
    if [ -d "$DEBEZIUM_CONNECTOR_DIR" ]; then
        echo "   ✅ Debezium connector installed at: $DEBEZIUM_CONNECTOR_DIR"
    else
        echo "   ❌ Debezium connector not installed"
    fi
    
    if [ -f "$CONNECT_CONFIG" ]; then
        echo "   ✅ Connect config exists: $CONNECT_CONFIG"
    else
        echo "   ❌ Connect config missing"
    fi
    
    echo ""
    echo "📋 Service Status:"
    if pgrep -f "ConnectDistributed.*connect-distributed.properties" > /dev/null; then
        echo "   ✅ Kafka Connect running (PID: $(pgrep -f 'ConnectDistributed.*connect-distributed.properties'))"
    else
        echo "   ❌ Kafka Connect not running"
    fi
    
    echo ""
    echo "📋 API Status:"
    if curl -s http://localhost:8083/ > /dev/null 2>&1; then
        echo "   ✅ Connect API accessible at http://localhost:8083"
    else
        echo "   ❌ Connect API not accessible"
    fi
    
    echo ""
    echo "💡 Recommended Actions:"
    if [ ! -d "$DEBEZIUM_CONNECTOR_DIR" ]; then
        echo "   → Run: $0 setup"
    elif ! pgrep -f "ConnectDistributed.*connect-distributed.properties" > /dev/null; then
        echo "   → Run: $0 start"
    else
        echo "   → Everything looks good! Try: $0 connector-status"
    fi
}
function start_kafka_connect() {
    if pgrep -f "ConnectDistributed.*connect-distributed.properties" > /dev/null; then
        echo "✅ Kafka Connect is already running (PID: $(pgrep -f 'ConnectDistributed.*connect-distributed.properties'))"
        return 0
    fi
    
    # Check if Kafka is running
    if ! pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "❌ Kafka is not running. Please start Kafka first:"
        echo "   ~/Desktop/samples/rds-ch-sync/scripts/kafka.sh start"
        return 1
    fi
    
    echo "🚀 Starting Kafka Connect..."
    cd "$KAFKA_LIBEXEC"
    
    # Set CLASSPATH to include Debezium connector
    export CLASSPATH="$PROJECT_DIR/debezium/debezium-connector-mysql/*:$CLASSPATH"
    
    ./bin/connect-distributed.sh "$CONNECT_CONFIG" > "$CONNECT_LOG" 2>&1 &
    
    echo "⏳ Waiting for Kafka Connect to start..."
    sleep 10
    
    # Check if Connect REST API is available
    for i in {1..30}; do
        if curl -s http://localhost:8083/ > /dev/null 2>&1; then
            echo "✅ Kafka Connect started successfully"
            echo "   - REST API: http://localhost:8083"
            return 0
        fi
        sleep 2
        echo "   Attempt $i/30..."
    done
    
    echo "❌ Kafka Connect failed to start"
    echo "Check logs: $CONNECT_LOG"
    return 1
}

function stop_kafka_connect() {
    if pgrep -f "ConnectDistributed.*connect-distributed.properties" > /dev/null; then
        echo "🛑 Stopping Kafka Connect..."
        local pid=$(pgrep -f "ConnectDistributed.*connect-distributed.properties")
        kill "$pid"
        sleep 3
        if kill -0 "$pid" 2>/dev/null; then
            echo "Force killing Kafka Connect..."
            kill -9 "$pid"
        fi
        echo "✅ Kafka Connect stopped"
    else
        echo "ℹ️  Kafka Connect is not running"
    fi
}

function status_kafka_connect() {
    echo "📊 Kafka Connect Status:"
    
    if pgrep -f "ConnectDistributed.*connect-distributed.properties" > /dev/null; then
        echo "✅ Kafka Connect: Running (PID: $(pgrep -f 'ConnectDistributed.*connect-distributed.properties'))"
        
        if curl -s http://localhost:8083/ > /dev/null 2>&1; then
            echo "✅ REST API: Available at http://localhost:8083"
            
            # Get connector plugins
            echo "📦 Available Connector Plugins:"
            curl -s http://localhost:8083/connector-plugins | jq -r '.[] | "   - " + .class' 2>/dev/null || echo "   (Unable to fetch plugins)"
            
            # List active connectors
            echo "🔗 Active Connectors:"
            local connectors=$(curl -s http://localhost:8083/connectors 2>/dev/null)
            if [[ "$connectors" == "[]" ]]; then
                echo "   No connectors running"
            else
                echo "$connectors" | jq -r '.[]' 2>/dev/null | sed 's/^/   - /' || echo "   $connectors"
            fi
        else
            echo "❌ REST API: Not responding"
        fi
    else
        echo "❌ Kafka Connect: Not running"
    fi
}

function create_mysql_connector() {
    if ! curl -s http://localhost:8083/ > /dev/null 2>&1; then
        echo "❌ Kafka Connect is not running or not responding"
        return 1
    fi
    
    echo "🏗️  Creating MySQL inventory connector..."
    
    # Generate connector configuration with current environment variables
    echo "📝 Generating connector configuration..."
    "$SCRIPT_DIR/generate-connector-config.sh"
    
    # Check if connector already exists
    if curl -s http://localhost:8083/connectors/mysql-inventory-connector > /dev/null 2>&1; then
        echo "✅ Connector already exists. Checking status..."
        show_connector_status
        return 0
    fi
    
    # Create the connector
    local response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d @"$CONNECTOR_CONFIG" \
        http://localhost:8083/connectors)
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" == "201" ]]; then
        echo "✅ MySQL connector created successfully"
        show_connector_status
    else
        echo "❌ Failed to create connector (HTTP $http_code)"
        echo "$response_body" | jq . 2>/dev/null || echo "$response_body"
        return 1
    fi
}

function delete_mysql_connector() {
    echo "🗑️  Deleting MySQL inventory connector..."
    
    local response=$(curl -s -w "%{http_code}" -X DELETE \
        http://localhost:8083/connectors/mysql-inventory-connector)
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "204" ]]; then
        echo "✅ MySQL connector deleted successfully"
    else
        echo "❌ Failed to delete connector (HTTP $http_code)"
        return 1
    fi
}

function show_connector_status() {
    if ! curl -s http://localhost:8083/ > /dev/null 2>&1; then
        echo "❌ Kafka Connect is not running"
        return 1
    fi
    
    echo "📊 MySQL Connector Status:"
    
    local status=$(curl -s http://localhost:8083/connectors/mysql-inventory-connector/status 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$status" | jq . || echo "$status"
    else
        echo "❌ Connector not found or error occurred"
    fi
}

function restart_mysql_connector() {
    echo "🔄 Restarting MySQL connector..."
    
    local response=$(curl -s -w "%{http_code}" -X POST \
        http://localhost:8083/connectors/mysql-inventory-connector/restart)
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "204" ]]; then
        echo "✅ MySQL connector restarted successfully"
        sleep 3
        show_connector_status
    else
        echo "❌ Failed to restart connector (HTTP $http_code)"
        return 1
    fi
}

function show_topics_with_data() {
    echo "📋 CDC Topics with Recent Data:"
    
    local topics=("mysql.inventory" "mysql.inventory.customers" "mysql.inventory.products")
    
    for topic in "${topics[@]}"; do
        echo "--- Topic: $topic ---"
        timeout 3 "$KAFKA_LIBEXEC/bin/kafka-console-consumer.sh" \
            --topic "$topic" \
            --bootstrap-server localhost:9092 \
            --from-beginning \
            --max-messages 1 \
            2>/dev/null || echo "No messages found"
        echo ""
    done
}

function test_cdc_pipeline() {
    echo "🧪 Testing CDC Pipeline..."
    
    if ! curl -s http://localhost:8083/connectors/mysql-inventory-connector/status > /dev/null 2>&1; then
        echo "❌ MySQL connector is not running"
        return 1
    fi
    
    echo "🔄 Making test changes to MySQL..."
    mysql -u debezium -pdebezium_password -e "
    USE inventory;
    INSERT INTO customers (first_name, last_name, email) 
    VALUES ('CDC', 'Test', 'cdc.test@example.com');
    
    UPDATE products SET weight = 2.7 WHERE name = 'Laptop Computer';
    " || { echo "❌ Failed to execute MySQL changes"; return 1; }
    
    echo "✅ MySQL changes applied"
    echo "⏳ Waiting for CDC events (5 seconds)..."
    sleep 5
    
    echo "📥 Recent CDC events:"
    show_topics_with_data
}

function show_logs() {
    echo "📝 Recent Kafka Connect logs:"
    if [[ -f "$CONNECT_LOG" ]]; then
        tail -30 "$CONNECT_LOG"
    else
        echo "No log file found at $CONNECT_LOG"
    fi
}

case "$1" in
    setup)
        setup_debezium
        ;;
    install)
        install_debezium
        ;;
    diagnose)
        diagnose_debezium
        ;;
    start)
        start_kafka_connect
        ;;
    stop)
        stop_kafka_connect
        ;;
    restart)
        stop_kafka_connect
        sleep 2
        start_kafka_connect
        ;;
    status)
        status_kafka_connect
        ;;
    create-connector)
        create_mysql_connector
        ;;
    delete-connector)
        delete_mysql_connector
        ;;
    connector-status)
        show_connector_status
        ;;
    restart-connector)
        restart_mysql_connector
        ;;
    test)
        test_cdc_pipeline
        ;;
    topics)
        show_topics_with_data
        ;;
    logs)
        show_logs
        ;;
    full)
        status_kafka_connect
        echo ""
        show_connector_status
        ;;
    *)
        echo "Usage: $0 {setup|install|diagnose|start|stop|restart|status|create-connector|delete-connector|connector-status|restart-connector|test|topics|logs|full}"
        echo ""
        echo "Setup Commands:"
        echo "  setup             - Complete Debezium setup (install, configure)"
        echo "  install           - Install Debezium MySQL connector"
        echo "  diagnose          - Run diagnostic checks"
        echo ""
        echo "Service Commands:"
        echo "  start             - Start Kafka Connect"
        echo "  stop              - Stop Kafka Connect"
        echo "  restart           - Restart Kafka Connect"
        echo ""
        echo "Connector Commands:"
        echo "  create-connector  - Create MySQL connector"
        echo "  delete-connector  - Delete MySQL connector"
        echo "  connector-status  - Show connector status"
        echo "  restart-connector - Restart MySQL connector"
        echo ""
        echo "Testing Commands:"
        echo "  status            - Show Kafka Connect status"
        echo "  test              - Test CDC pipeline with sample changes"
        echo "  topics            - Show recent CDC data in topics"
        echo "  logs              - Show Kafka Connect logs"
        echo "  full              - Show complete status"
        echo ""
        echo "🚀 For first-time setup, run: $0 setup"
        exit 1
        ;;
esac