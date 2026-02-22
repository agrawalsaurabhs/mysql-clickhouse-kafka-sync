#!/bin/bash

# Debezium Kafka Connect Management Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KAFKA_HOME="/Users/saurabhagrawal/software/kafka_2.13-3.7.0"
CONNECT_CONFIG="$PROJECT_DIR/debezium/connect-distributed.properties"
CONNECTOR_CONFIG="$PROJECT_DIR/debezium/mysql-connector.json"
CONNECT_LOG="$PROJECT_DIR/kafka-data/connect.log"

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
    cd "$KAFKA_HOME"
    
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
        timeout 3 "$KAFKA_HOME/bin/kafka-console-consumer.sh" \
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
        echo "Usage: $0 {start|stop|restart|status|create-connector|delete-connector|connector-status|restart-connector|test|topics|logs|full}"
        echo ""
        echo "Commands:"
        echo "  start             - Start Kafka Connect"
        echo "  stop              - Stop Kafka Connect"
        echo "  restart           - Restart Kafka Connect"
        echo "  status            - Show Kafka Connect status"
        echo "  create-connector  - Create MySQL connector"
        echo "  delete-connector  - Delete MySQL connector"
        echo "  connector-status  - Show connector status"
        echo "  restart-connector - Restart MySQL connector"
        echo "  test              - Test CDC pipeline with sample changes"
        echo "  topics            - Show recent CDC data in topics"
        echo "  logs              - Show Kafka Connect logs"
        echo "  full              - Show complete status"
        exit 1
        ;;
esac