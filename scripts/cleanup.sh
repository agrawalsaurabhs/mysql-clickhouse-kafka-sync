#!/bin/bash
# CDC Pipeline — Full Cleanup
#
# Stops all components in reverse dependency order:
#   1. Sinker
#   2. Debezium
#   3. MySQL
#   4. Kafka
#   5. ClickHouse

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { echo ""; echo "──────────────────────────────────────"; echo "  $1"; echo "──────────────────────────────────────"; }

# ── 1. Sinker ──────────────────────────────────────────────────────────────────
step "1/5  Sinker"
bash "$ROOT/sinker-setup/cleanup.sh"

# ── 2. Debezium ────────────────────────────────────────────────────────────────
step "2/5  Debezium"
bash "$ROOT/debezium-setup/cleanup.sh"

# ── 3. MySQL ───────────────────────────────────────────────────────────────────
step "3/5  MySQL"
bash "$ROOT/mysql-setup/cleanup.sh"

# ── 4. Kafka ───────────────────────────────────────────────────────────────────
step "4/5  Kafka"
bash "$ROOT/kafka-setup/cleanup.sh"

# ── 5. ClickHouse ──────────────────────────────────────────────────────────────
step "5/5  ClickHouse"
bash "$ROOT/clickhouse-setup/cleanup.sh"

echo ""
echo "══════════════════════════════════════"
echo "  CDC Pipeline stopped and cleaned up"
echo "══════════════════════════════════════"
echo ""
