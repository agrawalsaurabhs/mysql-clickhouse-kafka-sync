#!/bin/bash
# MySQL Setup Script
# Installs MySQL 8.0 via Homebrew (if missing), applies CDC configuration,
# starts the service, creates the debezium replication user, and initialises
# the inventory schema with sample data.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BREW_CNF="$(brew --prefix)/etc/my.cnf"

# Load root password from .env if present, default to 'password'
MYSQL_ROOT_PASSWORD="password"
if [ -f "$ROOT_DIR/.env" ]; then
    val=$(grep -E '^MYSQL_ROOT_PASSWORD=' "$ROOT_DIR/.env" | cut -d= -f2-)
    [ -n "$val" ] && MYSQL_ROOT_PASSWORD="$val"
fi
MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"

echo "=== MySQL Setup ==="

# -----------------------------------------
# 1. Install MySQL 8.0 via Homebrew
# -----------------------------------------
if ! brew list mysql@8.0 &>/dev/null; then
    echo "Installing MySQL 8.0..."
    brew install mysql@8.0
    brew link mysql@8.0 --force
    echo "MySQL 8.0 installed."
else
    echo "MySQL 8.0 already installed."
fi

# -----------------------------------------
# 2. Apply CDC configuration
# -----------------------------------------
echo "Applying CDC configuration..."
cp "$SCRIPT_DIR/my.cnf" "$BREW_CNF"

# -----------------------------------------
# 3. Start / restart MySQL service
# -----------------------------------------
if brew services list | grep -q "mysql@8.0.*started"; then
    echo "Restarting MySQL to apply config..."
    brew services restart mysql@8.0
else
    echo "Starting MySQL..."
    brew services start mysql@8.0
fi

echo -n "Waiting for MySQL to be ready"
for i in $(seq 1 30); do
    sleep 1
    if $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
        echo " ready."
        break
    fi
    echo -n "."
    if [ "$i" -eq 30 ]; then
        echo ""
        echo "ERROR: MySQL did not start within 30 seconds."
        exit 1
    fi
done

# -----------------------------------------
# 4. Create Debezium replication user
# -----------------------------------------
echo "Creating Debezium replication user..."
$MYSQL_CMD << 'SQL'
CREATE USER IF NOT EXISTS 'debezium'@'localhost' IDENTIFIED BY 'debezium_password';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'localhost';
FLUSH PRIVILEGES;
SQL
echo "Debezium user ready."

# -----------------------------------------
# 5. Initialise inventory schema
# -----------------------------------------
echo "Initialising inventory schema..."
$MYSQL_CMD < "$SCRIPT_DIR/init.sql"
echo "Schema initialised."

echo ""
echo "=== Setup Complete ==="
echo "  Host     : localhost:3306"
echo "  Database : inventory"
echo "  CDC user : debezium / debezium_password"
echo ""
echo "  Connect  : mysql -u root"
echo "  Verify   : mysql -u root -e 'SHOW MASTER STATUS\\G'"
