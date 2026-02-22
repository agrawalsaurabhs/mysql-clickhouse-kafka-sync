#!/bin/bash

# Kafka Management Script for MySQL-ClickHouse CDC Pipeline - Self-sufficient setup
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
KAFKA_CONTROLLER_PORT="${KAFKA_CONTROLLER_PORT:-9093}"

# Executable paths with fallbacks
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
BREW_BIN="${BREW_BIN:-brew}"

# Kafka paths (Homebrew installation)
KAFKA_HOME="$HOMEBREW_PREFIX/opt/kafka"
KAFKA_LIBEXEC="$HOMEBREW_PREFIX/opt/kafka/libexec"
KAFKA_CONFIG="$PROJECT_DIR/kafka-config/server.properties"
KAFKA_DATA_DIR="$PROJECT_DIR/kafka-data"
KAFKA_CLUSTER_ID="${KAFKA_CLUSTER_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-22)}"

function check_dependencies() {
    echo "🔍 Checking Kafka dependencies..."
    
    # Check Java
    if ! command -v java &> /dev/null; then
        echo "📦 Installing Java..."
        brew install openjdk@17
        echo 'export PATH="$HOMEBREW_PREFIX/opt/openjdk@17/bin:$PATH"' >> ~/.zprofile
        export PATH="$HOMEBREW_PREFIX/opt/openjdk@17/bin:$PATH"
    fi
    
    echo "✅ Java is available: $(java -version 2>&1 | head -1)"
}

function install_kafka() {
    echo "📦 Installing Kafka via Homebrew..."
    
    # Check if Kafka is already installed
    if $BREW_BIN list kafka &> /dev/null; then
        echo "✅ Kafka is already installed via Homebrew"
        echo "   Location: $KAFKA_HOME"
        return 0
    fi
    
    # Install Kafka using Homebrew
    echo "📥 Installing Kafka and dependencies..."
    $BREW_BIN install kafka
    
    echo "✅ Kafka installation completed via Homebrew"
    echo "   Kafka Home: $KAFKA_HOME"
    echo "   Kafka Libexec: $KAFKA_LIBEXEC"
}

function setup_kafka_dirs() {
    echo "📂 Setting up Kafka directories..."
    
    mkdir -p "$KAFKA_DATA_DIR/kafka-logs"
    
    # Initialize KRaft cluster metadata if not exists
    if [ ! -f "$KAFKA_DATA_DIR/kafka-logs/meta.properties" ]; then
        echo "🔧 Initializing KRaft cluster metadata..."
        cd "$KAFKA_LIBEXEC"
        KAFKA_CLUSTER_ID="$(bin/kafka-storage.sh random-uuid)"
        bin/kafka-storage.sh format -t "$KAFKA_CLUSTER_ID" -c "$KAFKA_CONFIG"
        echo "✅ KRaft cluster initialized with ID: $KAFKA_CLUSTER_ID"
    fi
    
    echo "✅ Kafka directories ready"
}

function setup_kafka() {
    echo "🏗️ Setting up Kafka for CDC pipeline..."
    echo ""
    
    check_dependencies
    install_kafka
    setup_kafka_dirs
    
    echo ""
    echo "✅ Kafka setup completed successfully!"
    echo ""
    echo "📊 Installation Details:"
    echo "   Kafka Home: $KAFKA_HOME"
    echo "   Data Directory: $KAFKA_DATA_DIR"
    echo "   Config File: $KAFKA_CONFIG"
    echo ""
}

function diagnose_kafka() {
    echo "🔍 Kafka Setup Diagnostics"
    echo "=========================="
    echo ""
    
    echo "📋 Installation Status:"
    if [ -d "$KAFKA_HOME" ]; then
        echo "   ✅ Kafka installed at: $KAFKA_HOME"
    else
        echo "   ❌ Kafka not installed"
    fi
    
    if command -v java &> /dev/null; then
        echo "   ✅ Java available: $(java -version 2>&1 | head -1)"
    else
        echo "   ❌ Java not installed"
    fi
    
    echo ""
    echo "📋 Service Status:"
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "   ✅ Kafka (KRaft mode) running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
    else
        echo "   ❌ Kafka not running"
    fi
    
    echo ""
    echo "💡 Recommended Actions:"
    if [ ! -d "$KAFKA_HOME" ]; then
        echo "   → Run: $0 setup"
    elif ! pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "   → Run: $0 start"
    else
        echo "   → Everything looks good! Try: $0 test"
    fi
}

