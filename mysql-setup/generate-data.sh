#!/bin/bash

# Data Generator - Inserts records every 5 seconds
#set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a  # automatically export all variables
    source "$PROJECT_DIR/.env"
    set +a  # stop automatically exporting
fi

# Configuration with environment variable fallbacks
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-debezium}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-debezium_password}"
MYSQL_DATABASE="${MYSQL_DATABASE:-inventory}"

echo "🚀 Starting continuous data generation..."
echo "📝 Performing random CRUD operations every 5 seconds"
echo "   Create (INSERT): 40%"
echo "   Update: 30%" 
echo "   Delete: 20%"
echo "   Read queries: 10%"
echo "Press Ctrl+C to stop"
echo ""

# Counter for tracking insertions
counter=0

# MySQL connection helper
mysql_exec() {
    mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "$@"
}

mysql_exec_silent() {
    mysql_exec "$@" 2>/dev/null
}

check_write_access() {
    local probe_email
    probe_email="access_check_$(date +%s)_$RANDOM@example.com"

    mysql_exec_silent -e "
    USE ${MYSQL_DATABASE};
    START TRANSACTION;
    INSERT INTO customers (first_name, last_name, email)
    VALUES ('Access', 'Check', '${probe_email}');
    DELETE FROM customers WHERE email = '${probe_email}';
    ROLLBACK;
    "
}

execute_sql() {
    local sql="$1"
    local output
    if ! output=$(mysql_exec -e "$sql" 2>&1); then
        echo "❌ MySQL command failed: $output"
        return 1
    fi
    echo "$output"
}

# Verify connectivity and write access before starting loop
if ! mysql_exec_silent -e "SELECT 1;"; then
    echo "❌ Could not connect to MySQL using ${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}"
    echo "   Check MYSQL_HOST, MYSQL_PORT, MYSQL_USER and MYSQL_PASSWORD in .env"
    exit 1
fi

if ! check_write_access; then
    echo "❌ User '${MYSQL_USER}' does not have write permissions on ${MYSQL_DATABASE}.*"
    echo "   Run: ./mysql-setup/install.sh"
    echo "   Or grant manually:"
    echo "   GRANT SELECT, INSERT, UPDATE, DELETE ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';"
    exit 1
fi

# Arrays for generating random data
first_names=("Alice" "Bob" "Charlie" "David" "Eve" "Frank" "Grace" "Henry" "Ivy" "Jack" "Kate" "Liam" "Mia" "Noah" "Olivia" "Peter" "Quinn" "Ruby" "Sam" "Tina")
last_names=("Smith" "Johnson" "Williams" "Brown" "Jones" "Garcia" "Miller" "Davis" "Rodriguez" "Martinez" "Hernandez" "Lopez" "Gonzalez" "Wilson" "Anderson" "Thomas" "Taylor" "Moore" "Jackson" "Martin")
products=("Smartphone" "Tablet" "Laptop" "Monitor" "Keyboard" "Mouse" "Headphones" "Webcam" "Printer" "Scanner" "Router" "Switch" "Cable" "Charger" "Battery" "Case" "Stand" "Dock" "Hub" "Adapter")
adjectives=("Premium" "Deluxe" "Pro" "Ultra" "Mini" "Portable" "Wireless" "Smart" "Digital" "Advanced")

