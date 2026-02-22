#!/bin/bash

# Pipeline Monitor - Shows real-time stats for all components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  CDC Pipeline Monitor - MySQL → Debezium → Kafka → ClickHouse"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
}

function check_component_status() {
    local component=$1
    local check_command=$2
    
    if eval "$check_command > /dev/null 2>&1"; then
        echo -e "${GREEN}✅${NC} $component: Running"
        return 0
    else
        echo -e "${RED}❌${NC} $component: Not Running"
        return 1
    fi
}

function get_mysql_stats() {
    local count=$(mysql -u debezium -pdebezium_password -N -e "SELECT COUNT(*) FROM inventory.customers;" 2>/dev/null || echo "0")
    local prod_count=$(mysql -u debezium -pdebezium_password -N -e "SELECT COUNT(*) FROM inventory.products;" 2>/dev/null || echo "0")
    echo -e "   Customers: ${BLUE}$count${NC} | Products: ${BLUE}$prod_count${NC}"
}

function get_kafka_topics() {
    local topics=$("$PROJECT_DIR/kafka_2.13-3.7.0/bin/kafka-topics.sh" --bootstrap-server localhost:9092 --list 2>/dev/null | grep -E "inventory" || echo "none")
    echo -e "   Topics: ${BLUE}$topics${NC}"
}

function get_clickhouse_stats() {
    local cust_count=$(clickhouse client -q "SELECT COUNT(*) FROM mysql_sync.customers" 2>/dev/null || echo "0")
    local prod_count=$(clickhouse client -q "SELECT COUNT(*) FROM mysql_sync.products" 2>/dev/null || echo "0")
    echo -e "   Customers: ${BLUE}$cust_count${NC} | Products: ${BLUE}$prod_count${NC}"
}

function get_connector_status() {
    local status=$(curl -s http://localhost:8083/connectors/mysql-inventory-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
    if [ "$status" = "RUNNING" ]; then
        echo -e "   Status: ${GREEN}$status${NC}"
    else
        echo -e "   Status: ${RED}$status${NC}"
    fi
    
    # Get tasks status
    local tasks=$(curl -s http://localhost:8083/connectors/mysql-inventory-connector/status 2>/dev/null | jq -r '.tasks[].state' 2>/dev/null)
    if [ ! -z "$tasks" ]; then
        echo -e "   Tasks: ${BLUE}$tasks${NC}"
    fi
}

function show_recent_events() {
    echo ""
    echo "📊 Recent MySQL Changes (Last 5):"
    mysql -u debezium -pdebezium_password -t -e "
    USE inventory;
    SELECT 
        'Customer' as type,
        id,
        CONCAT(first_name, ' ', last_name) as name,
        updated_at
    FROM customers
    ORDER BY updated_at DESC
    LIMIT 5;
    " 2>/dev/null || echo "   Unable to fetch MySQL data"
    
    echo ""
    echo "📊 ClickHouse Sync Status (Last 5):"
    clickhouse client -q "
    SELECT 
        'Customer' as type,
        id,
        concat(first_name, ' ', last_name) as name,
        updated_at
    FROM mysql_sync.customers
    ORDER BY updated_at DESC
    LIMIT 5
    FORMAT PrettyCompact
    " 2>/dev/null || echo "   No data synced yet"
}

# Main monitoring loop
clear
print_header

echo "Initializing monitors..."
sleep 2

while true; do
    clear
    print_header
    
    echo "🔧 Component Status:"
    echo "────────────────────────────────────────────────────────────────"
    check_component_status "MySQL" "mysql -u debezium -pdebezium_password -e 'SELECT 1'"
    get_mysql_stats
    echo ""
    
    check_component_status "Kafka" "pgrep -f 'kafka.Kafka.*server.properties'"
    get_kafka_topics
    echo ""
    
    check_component_status "ClickHouse" "clickhouse client --query 'SELECT 1'"
    get_clickhouse_stats
    echo ""
    
    check_component_status "Kafka Connect" "curl -s http://localhost:8083"
    get_connector_status
    echo ""
    
    check_component_status "Sink Connector" "pgrep -f 'mysql-clickhouse-sink'"
    echo ""
    
    check_component_status "Redpanda Console" "curl -s http://localhost:9090"
    echo -e "   URL: ${BLUE}http://localhost:9090${NC}"
    echo ""
    
    show_recent_events
    
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S') | Refreshing in 5s..."
    echo "Press Ctrl+C to exit"
    
    sleep 5
done
