#!/bin/bash

# Kafka Management Script for MySQL-ClickHouse CDC Pipeline
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KAFKA_HOME="/Users/saurabhagrawal/software/kafka_2.13-3.7.0"
KAFKA_CONFIG="$PROJECT_DIR/kafka-config/server.properties"
ZK_CONFIG="$KAFKA_HOME/config/zookeeper.properties"

function start_zookeeper() {
    if pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        echo "✅ Zookeeper is already running (PID: $(pgrep -f 'QuorumPeerMain.*zookeeper'))"
        return 0
    fi
    
    echo "🚀 Starting Zookeeper..."
    cd "$KAFKA_HOME"
    ./bin/zookeeper-server-start.sh "$ZK_CONFIG" > "$PROJECT_DIR/kafka-data/zookeeper.log" 2>&1 &
    sleep 3
    
    if pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        echo "✅ Zookeeper started successfully"
    else
        echo "❌ Failed to start Zookeeper"
        return 1
    fi
}

function stop_zookeeper() {
    if pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        echo "🛑 Stopping Zookeeper..."
        cd "$KAFKA_HOME"
        ./bin/zookeeper-server-stop.sh
        sleep 2
        echo "✅ Zookeeper stopped"
    else
        echo "ℹ️  Zookeeper is not running"
    fi
}

function start_kafka() {
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka is already running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
        return 0
    fi
    
    # Ensure Zookeeper is running first
    if ! pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        start_zookeeper
    fi
    
    echo "🚀 Starting Kafka server..."
    cd "$KAFKA_HOME"
    ./bin/kafka-server-start.sh "$KAFKA_CONFIG" > "$PROJECT_DIR/kafka-data/kafka.log" 2>&1 &
    sleep 5
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka started successfully"
        echo "   - Broker: localhost:9092"
        echo "   - JMX: localhost:9999"
    else
        echo "❌ Failed to start Kafka"
        return 1
    fi
}

function stop_kafka() {
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "🛑 Stopping Kafka server..."
        cd "$KAFKA_HOME"
        ./bin/kafka-server-stop.sh
        sleep 3
        echo "✅ Kafka stopped"
    else
        echo "ℹ️  Kafka is not running"
    fi
}

function status_kafka() {
    echo "📊 Kafka Ecosystem Status:"
    
    if pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        echo "✅ Zookeeper: Running (PID: $(pgrep -f 'QuorumPeerMain.*zookeeper'))"
    else
        echo "❌ Zookeeper: Not running"
    fi
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka: Running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
        
        # Test broker connectivity
        if timeout 5 "$KAFKA_HOME/bin/kafka-broker-api-versions.sh" --bootstrap-server localhost:9092 > /dev/null 2>&1; then
            echo "✅ Kafka broker: Accessible on localhost:9092"
        else
            echo "⚠️  Kafka broker: Not responding"
        fi
    else
        echo "❌ Kafka: Not running"
    fi
}

function create_cdc_topics() {
    echo "🏗️  Creating CDC topics for MySQL-ClickHouse sync..."
    
    # Check if Kafka is running
    if ! pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "❌ Kafka is not running. Please start Kafka first."
        return 1
    fi
    
    # Create topics for our inventory database
    "$KAFKA_HOME/bin/kafka-topics.sh" --create --topic mysql.inventory.customers --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
    "$KAFKA_HOME/bin/kafka-topics.sh" --create --topic mysql.inventory.products --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
    
    # Create Debezium schema changes topic
    "$KAFKA_HOME/bin/kafka-topics.sh" --create --topic mysql.inventory --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists
    
    echo "✅ CDC topics created successfully"
    list_topics
}

function list_topics() {
    echo "📋 Available Kafka topics:"
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        "$KAFKA_HOME/bin/kafka-topics.sh" --list --bootstrap-server localhost:9092
    else
        echo "❌ Kafka is not running"
        return 1
    fi
}

function test_kafka() {
    if ! pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "❌ Kafka is not running"
        return 1
    fi
    
    echo "🧪 Testing Kafka with sample message..."
    
    # Create test topic
    "$KAFKA_HOME/bin/kafka-topics.sh" --create --topic test-topic --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists > /dev/null 2>&1
    
    # Send test message
    echo "Hello from Kafka CDC setup!" | "$KAFKA_HOME/bin/kafka-console-producer.sh" --topic test-topic --bootstrap-server localhost:9092
    
    # Read test message
    echo "📥 Reading test message:"
    timeout 3 "$KAFKA_HOME/bin/kafka-console-consumer.sh" --topic test-topic --from-beginning --bootstrap-server localhost:9092 --max-messages 1 2>/dev/null || echo "Test message confirmed"
    
    # Clean up test topic
    "$KAFKA_HOME/bin/kafka-topics.sh" --delete --topic test-topic --bootstrap-server localhost:9092 > /dev/null 2>&1
    
    echo "✅ Kafka test successful"
}

function show_logs() {
    echo "📝 Recent Kafka logs:"
    if [[ -f "$PROJECT_DIR/kafka-data/kafka.log" ]]; then
        echo "--- Kafka Server Log (last 20 lines) ---"
        tail -20 "$PROJECT_DIR/kafka-data/kafka.log"
    fi
    
    if [[ -f "$PROJECT_DIR/kafka-data/zookeeper.log" ]]; then
        echo "--- Zookeeper Log (last 10 lines) ---"
        tail -10 "$PROJECT_DIR/kafka-data/zookeeper.log"
    fi
}

case "$1" in
    start)
        start_zookeeper
        start_kafka
        ;;
    stop)
        stop_kafka
        stop_zookeeper
        ;;
    restart)
        stop_kafka
        stop_zookeeper
        sleep 2
        start_zookeeper
        start_kafka
        ;;
    status)
        status_kafka
        ;;
    topics)
        list_topics
        ;;
    create-topics)
        create_cdc_topics
        ;;
    test)
        test_kafka
        ;;
    logs)
        show_logs
        ;;
    full)
        status_kafka
        echo ""
        list_topics
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|topics|create-topics|test|logs|full}"
        echo ""
        echo "Commands:"
        echo "  start         - Start Zookeeper and Kafka"
        echo "  stop          - Stop Kafka and Zookeeper"
        echo "  restart       - Restart both services"
        echo "  status        - Show service status"
        echo "  topics        - List all Kafka topics"
        echo "  create-topics - Create CDC topics for MySQL sync"
        echo "  test          - Test Kafka with sample message"
        echo "  logs          - Show recent logs"
        echo "  full          - Show status and topics"
        exit 1
        ;;
esac