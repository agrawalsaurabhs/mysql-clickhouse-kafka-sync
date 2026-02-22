#!/bin/bash

# MySQL Management and Testing Script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

function test_mysql_connection() {
    echo "Testing MySQL connection..."
    if mysql -u debezium -pdebezium_password -e "SELECT 'MySQL Connection OK' as status;" > /dev/null 2>&1; then
        echo "✅ MySQL connection successful"
        mysql -u debezium -pdebezium_password -e "SELECT VERSION() as mysql_version;"
    else
        echo "❌ MySQL connection failed"
        return 1
    fi
}

function check_cdc_config() {
    echo "Checking MySQL CDC configuration..."
    
    echo "📊 Binary Logging Status:"
    mysql -u debezium -pdebezium_password -e "SHOW VARIABLES LIKE 'log_bin';"
    
    echo "📊 Binary Log Format:"
    mysql -u debezium -pdebezium_password -e "SHOW VARIABLES LIKE 'binlog_format';"
    
    echo "📊 Binary Log Row Image:"
    mysql -u debezium -pdebezium_password -e "SHOW VARIABLES LIKE 'binlog_row_image';"
    
    echo "📊 Master Status:"
    mysql -u debezium -pdebezium_password -e "SHOW MASTER STATUS;"
    
    echo "📊 Debezium User Privileges:"
    mysql -u debezium -pdebezium_password -e "SHOW GRANTS FOR 'debezium'@'localhost';" 2>/dev/null || echo "Debezium user not found"
}

function show_sample_data() {
    echo "📋 Sample Data Overview:"
    mysql -u debezium -pdebezium_password -e "
    USE inventory;
    SELECT 'Customers Count:' as info, COUNT(*) as count FROM customers
    UNION ALL
    SELECT 'Products Count:' as info, COUNT(*) as count FROM products;
    "
    
    echo "📋 Recent Customers:"
    mysql -u debezium -pdebezium_password -e "USE inventory; SELECT * FROM customers LIMIT 3;"
    
    echo "📋 Recent Products:"
    mysql -u debezium -pdebezium_password -e "USE inventory; SELECT * FROM products LIMIT 3;"
}

function simulate_changes() {
    echo "🔄 Simulating database changes for CDC testing..."
    
    mysql -u debezium -pdebezium_password -e "
    USE inventory;
    
    -- Insert a new customer
    INSERT INTO customers (first_name, last_name, email) 
    VALUES ('Test', 'User', 'test.user@example.com');
    
    -- Update a customer
    UPDATE customers SET first_name = 'Johnny' WHERE first_name = 'John';
    
    -- Insert a new product
    INSERT INTO products (name, description, weight) 
    VALUES ('Test Product', 'A test product for CDC', 1.0);
    
    -- Update a product
    UPDATE products SET weight = 2.6 WHERE name = 'Laptop Computer';
    
    SELECT 'Changes applied successfully' as result;
    "
    
    echo "✅ Test changes applied"
    show_sample_data
}

function reset_sample_data() {
    echo "🔄 Resetting sample data..."
    mysql < "$PROJECT_DIR/mysql/init.sql" > /dev/null
    echo "✅ Sample data reset"
}

case "$1" in
    test)
        test_mysql_connection
        ;;
    status)
        test_mysql_connection
        check_cdc_config
        ;;
    data)
        show_sample_data
        ;;
    changes)
        simulate_changes
        ;;
    reset)
        reset_sample_data
        ;;
    full)
        test_mysql_connection
        check_cdc_config
        show_sample_data
        ;;
    *)
        echo "Usage: $0 {test|status|data|changes|reset|full}"
        echo ""
        echo "Commands:"
        echo "  test     - Test MySQL connection"
        echo "  status   - Show CDC configuration status"
        echo "  data     - Show current sample data"
        echo "  changes  - Simulate database changes for testing"
        echo "  reset    - Reset sample data to initial state"
        echo "  full     - Run all status checks"
        exit 1
        ;;
esac