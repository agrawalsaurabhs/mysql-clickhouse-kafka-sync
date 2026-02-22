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
ZOOKEEPER_HOST="${ZOOKEEPER_HOST:-localhost}"
ZOOKEEPER_PORT="${ZOOKEEPER_PORT:-2181}"

# Executable paths with fallbacks
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-$HOMEBREW_PREFIX}"

KAFKA_VERSION="2.13-3.7.0"
KAFKA_HOME="$PROJECT_DIR/kafka_$KAFKA_VERSION"
KAFKA_CONFIG="$PROJECT_DIR/kafka-config/server.properties"
ZK_CONFIG="$KAFKA_HOME/config/zookeeper.properties"
KAFKA_DATA_DIR="$PROJECT_DIR/kafka-data"
KAFKA_URL="https://archive.apache.org/dist/kafka/3.7.0/kafka_2.13-3.7.0.tgz"

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

function download_kafka() {
    echo "⬇️ Downloading Kafka $KAFKA_VERSION..."
    
    local temp_dir="/tmp/kafka_download"
    mkdir -p "$temp_dir"
    
    if [ ! -f "$temp_dir/kafka.tgz" ]; then
        echo "📥 Downloading from Apache mirror..."
        curl -L "$KAFKA_URL" -o "$temp_dir/kafka.tgz"
    fi
    
    echo "📦 Extracting Kafka..."
    tar -xzf "$temp_dir/kafka.tgz" -C "$PROJECT_DIR"
    
    echo "✅ Kafka downloaded and extracted to $KAFKA_HOME"
}

function install_kafka() {
    echo "📦 Installing Kafka..."
    
    if [ -d "$KAFKA_HOME" ]; then
        echo "✅ Kafka is already installed at $KAFKA_HOME"
        return 0
    fi
    
    check_dependencies
    download_kafka
    
    # Make scripts executable
    chmod +x "$KAFKA_HOME/bin/"*.sh
    
    echo "✅ Kafka installation completed"
}

function setup_kafka_dirs() {
    echo "📂 Setting up Kafka directories..."
    
    mkdir -p "$KAFKA_DATA_DIR/kafka-logs"
    mkdir -p "/tmp/zookeeper"
    
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
    if pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null; then
        echo "   ✅ Zookeeper running (PID: $(pgrep -f 'QuorumPeerMain.*zookeeper'))"
    else
        echo "   ❌ Zookeeper not running"
    fi
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "   ✅ Kafka running (PID: $(pgrep -f 'kafka.Kafka.*server.properties'))"
    else
        echo "   ❌ Kafka not running"
    fi
    
    echo ""
    echo "💡 Recommended Actions:"
    if [ ! -d "$KAFKA_HOME" ]; then
        echo "   → Run: $0 setup"
    elif ! pgrep -f "QuorumPeerMain.*zookeeper" > /dev/null || ! pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "   → Run: $0 start"
    else
        echo "   → Everything looks good! Try: $0 test"
    fi
}

function reset_kafka() {
    echo "🔄 Resetting Kafka cluster..."
    
    # Stop services
    stop_kafka
    stop_zookeeper
    
    # Clean up all data
    echo "🗑️ Cleaning up Kafka data..."
    rm -rf "$KAFKA_DATA_DIR/kafka-logs"
    rm -rf /tmp/zookeeper
    rm -rf "$KAFKA_DATA_DIR"/*.log
    
    # Recreate directories
    setup_kafka_dirs
    
    echo "✅ Kafka cluster reset complete"
    echo "💡 Run './scripts/kafka.sh start' to start fresh"
}

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
    
    # Clean up any stale broker registration in ZooKeeper
    echo "🧹 Cleaning up stale broker data..."
    rm -rf /tmp/zookeeper/version-2/log.* 2>/dev/null || true
    rm -rf "$PROJECT_DIR/kafka-data/kafka-logs/meta.properties" 2>/dev/null || true
    
    echo "🚀 Starting Kafka server..."
    cd "$KAFKA_HOME"
    ./bin/kafka-server-start.sh "$KAFKA_CONFIG" > "$PROJECT_DIR/kafka-data/kafka.log" 2>&1 &
    
    # Wait longer for Kafka to fully start
    sleep 10
    
    if pgrep -f "kafka.Kafka.*server.properties" > /dev/null; then
        echo "✅ Kafka started successfully"
        echo "   - Broker: localhost:9092"
        echo "   - JMX: localhost:9999"
        
        # Test broker connectivity
        sleep 2
        if timeout 10 "$KAFKA_HOME/bin/kafka-broker-api-versions.sh" --bootstrap-server localhost:9092 > /dev/null 2>&1; then
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
        cd "$KAFKA_HOME"
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
        echo "Usage: $0 {setup|install|diagnose|reset|start|stop|restart|status|topics|create-topics|test|logs|full}"
        echo ""
        echo "Setup Commands:"
        echo "  setup         - Complete Kafka setup (install, configure)"
        echo "  install       - Install Kafka locally"
        echo "  diagnose      - Run diagnostic checks"
        echo "  reset         - Reset Kafka cluster (clean all data)"
        echo ""
        echo "Service Commands:"
        echo "  start         - Start Zookeeper and Kafka"
        echo "  stop          - Stop Kafka and Zookeeper"
        echo "  restart       - Restart both services"
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