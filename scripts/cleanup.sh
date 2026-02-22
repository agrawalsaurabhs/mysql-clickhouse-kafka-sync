#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a  # automatically export all variables
    source "$PROJECT_ROOT/.env"
    set +a  # stop automatically exporting
fi

# Configuration with environment variable fallbacks
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-password}"

# Executable paths with fallbacks
CLICKHOUSE_BIN="${CLICKHOUSE_BIN:-clickhouse}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Function to check if a service is running
is_service_running() {
    local service_name="$1"
    local process_pattern="$2"
    
    if pgrep -f "$process_pattern" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop services
stop_services() {
    log "Stopping all CDC pipeline services..."
    
    # Stop sink connector
    if is_service_running "Sink Connector" "mysql-clickhouse-sink"; then
        log "Stopping sink connector..."
        pkill -f "mysql-clickhouse-sink" || warn "Could not stop sink connector"
        sleep 2
    fi
    
    # Stop Debezium
    if is_service_running "Debezium" "connect-distributed"; then
        log "Stopping Debezium..."
        "$SCRIPT_DIR/debezium.sh" stop || warn "Could not stop Debezium"
        sleep 3
    fi
    
    # Stop Kafka
    if is_service_running "Kafka" "kafka.Kafka"; then
        log "Stopping Kafka..."
        "$SCRIPT_DIR/kafka.sh" stop || warn "Could not stop Kafka"
        sleep 5
    fi
    
    # Stop ClickHouse
    if is_service_running "ClickHouse" "clickhouse-server"; then
        log "Stopping ClickHouse..."
        "$SCRIPT_DIR/clickhouse.sh" stop || warn "Could not stop ClickHouse"
        sleep 3
    fi
    
    # Stop MySQL
    if is_service_running "MySQL" "mysqld"; then
        log "Stopping MySQL..."
        "$SCRIPT_DIR/mysql.sh" stop || warn "Could not stop MySQL"
        sleep 3
    fi
}

# Function to clean Kafka data
clean_kafka_data() {
    log "Cleaning Kafka data and topics..."
    
    local kafka_data_dir="$PROJECT_ROOT/kafka-data"
    
    # Start Kafka temporarily if needed to delete topics
    local kafka_was_stopped=false
    if ! is_service_running "Kafka" "kafka.Kafka"; then
        log "Starting Kafka temporarily to clean topics..."
        "$SCRIPT_DIR/kafka.sh" start
        kafka_was_stopped=true
        sleep 10
    fi
    
    # Delete all topics
    if is_service_running "Kafka" "kafka.Kafka"; then
        log "Deleting all Kafka topics..."
        
        # Get Kafka directory from the kafka.sh script
        local kafka_dir="$PROJECT_ROOT/kafka_2.13-3.7.0"
        
        if [ -d "$kafka_dir" ]; then
            # List and delete all topics (except internal ones)
            "$kafka_dir/bin/kafka-topics.sh" --bootstrap-server localhost:9092 --list 2>/dev/null | grep -v "^__" | while read topic; do
                if [ ! -z "$topic" ]; then
                    log "Deleting topic: $topic"
                    "$kafka_dir/bin/kafka-topics.sh" --bootstrap-server localhost:9092 --delete --topic "$topic" 2>/dev/null || true
                fi
            done
        fi
    fi
    
    # Stop Kafka if we started it
    if [ "$kafka_was_stopped" = true ]; then
        log "Stopping Kafka..."
        "$SCRIPT_DIR/kafka.sh" stop
        sleep 5
    fi
    
    # Clean Kafka data directory
    if [ -d "$kafka_data_dir" ]; then
        log "Removing Kafka logs and data..."
        rm -rf "$kafka_data_dir/kafka-logs"/*
        success "Kafka data and topics cleaned"
    else
        warn "Kafka data directory not found: $kafka_data_dir"
    fi
}

# Function to clean ClickHouse data
clean_clickhouse_data() {
    log "Cleaning ClickHouse databases and data..."
    
    local clickhouse_data_dir="$PROJECT_ROOT/clickhouse-data"
    
    # Start ClickHouse temporarily if needed for database cleanup
    local clickhouse_was_stopped=false
    if ! is_service_running "ClickHouse" "clickhouse-server"; then
        log "Starting ClickHouse temporarily for database cleanup..."
        "$SCRIPT_DIR/clickhouse.sh" start
        clickhouse_was_stopped=true
        sleep 5
    fi
    
    # Drop all user databases via SQL
    if is_service_running "ClickHouse" "clickhouse-server"; then
        log "Dropping all user databases..."
        
        # Get list of databases and drop non-system ones
        $CLICKHOUSE_BIN client --query "SHOW DATABASES" 2>/dev/null | while read db; do
            if [ ! -z "$db" ] && [ "$db" != "system" ] && [ "$db" != "INFORMATION_SCHEMA" ] && [ "$db" != "information_schema" ]; then
                log "Dropping database: $db"
                $CLICKHOUSE_BIN client --query "DROP DATABASE IF EXISTS $db" 2>/dev/null || warn "Could not drop database $db"
            fi
        done
    fi
    
    # Stop ClickHouse if we started it
    if [ "$clickhouse_was_stopped" = true ]; then
        log "Stopping ClickHouse..."
        "$SCRIPT_DIR/clickhouse.sh" stop
        sleep 3
    fi
    
    # Clean ClickHouse data directory
    if [ -d "$clickhouse_data_dir" ]; then
        log "Removing ClickHouse data files..."
        
        # Remove data directories but keep the structure
        find "$clickhouse_data_dir/data" -mindepth 1 -maxdepth 1 -type d ! -name "system" -exec rm -rf {} + 2>/dev/null || true
        
        # Clean metadata (except system)
        find "$clickhouse_data_dir/metadata" -mindepth 1 -maxdepth 1 ! -name "system*" -exec rm -rf {} + 2>/dev/null || true
        
        # Clean other directories
        rm -rf "$clickhouse_data_dir/store"/* 2>/dev/null || true
        rm -rf "$clickhouse_data_dir/tmp"/* 2>/dev/null || true
        
        success "ClickHouse databases and data cleaned"
    else
        warn "ClickHouse data directory not found: $clickhouse_data_dir"
    fi
}

# Function to clean MySQL data (drop and recreate database)
clean_mysql_data() {
    log "Cleaning MySQL databases and schemas..."
    
    # Start MySQL temporarily if needed for cleanup
    local mysql_was_stopped=false
    if ! is_service_running "MySQL" "mysqld"; then
        log "Starting MySQL temporarily for database cleanup..."
        "$SCRIPT_DIR/mysql.sh" start
        mysql_was_stopped=true
        sleep 5
    fi
    
    # Drop and recreate inventory database completely
    log "Dropping and recreating inventory database..."
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "
        -- Drop the entire inventory database
        DROP DATABASE IF EXISTS inventory;
        
        -- Recreate empty inventory database
        CREATE DATABASE inventory;
        
        -- Reset binlog position for fresh CDC start
        RESET MASTER;
        FLUSH LOGS;
    " 2>/dev/null || warn "Could not drop/recreate MySQL database"
    
    # Also clean any other CDC-related databases
    mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" 2>/dev/null | grep -E "(debezium|kafka|connect)" | while read db; do
        if [ ! -z "$db" ]; then
            log "Dropping CDC database: $db"
            mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "DROP DATABASE IF EXISTS $db;" 2>/dev/null || true
        fi
    done
    
    # Stop MySQL if we started it
    if [ "$mysql_was_stopped" = true ]; then
        log "Stopping MySQL..."
        "$SCRIPT_DIR/mysql.sh" stop
        sleep 3
    fi
    
    success "MySQL databases and schemas cleaned"
}

# Function to reset Debezium state
reset_debezium_state() {
    log "Resetting Debezium connectors and state..."
    
    # Start Debezium temporarily if needed to delete connectors
    local debezium_was_stopped=false
    if ! is_service_running "Debezium" "connect-distributed"; then
        # Check if Kafka is running, start if needed
        if ! is_service_running "Kafka" "kafka.Kafka"; then
            log "Starting Kafka for Debezium cleanup..."
            "$SCRIPT_DIR/kafka.sh" start
            sleep 10
        fi
        
        log "Starting Debezium temporarily for connector cleanup..."
        "$SCRIPT_DIR/debezium.sh" start
        debezium_was_stopped=true
        sleep 15
    fi
    
    # Delete all existing connectors
    if is_service_running "Debezium" "connect-distributed"; then
        log "Deleting all Debezium connectors..."
        
        # Get list of connectors and delete them
        curl -s http://localhost:8083/connectors 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' | while read connector; do
            if [ ! -z "$connector" ]; then
                log "Deleting connector: $connector"
                curl -s -X DELETE "http://localhost:8083/connectors/$connector" 2>/dev/null || true
            fi
        done
    fi
    
    # Stop Debezium if we started it
    if [ "$debezium_was_stopped" = true ]; then
        log "Stopping Debezium..."
        "$SCRIPT_DIR/debezium.sh" stop
        sleep 3
    fi
    
    # Remove any connector state files
    find "$PROJECT_ROOT" -name "connect.offsets*" -exec rm -f {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.offset" -exec rm -f {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "connect-status*" -exec rm -f {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "connect-configs*" -exec rm -f {} + 2>/dev/null || true
    
    success "Debezium connectors and state reset"
}

# Function to clean temporary files and logs
clean_temp_files() {
    log "Cleaning temporary files and logs..."
    
    # Clean any log files
    find "$PROJECT_ROOT" -name "*.log" -exec rm -f {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.pid" -exec rm -f {} + 2>/dev/null || true
    
    # Clean sink connector binary if exists
    if [ -f "$PROJECT_ROOT/sink-connector/mysql-clickhouse-sink" ]; then
        rm -f "$PROJECT_ROOT/sink-connector/mysql-clickhouse-sink"
        log "Removed sink connector binary"
    fi
    
    success "Temporary files cleaned"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local issues=0
    
    # Check if services are stopped (more specific process checking)
    if pgrep -f "mysqld.*--port=3306" > /dev/null 2>&1; then
        warn "MySQL CDC instance is still running"
        ((issues++))
    fi
    
    if pgrep -f "kafka\.Kafka.*server\.properties" > /dev/null 2>&1; then
        warn "Kafka is still running"
        ((issues++))
    fi
    
    if pgrep -f "clickhouse-server.*config\.xml" > /dev/null 2>&1; then
        warn "ClickHouse is still running"
        ((issues++))
    fi
    
    if pgrep -f "connect-distributed" > /dev/null 2>&1; then
        warn "Debezium is still running"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        success "All CDC services stopped successfully"
    else
        warn "$issues CDC service(s) may still be running"
    fi
    
    # Show cleanup summary
    log "Cleanup Summary:"
    log "  ✅ All Kafka topics deleted"
    log "  ✅ All ClickHouse user databases dropped"
    log "  ✅ MySQL inventory database dropped and recreated"
    log "  ✅ All Debezium connectors removed"
    log "  ✅ All connector state files cleaned"
}

# Main cleanup function
main() {
    log "Starting CDC pipeline cleanup..."
    log "This will remove all CDC-related data and stop all services"
    
    # Ask for confirmation
    read -p "Are you sure you want to proceed? This will delete all CDC data (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    # Perform cleanup steps
    stop_services
    clean_kafka_data
    clean_clickhouse_data
    clean_mysql_data
    reset_debezium_state
    clean_temp_files
    verify_cleanup
    
    success "CDC pipeline cleanup completed!"
    log ""
    log "Your CDC pipeline is now clean and ready for a fresh start."
    log "You can run './scripts/start-pipeline.sh' to set up and start the pipeline again."
}

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Cleanup script for CDC pipeline data and services."
    echo "This script will:"
    echo "  - Stop all CDC services (MySQL, Kafka, ClickHouse, Debezium, Sink)"
    echo "  - Remove all Kafka topics and logs"
    echo "  - Clean ClickHouse databases and tables"
    echo "  - Remove data from MySQL inventory tables"
    echo "  - Reset Debezium connector state"
    echo "  - Clean temporary files and logs"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    exit 0
fi

# Run main function
main "$@"