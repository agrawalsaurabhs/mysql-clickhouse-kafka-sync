#!/bin/bash

# Generate Debezium MySQL connector configuration from environment variables
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
KAFKA_HOST="${KAFKA_HOST:-localhost}"
KAFKA_PORT="${KAFKA_PORT:-9092}"

# Generate connector configuration
cat > "$PROJECT_DIR/debezium/mysql-connector.json" << EOF
{
  "name": "mysql-inventory-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",

    "database.hostname": "${MYSQL_HOST}",
    "database.port": "${MYSQL_PORT}",
    "database.user": "${MYSQL_USER}",
    "database.password": "${MYSQL_PASSWORD}",
    "database.server.id": "184054",
    "topic.prefix": "mysql",
    "database.allowPublicKeyRetrieval": "true",

    "database.include.list": "inventory",
    "table.include.list": "inventory.customers,inventory.products",

    "schema.history.internal.kafka.bootstrap.servers": "${KAFKA_HOST}:${KAFKA_PORT}",
    "schema.history.internal.kafka.topic": "mysql.inventory.schema-changes",

    "table.whitelist": "inventory.customers,inventory.products",
    "database.history.kafka.bootstrap.servers": "${KAFKA_HOST}:${KAFKA_PORT}",
    "database.history.kafka.topic": "mysql.inventory.schema-changes",

    "include.schema.changes": "true",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "false",

    "transforms": "route",
    "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
    "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
    "transforms.route.replacement": "\$3",

    "tombstones.on.delete": "false",
    "decimal.handling.mode": "double",
    "bigint.unsigned.handling.mode": "long",
    "include.schema.comments": "true",

    "snapshot.mode": "when_needed",
    "snapshot.locking.mode": "minimal",

    "event.processing.failure.handling.mode": "warn",
    "inconsistent.schema.handling.mode": "warn",

    "max.batch.size": "2048",
    "max.queue.size": "8192",
    "poll.interval.ms": "1000",

    "provide.transaction.metadata": "false",

    "signal.enabled.channels": "kafka",
    "signal.kafka.topic": "mysql-signals",
    "signal.kafka.bootstrap.servers": "${KAFKA_HOST}:${KAFKA_PORT}"
  }
}
EOF

echo "✅ Generated MySQL connector configuration with environment variables"