#!/bin/bash
# CDC Pipeline — Full Install
#
# Starts all components in dependency order:
#   1. ClickHouse  (no deps)
#   2. Kafka       (no deps)
#   3. MySQL       (no deps)
#   4. Debezium    (needs Kafka + MySQL)
#   5. Sinker      (needs ClickHouse + Kafka)
#
# Each component's install.sh is idempotent — safe to re-run.

set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { echo ""; echo "──────────────────────────────────────"; echo "  $1"; echo "──────────────────────────────────────"; }
ok()   { echo "✓ $1"; }
fail() { echo "✗ $1"; exit 1; }

# ── 0. .env setup ──────────────────────────────────────────────────────────────
step "0/5  Environment (.env)"
if [ ! -f "$ROOT/.env" ]; then
    cp "$ROOT/.env.example" "$ROOT/.env"
    echo "Created .env from .env.example — review and edit if needed."
else
    echo ".env already exists — skipping."
fi
ok ".env ready"

# ── 1. ClickHouse ──────────────────────────────────────────────────────────────
step "1/5  ClickHouse"
bash "$ROOT/clickhouse-setup/install.sh" || fail "ClickHouse setup failed"
ok "ClickHouse ready"

# ── 2. Kafka ───────────────────────────────────────────────────────────────────
step "2/5  Kafka"
bash "$ROOT/kafka-setup/install.sh" || fail "Kafka setup failed"
ok "Kafka ready"

# ── 3. MySQL ───────────────────────────────────────────────────────────────────
step "3/5  MySQL"
bash "$ROOT/mysql-setup/install.sh" || fail "MySQL setup failed"
ok "MySQL ready"

# ── 4. Debezium (Kafka Connect + MySQL connector) ──────────────────────────────
step "4/5  Debezium"
bash "$ROOT/debezium-setup/install.sh" || fail "Debezium setup failed"
ok "Debezium ready"

# ── 5. Sinker (Kafka → ClickHouse) ─────────────────────────────────────────────
step "5/5  Sinker"
bash "$ROOT/sinker-setup/install.sh" || fail "Sinker setup failed"
ok "Sinker ready"

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════"
echo "  CDC Pipeline is running"
echo "══════════════════════════════════════"
echo ""

# ── Open iTerm2 monitoring layout ──────────────────────────────────────────────
if ! command -v itermocil >/dev/null 2>&1; then
    step "Installing itermocil"
    brew install itermocil || fail "Failed to install itermocil"
    ok "itermocil installed"
fi

step "Opening iTerm2 monitoring layout"
itermocil --layout "$ROOT/scripts/cdc-pipeline.yml" || \
    echo "⚠  itermocil failed — run manually: itermocil --layout scripts/cdc-pipeline.yml"
ok "iTerm2 layout launched"
echo ""
echo "  MySQL     : localhost:3306  (db: inventory)"
echo "  Kafka     : localhost:9092"
echo "  Debezium  : http://localhost:8083/connectors"
echo "  ClickHouse: localhost:9000  (db: cdc_sync)"
echo ""
echo "  Insert data into MySQL to test the pipeline:"
echo "    cd $ROOT/mysql-setup && ./generate-data.sh"
echo ""
echo "  Query ClickHouse to verify sync:"
echo "    cd $ROOT/clickhouse-setup && ./clickhouse client \\"
echo "      --query 'SELECT * FROM cdc_sync.customers LIMIT 10'"
echo ""
