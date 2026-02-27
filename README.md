# MySQL → ClickHouse CDC Pipeline

Real-time Change Data Capture pipeline that streams every insert, update, and delete from MySQL into ClickHouse. Built on Debezium, Kafka, and a custom Go sink connector.

## Architecture

```
MySQL 8.0       Debezium            Kafka         Go Sinker       ClickHouse
(binlog)  ───►  Kafka Connect  ───► Topics    ───► (consumer) ───► cdc_sync DB
                (port 8083)         customers                      customers
                                    products                       products
```

1. MySQL writes every row change to its binary log (binlog)
2. Debezium tails the binlog and publishes each change as a JSON event to Kafka
3. The Go sinker consumes those topics and bulk-inserts into ClickHouse every 5 seconds
4. ClickHouse appends every CDC event — inserts, updates, and deletes — giving a full audit trail

---

## Prerequisites

| Requirement | Install |
|---|---|
| macOS | Apple Silicon or Intel |
| Homebrew | https://brew.sh |
| Java 17 | `brew install openjdk@17` |
| Go 1.21+ | https://go.dev/dl |
| iTerm2 + itermocil | `gem install itermocil` |

MySQL, Kafka, ClickHouse and Debezium are downloaded automatically by the install scripts.

---

## Quick Start

```bash
git clone <your-repo>
cd rds-ch-sync
./scripts/install.sh
```

The script runs in order:

| Step | Component | What it does |
|---|---|---|
| 0 | .env | Creates `.env` from `.env.example` if not present |
| 1 | ClickHouse | Downloads binary, starts server, creates `cdc_sync` DB |
| 2 | Kafka | Installs via Homebrew, formats KRaft storage, starts broker |
| 3 | MySQL | Installs via Homebrew, applies CDC config, creates `inventory` schema |
| 4 | Debezium | Downloads connector plugin, starts Kafka Connect, registers MySQL connector |
| 5 | Sinker | Builds Go binary, starts consumer |

When all components are up, iTerm2 opens automatically with a monitoring layout.

## Tear Down

```bash
./scripts/cleanup.sh
```

---

## Monitoring Layout

```bash
itermocil --layout scripts/cdc-pipeline.yml
```

| Pane | Content |
|---|---|
| ClickHouse Logs | `tail -f clickhouse-setup/server.log` |
| Kafka Logs | `tail -f kafka-setup/kafka.log` |
| MySQL Error Log | MySQL error log |
| Debezium Logs | `tail -f debezium-setup/debezium.log` |
| Sinker Logs | `tail -f sinker-setup/sink.log` |
| Data Generator | Press Enter to start continuous CRUD operations |
| MySQL Client | `mysql` logged in to `inventory` |
| ClickHouse Client | `clickhouse client` on `cdc_sync` |

---

## Components

### MySQL (`mysql-setup/`)

Source database. Key CDC settings in `my.cnf`:

- `binlog_format = ROW` — captures full before/after row images
- `gtid_mode = ON` — global transaction IDs for reliable resumption
- `binlog_row_image = FULL` — all columns in every event

Schema: `inventory.customers`, `inventory.products`
CDC user: `debezium` with replication grants

### Kafka (`kafka-setup/`)

Message broker in **KRaft mode** (no Zookeeper). A `RegexRouter` transform strips the topic prefix:

```
mysql.inventory.customers  →  customers
mysql.inventory.products   →  products
```

### Debezium (`debezium-setup/`)

Kafka Connect worker running the Debezium MySQL connector (v2.4.0.Final). Reads the MySQL binlog and publishes each row change as a JSON event. Key settings:

- `snapshot.mode = when_needed` — full snapshot only if offset history is lost
- `value.converter.schemas.enable = false` — lean JSON, no schema envelope
- `tombstones.on.delete = false` — no null messages on deletes

REST API: `http://localhost:8083/connectors/mysql-inventory-connector/status`

### Sinker (`sinker-setup/`)

Go service that consumes Kafka topics and bulk-inserts into ClickHouse. Flushes every **5 seconds** or at **1000 rows**. Each event maps to:

| Column | Value |
|---|---|
| `id` | Primary key from the CDC payload |
| `data` | Full row as a JSON string |
| `op` | `c` create · `u` update · `d` delete · `r` snapshot |
| `source_ts_ms` | MySQL commit timestamp |
| `source_file` / `source_pos` / `source_row` | Binlog location tuple from Debezium source metadata |
| `source_gtid` | GTID from Debezium source metadata (when available) |
| `source_db` / `source_table` | Origin database and table |
| `_raw_message` | Full Debezium JSON for debugging |
| `_ingestion_time` | ClickHouse insert time |

POC views are also auto-created per table:

- `<table>_latest_by_ts_file_pos` uses `argMax(..., tuple(source_ts_ms, source_file_idx, source_pos, source_row, _ingestion_time))`
- `<table>_latest_by_gtid` uses `argMax(..., tuple(source_gtid != '', source_gtid, source_ts_ms, source_file_idx, source_pos, source_row, _ingestion_time))`

### ClickHouse (`clickhouse-setup/`)

Single self-contained binary. TCP `:9000` / HTTP `:8123`. Tables use `MergeTree` — every CDC operation is appended, giving complete history.

```sql
CREATE TABLE cdc_sync.customers (
    id              UInt32,
    data            String,
    op              String,
    is_deleted      UInt8,
    source_ts_ms    UInt64,
    source_file     String,
    source_file_idx UInt64,
    source_pos      UInt64,
    source_row      UInt64,
    source_gtid     String,
    source_db       String,
    source_table    String,
    _raw_message    String,
    _ingestion_time DateTime DEFAULT now()
) ENGINE = ReplacingMergeTree(source_ts_ms) ORDER BY id;
```

---

## Test the Pipeline

```sql
-- MySQL Client pane:
INSERT INTO customers (first_name, last_name, email)
VALUES ('John', 'Doe', 'john@example.com');
```

```sql
-- ClickHouse Client pane (within ~5 seconds):
SELECT id, JSONExtractString(data, 'first_name'), op, _ingestion_time
FROM customers ORDER BY _ingestion_time DESC LIMIT 5;

-- POC: compare latest-row pick strategies
SELECT id, op, source_ts_ms, source_file, source_pos, source_gtid
FROM customers_latest_by_ts_file_pos
ORDER BY id
LIMIT 10;

SELECT id, op, source_ts_ms, source_file, source_pos, source_gtid
FROM customers_latest_by_gtid
ORDER BY id
LIMIT 10;
```

For continuous random CRUD:

```bash
cd mysql-setup && ./generate-data.sh
```

---

## Project Structure

```
rds-ch-sync/
├── scripts/
│   ├── install.sh            # Start full pipeline
│   ├── cleanup.sh            # Stop full pipeline
│   └── cdc-pipeline.yml      # iTerm2 monitoring layout
├── clickhouse-setup/
│   ├── install.sh
│   └── cleanup.sh
├── kafka-setup/
│   ├── install.sh
│   └── cleanup.sh
├── mysql-setup/
│   ├── install.sh
│   ├── cleanup.sh
│   ├── my.cnf                # CDC configuration
│   ├── init.sql              # Schema DDL
│   └── generate-data.sh      # Random CRUD generator
├── debezium-setup/
│   ├── install.sh
│   ├── cleanup.sh
│   └── mysql-connector.json
├── sinker-setup/
│   ├── install.sh
│   ├── cleanup.sh
│   ├── main.go
│   ├── config.hjson
│   └── go.mod
├── .env.example
├── .gitignore
└── README.md
```
