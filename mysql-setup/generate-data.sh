#!/bin/bash

# Data Generator - Inserts records every 5 seconds
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
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-debezium}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-debezium_password}"

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
        mysql_exec -e "
        USE inventory;
        INSERT INTO customers (first_name, last_name, email) 
        VALUES ('$first_name', '$last_name', '$email');
        " 2>/dev/null
        
        mysql_exec -e "
        USE inventory;
        INSERT INTO products (name, description, weight) 
        VALUES ('$product_name', 'Auto-generated product #$counter', $weight);
        " 2>/dev/null
        
        echo "[$timestamp] #$counter - CREATE: Added $first_name $last_name, $product_name (${weight}kg)"
        
    elif [ $operation_type -lt 7 ]; then
        # UPDATE - 30% probability
        update_type=$((RANDOM % 3))
        if [ $update_type -eq 0 ]; then
            # Update customer
            mysql_exec -e "
            USE inventory;
            UPDATE customers SET email = CONCAT('updated_', email) 
            WHERE id = (SELECT id FROM (SELECT id FROM customers ORDER BY RAND() LIMIT 1) as tmp);
            " 2>/dev/null
            echo "[$timestamp] #$counter - UPDATE: Updated customer email"
        elif [ $update_type -eq 1 ]; then
            # Update product
            mysql_exec -e "
            USE inventory;
            UPDATE products SET weight = ROUND(RAND() * 10, 2)
            WHERE id = (SELECT id FROM (SELECT id FROM products ORDER BY RAND() LIMIT 1) as tmp);
            " 2>/dev/null
            echo "[$timestamp] #$counter - UPDATE: Updated product weight"
        else
            # Update customer name
            mysql_exec -e "
            USE inventory;
            UPDATE customers SET first_name = CONCAT(first_name, '-MOD') 
            WHERE id = (SELECT id FROM (SELECT id FROM customers ORDER BY RAND() LIMIT 1) as tmp);
            " 2>/dev/null
            echo "[$timestamp] #$counter - UPDATE: Updated customer name"
        fi
        
    elif [ $operation_type -lt 9 ]; then
        # DELETE - 20% probability
        delete_type=$((RANDOM % 2))
        if [ $delete_type -eq 0 ]; then
            # Delete customer (but keep some records)
            deleted_count=$(mysql_exec -e "
            USE inventory;
            DELETE FROM customers WHERE id = (
                SELECT id FROM (
                    SELECT id FROM customers WHERE id > 100 ORDER BY RAND() LIMIT 1
                ) as tmp
            );
            SELECT ROW_COUNT() as deleted;
            " 2>/dev/null | tail -1)
            if [ "$deleted_count" = "1" ]; then
                echo "[$timestamp] #$counter - DELETE: Removed customer"
            else
                echo "[$timestamp] #$counter - DELETE: No customers to delete (keeping base records)"
            fi
        else
            # Delete product
            deleted_count=$(mysql_exec -e "
            USE inventory;
            DELETE FROM products WHERE id = (
                SELECT id FROM (
                    SELECT id FROM products WHERE id > 100 ORDER BY RAND() LIMIT 1
                ) as tmp
            );
            SELECT ROW_COUNT() as deleted;
            " 2>/dev/null | tail -1)
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
            customer_count=$(mysql_exec -e "
            USE inventory;
            SELECT COUNT(*) as count FROM customers;
            " 2>/dev/null | tail -1)
            echo "[$timestamp] #$counter - READ: Total customers: $customer_count"
        elif [ $read_type -eq 1 ]; then
            product_count=$(mysql_exec -e "
            USE inventory;
            SELECT COUNT(*) as count FROM products;
            " 2>/dev/null | tail -1)
            echo "[$timestamp] #$counter - READ: Total products: $product_count"
        else
            latest_customer=$(mysql_exec -e "
            USE inventory;
            SELECT CONCAT(first_name, ' ', last_name) as name FROM customers ORDER BY id DESC LIMIT 1;
            " 2>/dev/null | tail -1)
            echo "[$timestamp] #$counter - READ: Latest customer: $latest_customer"
        fi
    fi
    
    # Wait 5 seconds
    sleep 5
done
