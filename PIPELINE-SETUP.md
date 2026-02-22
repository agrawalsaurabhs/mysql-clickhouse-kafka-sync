# 🚀 One-Click CDC Pipeline Setup

This setup provides a complete CDC (Change Data Capture) pipeline from MySQL to ClickHouse using Debezium, Kafka, and a custom sink connector.

## Quick Start

Run the one-click setup script:

```bash
./scripts/start-pipeline.sh
```

This will:
1. Check prerequisites (MySQL, ClickHouse)
2. Initialize databases
3. Launch an iTerm2 window with 6 panes:
   - **Kafka Broker** - Event streaming platform
   - **ClickHouse Server** - Target database
   - **Debezium Connect** - CDC connector capturing MySQL changes
   - **Sink Connector** - Writes data from Kafka to ClickHouse
   - **Data Generator** - Inserts test records every 0.5 seconds
   - **Pipeline Monitor** - Real-time dashboard showing all components

## What It Does

The pipeline automatically:
- ✅ Starts all components (if not already running)
- 📊 Opens live logs for debugging in each pane
- 🔄 Captures MySQL changes in real-time
- 📝 Inserts new customers and products every 0.5 seconds
- 🚀 Syncs data to ClickHouse automatically
- 📈 Shows live statistics and monitoring

## Architecture

```
MySQL (Source)
    ↓ (binlog)
Debezium CDC Connector
    ↓ (events)
Kafka Topics
    ↓ (consume)
Sink Connector (Go)
    ↓ (insert)
ClickHouse (Target)
```

## Components

### 1. Kafka Broker (Port 9092)
- Manages event topics
- Stores CDC events from Debezium
- Logs: `kafka-data/kafka.log`

### 2. ClickHouse Server (Ports 9000, 8123)
- Target analytical database
- Stores synced data from MySQL
- Logs: `clickhouse-data/clickhouse-server.err.log`

### 3. Debezium Kafka Connect (Port 8083)
- Captures MySQL binlog changes
- Publishes events to Kafka
- REST API: http://localhost:8083
- Logs: `kafka-data/connect.log`

### 4. Sink Connector (Go)
- Consumes from Kafka topics
- Writes to ClickHouse
- Built from `sink-connector/main.go`

### 5. Data Generator
- Inserts records every 0.5 seconds
- Generates random customers and products
- Occasionally updates existing records

### 6. Pipeline Monitor
- Real-time component status
- Row counts for MySQL and ClickHouse
- Recent changes display
- Auto-refreshes every 5 seconds

## Web Interfaces

- **Redpanda Console**: http://localhost:9090
  - View Kafka topics, messages, consumer groups
  
- **Kafka Connect API**: http://localhost:8083
  - Check connector status and tasks

- **ClickHouse HTTP**: http://localhost:8123
  - Query interface

## Manual Component Control

If you need to control components individually:

```bash
# Kafka
./scripts/kafka.sh start|stop|restart|status

# ClickHouse
./scripts/clickhouse.sh start|stop|restart|status

# Debezium
./scripts/debezium.sh start|stop|restart|status|deploy

# Sink
./scripts/sink.sh start|stop|status|build

# Data Generator (run in background)
./scripts/generate-data.sh
```

## Stopping the Pipeline

To stop all components:

```bash
# Stop each component
./scripts/sink.sh stop
./scripts/debezium.sh stop
./scripts/kafka.sh stop
./scripts/clickhouse.sh stop

# Or just close the iTerm2 window and kill processes
pkill -f "mysql-clickhouse-sink"
pkill -f "ConnectDistributed"
pkill -f "kafka.Kafka"
pkill -f "clickhouse"
```

## Troubleshooting

### Kafka fails to start
- Check if port 9092 is already in use: `lsof -i :9092`
- Clear Kafka data: `rm -rf kafka-data/kafka-logs/*`

### Debezium can't connect to MySQL
- Ensure MySQL binlog is enabled
- Check debezium user privileges: `SHOW GRANTS FOR 'debezium'@'localhost';`

### ClickHouse connection issues
- Verify ClickHouse is running: `clickhouse client --query "SELECT 1"`
- Check port 9000 availability: `lsof -i :9000`

### Sink connector errors
- Check Go is installed: `go version`
- Rebuild: `cd sink-connector && go build`
- Check Kafka topics exist: `kafka-topics.sh --list`

### No data appearing in ClickHouse
- Verify Debezium connector is running: `curl http://localhost:8083/connectors/mysql-connector/status`
- Check Kafka topics have messages
- Verify sink connector logs

## Data Verification

Check data is flowing:

```bash
# MySQL source
mysql -e "SELECT COUNT(*) FROM inventory.customers;"

# ClickHouse target
clickhouse client -q "SELECT COUNT(*) FROM mysql_sync.customers;"

# Kafka topics
kafka-topics.sh --bootstrap-server localhost:9092 --list

# View messages
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic dbserver1.inventory.customers --from-beginning --max-messages 5
```

## Configuration Files

- `kafka-config/server.properties` - Kafka broker settings
- `debezium/connect-distributed.properties` - Kafka Connect config
- `debezium/mysql-connector.json` - Debezium CDC connector config
- `sink-connector/config.hjson` - Sink connector settings
- `cdc-pipeline.yml` - iTerm layout configuration

## Requirements

- MySQL (with binlog enabled)
- ClickHouse
- Kafka 3.7.0
- Go (for sink connector)
- iTerm2 + itermocil
- jq (for JSON parsing)

## What Gets Created

**MySQL Tables:**
- `inventory.customers`
- `inventory.products`

**ClickHouse Tables:**
- `mysql_sync.customers`
- `mysql_sync.products`

**Kafka Topics:**
- `dbserver1.inventory.customers`
- `dbserver1.inventory.products`

## Performance

- Data generator: 2 inserts/second (1 customer + 1 product every 0.5s)
- Debezium latency: <100ms
- End-to-end latency: <1 second typically

Enjoy your CDC pipeline! 🎉
