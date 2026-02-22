#!/bin/bash

# MySQL Management and Testing Script - Self-sufficient setup for macOS
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# MySQL configuration
MYSQL_USER="debezium"
MYSQL_PASSWORD="debezium_password"
MYSQL_ROOT_PASSWORD="password"
MYSQL_PORT="3306"
MYSQL_DATA_DIR="$PROJECT_DIR/mysql-data"
MYSQL_CONFIG_FILE="$PROJECT_DIR/mysql/my.cnf"

function check_dependencies() {
    echo "🔍 Checking required dependencies..."
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew is not installed. Please install Homebrew first:"
        echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    echo "✅ Homebrew is available"
}

function install_mysql() {
    echo "📦 Installing MySQL..."
    
    if command -v mysql &> /dev/null; then
        echo "✅ MySQL is already installed"
        mysql --version
        return 0
    fi
    
    echo "⬇️ Installing MySQL 8.0 via Homebrew..."
    brew install mysql
    
    echo "✅ MySQL installed successfully"
    mysql --version
}

function setup_mysql_config() {
    echo "⚙️ Setting up MySQL configuration..."
    
    # Create mysql directory if it doesn't exist
    mkdir -p "$PROJECT_DIR/mysql"
    
    # Our config is already in the right place
    echo "📝 Using CDC-optimized MySQL configuration from $MYSQL_CONFIG_FILE"
    
    echo "✅ MySQL configuration ready"
}

function start_mysql() {
    echo "🚀 Starting MySQL server..."
    
    # Check if MySQL is already running
    if mysqladmin ping -h localhost --silent &> /dev/null; then
        echo "✅ MySQL is already running"
        return 0
    fi
    
    # Try different Homebrew MySQL service names
    local mysql_services=("mysql" "mysql@8.0" "mysql@8.4")
    local started=false
    
    for service in "${mysql_services[@]}"; do
        if brew services start "$service" 2>/dev/null; then
            echo "🍺 Started MySQL via Homebrew services ($service)"
            started=true
            break
        fi
    done
    
    if [ "$started" = false ]; then
        echo "⚠️  Could not start MySQL via Homebrew services"
        echo "🔍 Available MySQL services:"
        brew services list | grep mysql || echo "   No MySQL services found"
        return 1
    fi
    
    # Wait for MySQL to be ready
    echo "⏳ Waiting for MySQL to be ready..."
    local attempts=0
    local max_attempts=30
    
    while ! mysqladmin ping -h localhost --silent &> /dev/null && [ $attempts -lt $max_attempts ]; do
        sleep 2
        attempts=$((attempts + 1))
        echo "   Attempt $attempts/$max_attempts..."
    done
    
    if [ $attempts -eq $max_attempts ]; then
        echo "❌ MySQL failed to start within 60 seconds"
        return 1
    fi
    
    echo "✅ MySQL server is running"
}

function stop_mysql() {
    echo "🛑 Stopping MySQL server..."
    
    # Try different Homebrew MySQL service names
    local mysql_services=("mysql" "mysql@8.0" "mysql@8.4")
    local stopped=false
    
    for service in "${mysql_services[@]}"; do
        if brew services stop "$service" 2>/dev/null; then
            echo "🍺 Stopped MySQL via Homebrew services ($service)"
            stopped=true
            break
        fi
    done
    
    if [ "$stopped" = false ]; then
        echo "⚠️  No active MySQL service found to stop"
    fi
    
    echo "✅ MySQL server stopped"
}

function secure_mysql_installation() {
    echo "🔐 Securing MySQL installation..."
    
    # Set root password and remove anonymous users
    mysql -u root -e "
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        FLUSH PRIVILEGES;
    " 2>/dev/null || echo "⚠️  Root password might already be set"
    
    echo "✅ MySQL installation secured"
}