function reset_kafka() {
    echo "🔄 Resetting Kafka cluster..."
    
    # Stop services
    stop_kafka
    
    # Clean up all data
    echo "🗑️ Cleaning up Kafka data..."
    rm -rf "$KAFKA_DATA_DIR/kafka-logs"
    rm -rf "$KAFKA_DATA_DIR"/*.log
    
    # Recreate directories and reinitialize
    setup_kafka_dirs
    
    echo "✅ Kafka cluster reset complete"
    echo "💡 Run './scripts/kafka.sh start' to start fresh"
}



function start_kafka() {
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka is already running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
        return 0
    fi
    
    # Ensure KRaft metadata is initialized
    if [ ! -f "$KAFKA_DATA_DIR/kafka-logs/meta.properties" ]; then
        echo "🔧 Initializing KRaft cluster metadata..."
        setup_kafka_dirs
    fi
    
    echo "🚀 Starting Kafka server in KRaft mode..."
    cd "$KAFKA_LIBEXEC"
    export JAVA_HOME="${JAVA_HOME:-$HOMEBREW_PREFIX/opt/openjdk@17}"
    ./bin/kafka-server-start.sh "$KAFKA_CONFIG" > "$PROJECT_DIR/kafka-data/kafka.log" 2>&1 &
    
    # Wait longer for Kafka to fully start
    sleep 10
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka started successfully"
        echo "   - Broker: localhost:9092"
        echo "   - JMX: localhost:9999"
        
        # Test broker connectivity
        sleep 2
        if timeout 10 "$KAFKA_LIBEXEC/bin/kafka-broker-api-versions.sh" --bootstrap-server localhost:9092 > /dev/null 2>&1; then
            echo "✅ Kafka broker is accessible"
        else
            echo "⚠️  Kafka broker may not be fully ready yet"
        fi
    else
        echo "❌ Failed to start Kafka"
        echo "📋 Check logs: tail -f $PROJECT_DIR/kafka-data/kafka.log"
        return 1
    fi
}

function stop_kafka() {
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "🛑 Stopping Kafka server..."
        cd "$KAFKA_LIBEXEC"
        ./bin/kafka-server-stop.sh
        
        # Wait for graceful shutdown
        local attempts=0
        while pgrep -f "kafka.Kafka.*server.properties" > /dev/null && [ $attempts -lt 10 ]; do
            sleep 2
            attempts=$((attempts + 1))
        done
        
        # Force kill if still running
        if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
            echo "🔥 Force stopping Kafka..."
            pkill -f "kafka.Kafka.*server.properties"
            sleep 2
        fi
        
        echo "✅ Kafka stopped"
    else
        echo "ℹ️  Kafka is not running"
    fi
}

function status_kafka() {
    echo "📊 Kafka Status (KRaft Mode):"
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka: Running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
        
        # Test broker connectivity
        if timeout 5 "$KAFKA_LIBEXEC/bin/kafka-broker-api-versions.sh" --bootstrap-server localhost:9092 > /dev/null 2>&1; then
            echo "✅ Kafka broker: Accessible on localhost:9092"
        else
            echo "⚠️  Kafka broker: Not responding"
        fi
        
        # Show KRaft metadata status
        if [ -f "$KAFKA_DATA_DIR/kafka-logs/meta.properties" ]; then
            echo "✅ KRaft metadata: Initialized"
            # Show cluster ID
            if command -v grep &> /dev/null; then
                CLUSTER_ID=$(grep "cluster.id" "$KAFKA_DATA_DIR/kafka-logs/meta.properties" 2>/dev/null | cut -d'=' -f2)
                if [ -n "$CLUSTER_ID" ]; then
                    echo "   Cluster ID: $CLUSTER_ID"
                fi
            fi
        else
            echo "⚠️  KRaft metadata: Not initialized"
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
    "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --create --topic mysql.inventory.customers --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
    "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --create --topic mysql.inventory.products --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --if-not-exists
    
    # Create Debezium schema changes topic
    "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --create --topic mysql.inventory --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists
    
    echo "✅ CDC topics created successfully"
    list_topics
}

function list_topics() {
    echo "📋 Available Kafka topics:"
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --list --bootstrap-server localhost:9092
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
    "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --create --topic test-topic --bootstrap-server localhost:9092 --partitions 1 --replication-factor 1 --if-not-exists > /dev/null 2>&1
    
    # Send test message
    echo "Hello from Kafka CDC setup!" | "$KAFKA_LIBEXEC/bin/kafka-console-producer.sh" --topic test-topic --bootstrap-server localhost:9092
    
    # Read test message
    echo "📥 Reading test message:"
    timeout 3 "$KAFKA_LIBEXEC/bin/kafka-console-consumer.sh" --topic test-topic --from-beginning --bootstrap-server localhost:9092 --max-messages 1 2>/dev/null || echo "Test message confirmed"
    
    # Clean up test topic
    "$KAFKA_LIBEXEC/bin/kafka-topics.sh" --delete --topic test-topic --bootstrap-server localhost:9092 > /dev/null 2>&1
    
    echo "✅ Kafka test successful"
}

function show_logs() {
    echo "📝 Recent Kafka logs:"
    if [[ -f "$PROJECT_DIR/kafka-data/kafka.log" ]]; then
        echo "--- Kafka Server Log (last 30 lines) ---"
        tail -30 "$PROJECT_DIR/kafka-data/kafka.log"
    else
        echo "❌ No Kafka logs found at $PROJECT_DIR/kafka-data/kafka.log"
    fi
}

case "$1" in
    setup)
        setup_kafka
        ;;
    install)
        install_kafka
        ;;
    diagnose)
        diagnose_kafka
        ;;
    reset)
        reset_kafka
        ;;
    start)
        start_kafka
        ;;
    stop)
        stop_kafka
        ;;
    restart)
        stop_kafka
        sleep 2
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
        echo "Usage: $0 {setup|install|diagnose|reset|start|stop|restart|status|topics|create-topics|test|logs|full}"
        echo ""
        echo "Setup Commands:"
        echo "  setup         - Complete Kafka setup (install, configure)"
        echo "  install       - Install Kafka locally"
        echo "  diagnose      - Run diagnostic checks"
        echo "  reset         - Reset Kafka cluster (clean all data)"
        echo ""
        echo "Service Commands:"
        echo "  start         - Start Kafka in KRaft mode"
        echo "  stop          - Stop Kafka"
        echo "  restart       - Restart Kafka"
        echo ""
        echo "Management Commands:"
        echo "  status        - Show service status"
        echo "  topics        - List all Kafka topics"
        echo "  create-topics - Create CDC topics for MySQL sync"
        echo "  test          - Test Kafka with sample message"
        echo "  logs          - Show recent logs"
        echo "  full          - Show status and topics"
        echo ""
        echo "🚀 For first-time setup, run: $0 setup"
        exit 1
        ;;
esac