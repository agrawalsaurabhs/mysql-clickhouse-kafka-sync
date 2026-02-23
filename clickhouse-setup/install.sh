#!/bin/bash
# ClickHouse Setup Script
# Downloads the ClickHouse binary (if missing), starts the server, and
# initialises the cdc_sync database with the tables required for CDC.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLICKHOUSE="$SCRIPT_DIR/clickhouse"

echo "=== ClickHouse Setup ==="

# -----------------------------------------
# 1. Download binary if not present
# -----------------------------------------
if [ ! -f "$CLICKHOUSE" ]; then
    echo "Downloading ClickHouse..."
    cd "$SCRIPT_DIR"
    curl https://clickhouse.com/ | sh

    # macOS: remove quarantine attribute to avoid Gatekeeper prompts
    if [[ "$OSTYPE" == "darwin"* ]]; then
        xattr -d com.apple.quarantine "$CLICKHOUSE" 2>/dev/null || true
    fi

    echo "ClickHouse downloaded."
else
    echo "ClickHouse binary already present."
fi

"$CLICKHOUSE" --version

# -----------------------------------------
# 2. Start server (skip if already running)
# -----------------------------------------
if "$CLICKHOUSE" client --query "SELECT 1" > /dev/null 2>&1; then
    echo "ClickHouse server is already running."
else
    echo "Starting ClickHouse server..."
    cd "$SCRIPT_DIR"
    # On first run ClickHouse auto-creates config.xml and data/ here.
    # server.log captures early startup output.
    nohup "$CLICKHOUSE" server > "$SCRIPT_DIR/server.log" 2>&1 &
    echo $! > "$SCRIPT_DIR/clickhouse.pid"

    echo -n "Waiting for server to be ready"
    for i in $(seq 1 30); do
        sleep 1
        if "$CLICKHOUSE" client --query "SELECT 1" > /dev/null 2>&1; then
            echo " ready."
            break
        fi
        echo -n "."
        if [ "$i" -eq 30 ]; then
            echo ""
            echo "ERROR: Server did not start within 30 seconds."
            echo "Check logs: $SCRIPT_DIR/server.log"
            exit 1
        fi
    done
fi

# -----------------------------------------
# 3. Initialise database
# -----------------------------------------
echo "Initialising database..."

"$CLICKHOUSE" client --multiquery << 'SQL'
CREATE DATABASE IF NOT EXISTS cdc_sync;

-- Schema matches sinker-setup's createTables() / insertBatch() exactly.
-- `data` holds the full row as a JSON string; `_raw_message` is the raw Kafka payload.
CREATE TABLE IF NOT EXISTS cdc_sync.customers
(
    id              UInt32,
    data            String,
    op              String,
    source_ts_ms    UInt64,
    source_db       String,
    source_table    String,
    _raw_message    String,
    _ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (id, _ingestion_time);

CREATE TABLE IF NOT EXISTS cdc_sync.products
(
    id              UInt32,
    data            String,
    op              String,
    source_ts_ms    UInt64,
    source_db       String,
    source_table    String,
    _raw_message    String,
    _ingestion_time DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (id, _ingestion_time);
SQL

echo "Database 'cdc_sync' initialised."
echo ""
echo "=== Setup Complete ==="
echo "  TCP  : localhost:9000"
echo "  HTTP : localhost:8123"
echo "  DB   : cdc_sync"
echo ""
echo "  Connect : cd $SCRIPT_DIR && ./clickhouse client"
echo "  Logs    : $SCRIPT_DIR/server.log"