function create_debezium_user() {
    echo "👤 Creating Debezium user..."
    
    # Try to connect with root password first
    local mysql_cmd="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
    
    # Check if debezium user already exists
    if $mysql_cmd -e "SELECT User FROM mysql.user WHERE User = '${MYSQL_USER}';" 2>/dev/null | grep -q "${MYSQL_USER}"; then
        echo "✅ Debezium user already exists"
        return 0
    fi
    
    # Create debezium user with required privileges for CDC
    $mysql_cmd -e "
        CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
        CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
        
        -- Grant required privileges for CDC
        GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${MYSQL_USER}'@'localhost';
        GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '${MYSQL_USER}'@'%';
        
        -- Grant database-specific privileges
        GRANT CREATE, INSERT, UPDATE, DELETE, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES ON inventory.* TO '${MYSQL_USER}'@'localhost';
        GRANT CREATE, INSERT, UPDATE, DELETE, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES ON inventory.* TO '${MYSQL_USER}'@'%';
        
        FLUSH PRIVILEGES;
    "
    
    echo "✅ Debezium user created with proper CDC privileges"
}

function initialize_database() {
    echo "🗄️ Initializing inventory database..."
    
    # Check if database already has tables
    local table_count=$(mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "USE inventory; SHOW TABLES;" 2>/dev/null | wc -l)
    
    if [ "$table_count" -gt 1 ]; then
        echo "✅ Database already initialized with $(($table_count - 1)) tables"
        return 0
    fi
    
    # Run the initialization script
    mysql -u root -p${MYSQL_ROOT_PASSWORD} < "$PROJECT_DIR/mysql/init.sql"
    
    echo "✅ Database and sample data created"
}

function setup_mysql() {
    echo "🏗️ Setting up MySQL for CDC pipeline..."
    echo ""
    
    check_dependencies
    install_mysql
    setup_mysql_config
    start_mysql
    secure_mysql_installation
    create_debezium_user
    initialize_database
    
    echo ""
    echo "✅ MySQL setup completed successfully!"
    echo ""
    echo "📊 Connection Details:"
    echo "   Host: localhost"
    echo "   Port: ${MYSQL_PORT}"
    echo "   Database: inventory"
    echo "   CDC User: ${MYSQL_USER}"
    echo "   Password: ${MYSQL_PASSWORD}"
    echo ""
    
    # Test the connection
    test_mysql_connection
}

function reinstall_mysql() {
    echo "🔄 Reinstalling MySQL (this will remove all data)..."
    read -p "Are you sure? This will delete all MySQL data! (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Reinstall cancelled"
        return 1
    fi
    
    echo "🛑 Stopping MySQL..."
    brew services stop mysql || true
    
    echo "🗑️ Removing MySQL..."
    brew uninstall mysql || true
    rm -rf $MYSQL_DATA_DIR || true
    
    echo "🔄 Reinstalling MySQL..."
    setup_mysql
}

function test_mysql_connection() {
    echo "Testing MySQL connection..."
    if mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SELECT 'MySQL Connection OK' as status;" > /dev/null 2>&1; then
        echo "✅ MySQL connection successful"
        mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SELECT VERSION() as mysql_version;"
    else
        echo "❌ MySQL connection failed"
        echo "💡 Try running: $0 setup"
        return 1
    fi
}

function check_cdc_config() {
    echo "Checking MySQL CDC configuration..."
    
    echo "📊 Binary Logging Status:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW VARIABLES LIKE 'log_bin';"
    
    echo "📊 Binary Log Format:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW VARIABLES LIKE 'binlog_format';"
    
    echo "📊 Binary Log Row Image:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW VARIABLES LIKE 'binlog_row_image';"
    
    echo "📊 Master Status:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW MASTER STATUS;"
    
    echo "📊 Debezium User Privileges:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SHOW GRANTS FOR '${MYSQL_USER}'@'localhost';" 2>/dev/null || echo "❌ Debezium user privileges not found"
}

