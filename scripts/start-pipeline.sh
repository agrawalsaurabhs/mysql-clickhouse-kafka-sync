#!/bin/bash

# One-Click CDC Pipeline Starter
# This script starts the entire CDC pipeline and opens itermocil layout

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a  # automatically export all variables
    source "$PROJECT_DIR/.env"
    set +a  # stop automatically exporting
fi

echo "🚀 Starting CDC Pipeline Setup..."
echo ""

# Check if itermocil is installed
if ! command -v itermocil &> /dev/null; then
    echo "❌ itermocil is not installed"
    echo "Install with: gem install itermocil"
    exit 1
fi

# Check if MySQL is accessible and properly set up
echo "📊 Checking MySQL setup..."
if ! mysql -u debezium -pdebezium_password -e "SELECT 1" > /dev/null 2>&1; then
    echo "❌ MySQL is not properly configured for CDC"
    echo "🚀 Running MySQL setup..."
    "$SCRIPT_DIR/mysql.sh" setup
    echo "✅ MySQL setup completed"
else
    echo "✅ MySQL is ready"
fi

# Ensure MySQL database is initialized
echo "📊 Checking MySQL setup..."
mysql -u debezium -pdebezium_password -e "CREATE DATABASE IF NOT EXISTS inventory;" 2>/dev/null
mysql -u debezium -pdebezium_password -e "USE inventory; SHOW TABLES;" > /dev/null 2>&1 || {
    echo "📝 Initializing MySQL database..."
    mysql -u root -p < "$PROJECT_DIR/mysql/init.sql"
}
echo "✅ MySQL ready"

# Ensure ClickHouse database is initialized
echo "📊 Checking ClickHouse setup..."
if clickhouse client --query "SELECT 1" > /dev/null 2>&1; then
    clickhouse client --query "CREATE DATABASE IF NOT EXISTS mysql_sync;" 2>/dev/null || true
    if [ -f "$PROJECT_DIR/clickhouse/init.sql" ]; then
        clickhouse client < "$PROJECT_DIR/clickhouse/init.sql" 2>/dev/null || true
    fi
    echo "✅ ClickHouse ready"
else
    echo "⚠️  ClickHouse not running, will be started by itermocil"
fi

# Make scripts executable
echo "🔧 Setting up scripts..."
chmod +x "$PROJECT_DIR"/scripts/*.sh

# Check if Kafka data directory exists
if [ ! -d "$PROJECT_DIR/kafka-data" ]; then
    mkdir -p "$PROJECT_DIR/kafka-data/kafka-logs"
fi

echo ""
echo "✅ Pre-flight checks complete!"
echo ""

# Validate critical services can start
echo "🔍 Validating services..."

# Check if Kafka can start
if ! "$SCRIPT_DIR/kafka.sh" status > /dev/null 2>&1; then
    echo "⚠️  Starting Kafka for validation..."
    "$SCRIPT_DIR/kafka.sh" start
    if ! "$SCRIPT_DIR/kafka.sh" status > /dev/null 2>&1; then
        echo "❌ Kafka failed to start. Check configuration."
        exit 1
    fi
fi
echo "✅ Kafka is ready"

# Check if ClickHouse can start (but don't require it to be running)
if command -v clickhouse &> /dev/null; then
    echo "✅ ClickHouse is available"
else
    echo "⚠️  ClickHouse not found - will be started in pipeline"
fi

# Validate MySQL connectivity one more time
if ! mysql -u debezium -pdebezium_password -e "SELECT 1" > /dev/null 2>&1; then
    echo "❌ MySQL connectivity failed after setup"
    exit 1
fi
echo "✅ MySQL connectivity verified"

echo ""
echo "🎬 Launching CDC Pipeline in iTerm2..."
echo ""
echo "The pipeline will start in this order:"
echo "  1. Kafka (KRaft mode)"
echo "  2. ClickHouse Server"
echo "  3. Debezium Kafka Connect"
echo "  4. Sink Connector"
echo "  5. Data Generator (inserts records every 5s)"
echo "  6. Pipeline Monitor"
echo ""
echo "📊 You can also access:"
echo "  • Redpanda Console: http://localhost:9090"
echo "  • Kafka Connect API: http://localhost:8083"
echo "  • ClickHouse HTTP: http://localhost:8123"
echo ""

sleep 2

# Copy itermocil config to the correct location
mkdir -p ~/.itermocil
cp "$PROJECT_DIR/cdc-pipeline.yml" ~/.itermocil/

# Ensure iTerm2 is running and activated
echo "📱 Activating iTerm2..."
osascript -e 'tell application "iTerm2" to activate'
sleep 2

# Launch itermocil
itermocil cdc-pipeline

echo ""
echo "✅ CDC Pipeline layout launched!"
echo "Check your iTerm2 window for the pipeline components."
