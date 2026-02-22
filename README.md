# MySQL to ClickHouse Sync Pipeline

A real-time data synchronization pipeline that captures changes from MySQL using Debezium CDC and streams them to ClickHouse via Kafka. This implementation uses a standalone sink connector approach for production-grade flexibility and control.

## Architecture

```
MySQL (CDC) → Debezium → Kafka → Custom Sink Connector → ClickHouse
```

### Components

- **MySQL 8.0+** - Source database with binary logging enabled
- **Apache Kafka** - Message broker for CDC events
- **Debezium MySQL Connector** - Captures database changes via Kafka Connect
- **Custom Go Sink Connector** - Consumes Kafka messages and writes to ClickHouse
- **ClickHouse** - Target analytical database

## Prerequisites

- macOS (tested on latest)
- Homebrew package manager
- MySQL 8.0+ installed and configured
- Kafka 3.7.0+ (binary installation)
- Go 1.21+ for building sink connector
- ClickHouse 25.12+

## Quick Start

### 1. Environment Setup

Clone and navigate to the project:

```bash
git clone <your-repo>
cd rds-ch-sync
```

### 2. Start Infrastructure

**Start MySQL:**

```bash
./scripts/mysql.sh start
```

**Start Kafka ecosystem:**

```bash
./scripts/kafka.sh start
```

**Start ClickHouse:**

```bash
./scripts/clickhouse.sh start
```

### 3. Configure CDC Pipeline

**Deploy Debezium connector:**

```bash
./scripts/debezium.sh start
./scripts/debezium.sh create-connector
```

**Build and start sink connector:**

```bash
./scripts/sink.sh build
./scripts/sink.sh start
```

### 4. Verify Pipeline

**Check all services:**

```bash
./scripts/mysql.sh status
./scripts/kafka.sh status
./scripts/clickhouse.sh status
./scripts/debezium.sh connector-status
./scripts/sink.sh status
```

**Test CDC:**

```bash
./scripts/debezium.sh test-cdc
./scripts/sink.sh test-clickhouse
```

## Project Structure

```
rds-ch-sync/
├── scripts/
│   ├── mysql.sh              # MySQL management
│   ├── kafka.sh              # Kafka ecosystem management
│   ├── clickhouse.sh         # ClickHouse management
│   ├── debezium.sh           # Debezium connector management
│   └── sink.sh               # Sink connector management
├── debezium/
│   ├── mysql-connector-simple.json    # Debezium configuration
│   └── connect-distributed.properties # Kafka Connect settings
├── sink-connector/
│   ├── main.go               # Sink connector implementation
│   ├── config.hjson          # Sink configuration
│   ├── go.mod               # Go dependencies
│   └── mysql-clickhouse-sink # Built binary (ignored)
├── clickhouse-data/         # ClickHouse data directory (ignored)
├── README.md
└── .gitignore
```

## Configuration

### MySQL CDC Setup

The pipeline captures changes from MySQL tables in the `inventory` database:

- `customers` - Customer data
- `products` - Product catalog
- `orders` - Order transactions

### Debezium Configuration

Key settings in [`debezium/mysql-connector-simple.json`](debezium/mysql-connector-simple.json):

```json
{
  "database.hostname": "127.0.0.1",
  "database.port": 3306,
  "database.user": "debezium",
  "database.password": "debezium",
  "table.include.list": "inventory.customers,inventory.products,inventory.orders",
  "transforms": "extract",
  "transforms.extract.type": "io.debezium.transforms.ExtractNewRecordState"
}
```

### Sink Connector Configuration

Configuration in [`sink-connector/config.hjson`](sink-connector/config.hjson):

```hjson
{
  "clickhouse": {
    "host": "127.0.0.1",
    "port": 9000,
    "database": "default",
    "maxOpenConns": 20,
    "asyncInsert": true
  },
  "kafka": {
    "brokers": ["localhost:9092"]
  },
  "tasks": [
    {
      "name": "sinker-customers",
      "topic": "mysql.inventory.customers",
      "consumerGroup": "sinker-customers-v2",
      "tableName": "customers",
      "bufferSize": 1000,
      "flushInterval": 5
    }
  ]
}
```

## Data Schema

### ClickHouse Tables

Each source table is replicated with this schema:

