#!/bin/bash
# Drops the inventory database and debezium user, then stops MySQL.
# Does NOT uninstall MySQL (it may be used for other things).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load root password from .env if present, default to 'password'
MYSQL_ROOT_PASSWORD="password"
if [ -f "$ROOT_DIR/.env" ]; then
    val=$(grep -E '^MYSQL_ROOT_PASSWORD=' "$ROOT_DIR/.env" | cut -d= -f2-)
    [ -n "$val" ] && MYSQL_ROOT_PASSWORD="$val"
fi
MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"

echo "=== MySQL Cleanup ==="

# Drop database and user (best-effort — MySQL may already be stopped)
if $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
    echo "Dropping inventory database and debezium user..."
    $MYSQL_CMD << 'SQL'
DROP DATABASE IF EXISTS inventory;
DROP USER IF EXISTS 'debezium'@'localhost';
FLUSH PRIVILEGES;
SQL
    echo "Database and user removed."
else
    echo "MySQL not reachable — skipping database cleanup."
fi

# Stop MySQL service
if brew services list | grep -q "mysql@8.0.*started"; then
    brew services stop mysql@8.0
    echo "MySQL stopped."
else
    echo "MySQL is not running."
fi

echo "Done. Remaining files:"
ls "$SCRIPT_DIR"
