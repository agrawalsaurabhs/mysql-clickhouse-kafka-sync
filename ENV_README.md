# Environment Configuration

This project uses environment variables to manage sensitive configuration data like passwords.

## Setup

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your actual passwords and paths:
   ```bash
   # Executable Paths (adjust based on your system)
   CLICKHOUSE_BIN=clickhouse  # or full path like /usr/local/bin/clickhouse
   BREW_BIN=brew
   HOMEBREW_PREFIX=/opt/homebrew  # or /usr/local on Intel Macs
   
   # MySQL Configuration
   MYSQL_ROOT_PASSWORD=your_mysql_root_password
   MYSQL_USER=debezium
   MYSQL_PASSWORD=your_debezium_password
   
   # ClickHouse Configuration  
   CLICKHOUSE_PASSWORD=your_clickhouse_password
   
   # Kafka Configuration (if needed for authentication)
   KAFKA_PASSWORD=your_kafka_password
   
   # Debezium Configuration (if needed)
   DEBEZIUM_PASSWORD=your_debezium_password
   ```

## Security Notes

- The `.env` file is automatically ignored by git and will not be committed
- Never commit passwords or sensitive data to version control
- Each team member should create their own `.env` file locally
- Use different passwords for different environments (dev, staging, production)

## Environment Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `CLICKHOUSE_BIN` | ClickHouse executable path | `clickhouse` |
| `BREW_BIN` | Homebrew executable path | `brew` |
| `HOMEBREW_PREFIX` | Homebrew installation prefix | `/opt/homebrew` |
| `MYSQL_HOST` | MySQL server host | `localhost` |
| `MYSQL_PORT` | MySQL server port | `3306` |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | `password` |
| `MYSQL_USER` | MySQL user for CDC | `debezium` |
| `MYSQL_PASSWORD` | Password for MySQL CDC user | `debezium_password` |
| `CLICKHOUSE_HOST` | ClickHouse server host | `127.0.0.1` |
| `CLICKHOUSE_PORT` | ClickHouse native port | `9000` |
| `CLICKHOUSE_HTTP_PORT` | ClickHouse HTTP port | `8123` |
| `CLICKHOUSE_USER` | ClickHouse user | `default` |
| `CLICKHOUSE_PASSWORD` | ClickHouse password | `` |
| `KAFKA_HOST` | Kafka broker host | `localhost` |
| `KAFKA_PORT` | Kafka broker port | `9092` |
| `ZOOKEEPER_HOST` | Zookeeper host | `localhost` |
| `ZOOKEEPER_PORT` | Zookeeper port | `2181` |
| `KAFKA_PASSWORD` | Kafka password (if auth enabled) | `kafka_password` |
| `DEBEZIUM_REST_PORT` | Debezium Connect REST API port | `8083` |
| `DEBEZIUM_PASSWORD` | Debezium password (if needed) | `debezium_password` |

## Script Integration

All scripts automatically load environment variables from `.env` if the file exists:

- `scripts/mysql.sh` - Uses MySQL credentials
- `scripts/cleanup.sh` - Uses MySQL root password
- Other scripts can be enhanced to use environment variables as needed

## Cross-Platform Compatibility

The scripts now use environment variables for executable paths, making them compatible across different systems:

### macOS (Apple Silicon)
```bash
HOMEBREW_PREFIX=/opt/homebrew
CLICKHOUSE_BIN=clickhouse  # if in PATH
```

### macOS (Intel)
```bash
HOMEBREW_PREFIX=/usr/local
CLICKHOUSE_BIN=clickhouse  # if in PATH
```

### Linux
```bash
HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew  # if using Homebrew on Linux
CLICKHOUSE_BIN=/usr/bin/clickhouse  # or wherever ClickHouse is installed
```

### Custom Installations
```bash
CLICKHOUSE_BIN=/custom/path/to/clickhouse
HOMEBREW_PREFIX=/custom/homebrew/path
```

## Troubleshooting

If you encounter authentication errors:

1. Verify your `.env` file exists and has the correct passwords
2. Make sure the `.env` file is in the project root directory
3. Check that environment variables are being loaded correctly:
   ```bash
   source .env
   echo $MYSQL_ROOT_PASSWORD
   ```