while true; do
    counter=$((counter + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Generate random data
    first_name=${first_names[$RANDOM % ${#first_names[@]}]}
    last_name=${last_names[$RANDOM % ${#last_names[@]}]}
    email=$(echo "${first_name}.${last_name}${counter}@example.com" | tr '[:upper:]' '[:lower:]')
    
    adjective=${adjectives[$RANDOM % ${#adjectives[@]}]}
    product=${products[$RANDOM % ${#products[@]}]}
    product_name="$adjective $product"
    weight=$(echo "scale=2; $RANDOM % 1000 / 100" | bc)
    
    # Random CRUD operation based on probability
    operation_type=$((RANDOM % 10))
    
    if [ $operation_type -lt 4 ]; then
        # CREATE (INSERT) - 40% probability
        if execute_sql "
        USE ${MYSQL_DATABASE};
        INSERT INTO customers (first_name, last_name, email) 
        VALUES ('$first_name', '$last_name', '$email');
        " >/dev/null && execute_sql "
        USE ${MYSQL_DATABASE};
        INSERT INTO products (name, description, weight) 
        VALUES ('$product_name', 'Auto-generated product #$counter', $weight);
        " >/dev/null; then
            echo "[$timestamp] #$counter - CREATE: Added $first_name $last_name, $product_name (${weight}kg)"
        else
            echo "[$timestamp] #$counter - CREATE: Failed"
        fi
        
    elif [ $operation_type -lt 7 ]; then
        # UPDATE - 30% probability
        update_type=$((RANDOM % 3))
        if [ $update_type -eq 0 ]; then
            # Update customer
            if execute_sql "
            USE ${MYSQL_DATABASE};
            UPDATE customers SET email = CONCAT('updated_', email) 
            WHERE id = (SELECT id FROM (SELECT id FROM customers ORDER BY RAND() LIMIT 1) as tmp);
            " >/dev/null; then
                echo "[$timestamp] #$counter - UPDATE: Updated customer email"
            else
                echo "[$timestamp] #$counter - UPDATE: Failed to update customer email"
            fi
        elif [ $update_type -eq 1 ]; then
            # Update product
            if execute_sql "
            USE ${MYSQL_DATABASE};
            UPDATE products SET weight = ROUND(RAND() * 10, 2)
            WHERE id = (SELECT id FROM (SELECT id FROM products ORDER BY RAND() LIMIT 1) as tmp);
            " >/dev/null; then
                echo "[$timestamp] #$counter - UPDATE: Updated product weight"
            else
                echo "[$timestamp] #$counter - UPDATE: Failed to update product weight"
            fi
        else
            # Update customer name
            if execute_sql "
            USE ${MYSQL_DATABASE};
            UPDATE customers SET first_name = CONCAT(first_name, '-MOD') 
            WHERE id = (SELECT id FROM (SELECT id FROM customers ORDER BY RAND() LIMIT 1) as tmp);
            " >/dev/null; then
                echo "[$timestamp] #$counter - UPDATE: Updated customer name"
            else
                echo "[$timestamp] #$counter - UPDATE: Failed to update customer name"
            fi
        fi
        
    elif [ $operation_type -lt 9 ]; then
        # DELETE - 20% probability
        delete_type=$((RANDOM % 2))
        if [ $delete_type -eq 0 ]; then
            # Delete customer (but keep some records)
            deleted_count=$(execute_sql "
            USE ${MYSQL_DATABASE};
            DELETE FROM customers WHERE id = (
                SELECT id FROM (
                    SELECT id FROM customers WHERE id > 100 ORDER BY RAND() LIMIT 1
                ) as tmp
            );
            SELECT ROW_COUNT() as deleted;
            " | tail -1)
            if [ "$deleted_count" = "1" ]; then
                echo "[$timestamp] #$counter - DELETE: Removed customer"
            else
                echo "[$timestamp] #$counter - DELETE: No customers to delete (keeping base records)"
            fi
        else
            # Delete product
            deleted_count=$(execute_sql "
            USE ${MYSQL_DATABASE};
            DELETE FROM products WHERE id = (
                SELECT id FROM (
                    SELECT id FROM products WHERE id > 100 ORDER BY RAND() LIMIT 1
                ) as tmp
            );
            SELECT ROW_COUNT() as deleted;
            " | tail -1)
            if [ "$deleted_count" = "1" ]; then
                echo "[$timestamp] #$counter - DELETE: Removed product"
            else
                echo "[$timestamp] #$counter - DELETE: No products to delete (keeping base records)"
            fi
        fi
        
    else
        # READ queries - 10% probability
        read_type=$((RANDOM % 3))
        if [ $read_type -eq 0 ]; then
            customer_count=$(execute_sql "
            USE ${MYSQL_DATABASE};
            SELECT COUNT(*) as count FROM customers;
            " | tail -1)
            echo "[$timestamp] #$counter - READ: Total customers: $customer_count"
        elif [ $read_type -eq 1 ]; then
            product_count=$(execute_sql "
            USE ${MYSQL_DATABASE};
            SELECT COUNT(*) as count FROM products;
            " | tail -1)
            echo "[$timestamp] #$counter - READ: Total products: $product_count"
        else
            latest_customer=$(execute_sql "
            USE ${MYSQL_DATABASE};
            SELECT CONCAT(first_name, ' ', last_name) as name FROM customers ORDER BY id DESC LIMIT 1;
            " | tail -1)
            echo "[$timestamp] #$counter - READ: Latest customer: $latest_customer"
        fi
    fi
    
    # Wait 5 seconds
    sleep 5
done