function show_sample_data() {
    echo "📋 Sample Data Overview:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "
    USE inventory;
    SELECT 'Customers Count:' as info, COUNT(*) as count FROM customers
    UNION ALL
    SELECT 'Products Count:' as info, COUNT(*) as count FROM products;
    "
    
    echo "📋 Recent Customers:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "USE inventory; SELECT * FROM customers LIMIT 3;"
    
    echo "📋 Recent Products:"
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "USE inventory; SELECT * FROM products LIMIT 3;"
}

function simulate_changes() {
    echo "🔄 Simulating database changes for CDC testing..."
    
    mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "
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
    mysql -u root -p${MYSQL_ROOT_PASSWORD} < "$PROJECT_DIR/mysql/init.sql" > /dev/null
    echo "✅ Sample data reset"
}

function diagnose() {
    echo "🔍 MySQL Setup Diagnostics"
    echo "=========================="
    echo ""
    
    echo "📋 System Information:"
    echo "   OS: $(uname -s)"
    echo "   Architecture: $(uname -m)"
    echo ""
    
    echo "📋 Homebrew Status:"
    if command -v brew &> /dev/null; then
        echo "   ✅ Homebrew installed: $(brew --version | head -1)"
    else
        echo "   ❌ Homebrew not installed"
    fi
    echo ""
    
    echo "📋 MySQL Installation:"
    if command -v mysql &> /dev/null; then
        echo "   ✅ MySQL installed: $(mysql --version)"
        echo "   📂 Config file: $MYSQL_CONFIG_FILE"
        if [ -f "$MYSQL_CONFIG_FILE" ]; then
            echo "   ✅ Config file exists"
        else
            echo "   ❌ Config file missing"
        fi
    else
        echo "   ❌ MySQL not installed"
    fi
    echo ""
    
    echo "📋 MySQL Service Status:"
    if brew services list | grep -q "mysql.*started"; then
        echo "   ✅ MySQL service is running"
    else
        echo "   ❌ MySQL service not running"
    fi
    echo ""
    
    echo "📋 Connection Test:"
    if mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
        echo "   ✅ Can connect with debezium user"
    else
        echo "   ❌ Cannot connect with debezium user"
    fi
    
    if mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
        echo "   ✅ Can connect with root user"
    else
        echo "   ❌ Cannot connect with root user"
    fi
    echo ""
    
    echo "💡 Recommended Actions:"
    if ! command -v mysql &> /dev/null; then
        echo "   → Run: $0 setup"
    elif ! brew services list | grep -q "mysql.*started"; then
        echo "   → Run: $0 start"
    elif ! mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; then
        echo "   → Run: $0 setup (to create debezium user)"
    else
        echo "   → Everything looks good! Try: $0 test"
    fi
}

case "$1" in
    setup)
        setup_mysql
        ;;
    install)
        check_dependencies
        install_mysql
        ;;
    start)
        start_mysql
        ;;
    stop)
        stop_mysql
        ;;
    restart)
        stop_mysql
        sleep 2
        start_mysql
        ;;
    diagnose)
        diagnose
        ;;
    reinstall)
        reinstall_mysql
        ;;
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
        echo "Usage: $0 {setup|install|start|stop|restart|reinstall|diagnose|test|status|data|changes|reset|full}"
        echo ""
        echo "Setup Commands:"
        echo "  setup      - Complete MySQL setup (install, configure, secure, initialize)"
        echo "  install    - Install MySQL via Homebrew"
        echo "  reinstall  - Completely reinstall MySQL (removes all data)"
        echo "  diagnose   - Run diagnostic checks and show recommendations"
        echo ""
        echo "Service Commands:"
        echo "  start      - Start MySQL server"
        echo "  stop       - Stop MySQL server"
        echo "  restart    - Restart MySQL server"
        echo ""
        echo "Testing Commands:"
        echo "  test       - Test MySQL connection"
        echo "  status     - Show CDC configuration status"
        echo "  data       - Show current sample data"
        echo "  changes    - Simulate database changes for testing"
        echo "  reset      - Reset sample data to initial state"
        echo "  full       - Run all status checks"
        echo ""
        echo "🚀 For first-time setup, run: $0 setup"
        exit 1
        ;;
esac