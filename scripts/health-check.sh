#!/bin/bash

# Complete CDC Pipeline Health Check
# Validates all components are properly set up and running

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🏥 CDC Pipeline Health Check"
echo "============================"
echo ""

function check_component() {
    local component=$1
    local script=$2
    local test_command=$3
    
    echo "🔍 Checking $component..."
    
    if "$SCRIPT_DIR/$script" $test_command > /dev/null 2>&1; then
        echo "   ✅ $component: OK"
        return 0
    else
        echo "   ❌ $component: FAILED"
        echo "   💡 Run: ./scripts/$script diagnose"
        return 1
    fi
}

# Track overall health
overall_health=0

# Check all components
check_component "MySQL" "mysql.sh" "test" || overall_health=1
check_component "Kafka" "kafka.sh" "status" || overall_health=1
check_component "ClickHouse" "clickhouse.sh" "status" || overall_health=1
check_component "Debezium" "debezium.sh" "status" || overall_health=1
check_component "Sink Connector" "sink.sh" "status" || overall_health=1

echo ""

if [ $overall_health -eq 0 ]; then
    echo "✅ All components are healthy!"
    echo ""
    echo "🚀 Pipeline is ready for:"
    echo "   • Real-time CDC from MySQL to ClickHouse"
    echo "   • Data generation and testing"
    echo "   • Production workloads"
    echo ""
    echo "📊 Quick tests:"
    echo "   ./scripts/mysql.sh changes     # Generate test data"
    echo "   ./scripts/sink.sh test-clickhouse  # Verify sync"
    echo "   ./scripts/start-pipeline.sh    # Launch full monitoring"
else
    echo "❌ Some components need attention"
    echo ""
    echo "🔧 Run diagnostics for failed components:"
    echo "   ./scripts/mysql.sh diagnose"
    echo "   ./scripts/kafka.sh diagnose"
    echo "   ./scripts/clickhouse.sh diagnose"
    echo "   ./scripts/debezium.sh diagnose"
    echo "   ./scripts/sink.sh diagnose"
    echo ""
    echo "🏗️ Or run complete setup:"
    echo "   ./scripts/setup-all.sh"
fi

echo ""
echo "📚 Documentation: README.md"
echo "🎛️ Monitoring: ./scripts/start-pipeline.sh"