```sql
CREATE TABLE customers (
    id UInt32,                    -- Source table primary key
    data String,                  -- JSON payload with clean data
    op String,                    -- Operation: c(create), u(update), d(delete)
    source_ts_ms UInt64,         -- MySQL timestamp
    source_db String,            -- Source database name
    source_table String,         -- Source table name
    _raw_message String,         -- Full Debezium message for debugging
    _ingestion_time DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (id, _ingestion_time);
```

### Sample Data Flow

**MySQL Insert:**

```sql
INSERT INTO customers (first_name, last_name, email)
VALUES ('John', 'Doe', 'john@example.com');
```

**ClickHouse Result:**

```sql
SELECT id, data, op FROM customers WHERE id = 1;
-- Result:
-- 1 | {"id":1,"first_name":"John","last_name":"Doe","email":"john@example.com"} | c
```

## Operations

### Management Scripts

All components can be managed using the provided scripts:

**MySQL:**

```bash
./scripts/mysql.sh {start|stop|status|test-cdc}
```

**Kafka:**

```bash
./scripts/kafka.sh {start|stop|status|create-topics|list-topics}
```

**ClickHouse:**

```bash
./scripts/clickhouse.sh {start|stop|status|client}
```

**Debezium:**

```bash
./scripts/debezium.sh {start|stop|status|create-connector|delete-connector|connector-status|test-cdc}
```

**Sink Connector:**

```bash
./scripts/sink.sh {start|stop|restart|status|build|clean|logs|test-clickhouse}
```

### Monitoring

**Check pipeline health:**

```bash
# Debezium connector status
./scripts/debezium.sh connector-status

# Sink connector status
./scripts/sink.sh status

# ClickHouse data verification
./scripts/sink.sh test-clickhouse
```

**View logs:**

```bash
# Kafka Connect logs
tail -f $KAFKA_HOME/logs/connect.log

# Sink connector logs (if running in background)
./scripts/sink.sh logs
```

### Testing

**Insert test data:**

```bash
./scripts/debezium.sh test-cdc
```

**Verify in ClickHouse:**

```bash
./scripts/clickhouse.sh client
# Then run: SELECT count(), op FROM customers GROUP BY op;
```

## Production Deployment

### Scaling Considerations

1. **Kafka Partitioning** - Partition topics by primary key for parallel processing
2. **Consumer Groups** - Scale sink connector instances horizontally
3. **ClickHouse Sharding** - Use distributed tables for large datasets
4. **Buffer Tuning** - Adjust `bufferSize` and `flushInterval` based on throughput

### Security

1. **Database Credentials** - Use environment variables or secret management
2. **Kafka Security** - Enable SASL/SSL for production clusters
3. **ClickHouse Access** - Configure users and permissions
4. **Network Security** - Use VPCs and security groups

### Monitoring

1. **Metrics** - Expose JMX metrics from Kafka Connect
2. **Alerting** - Monitor lag, error rates, and throughput
3. **Logging** - Centralized logging with structured formats
4. **Dashboards** - Grafana dashboards for operational visibility

## Troubleshooting

### Common Issues

**Debezium connector fails to start:**

```bash
# Check MySQL binary log configuration
./scripts/mysql.sh test-cdc

# Verify Kafka Connect logs
tail -f $KAFKA_HOME/logs/connect.log
```

**No data in ClickHouse:**

```bash
# Check consumer lag
./scripts/kafka.sh consumer-lag

# Verify sink connector logs
./scripts/sink.sh logs
```

**High latency:**

- Reduce `flushInterval` in sink configuration
- Increase `bufferSize` for better batching
- Tune Kafka consumer settings

### Log Locations

- **MySQL**: `/usr/local/var/log/mysql/`
- **Kafka**: `$KAFKA_HOME/logs/`
- **ClickHouse**: `~/clickhouse-data/clickhouse.err.log`
- **Sink Connector**: Console output or `sink.log`

## Development

### Building from Source

```bash
cd sink-connector
go mod tidy
go build -o mysql-clickhouse-sink main.go
```

### Testing Changes

```bash
# Rebuild and restart sink connector
./scripts/sink.sh clean
./scripts/sink.sh build
./scripts/sink.sh restart

# Test with sample data
./scripts/debezium.sh test-cdc
./scripts/sink.sh test-clickhouse
```

## License

[Add your license information here]

## Contributing

[Add contributing guidelines here]
