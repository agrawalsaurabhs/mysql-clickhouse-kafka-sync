#!/bin/bash

# Complete CDC Pipeline Setup for macOS
# This script will install and configure all required components from scratch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 CDC Pipeline - Complete Setup"
echo "================================="
echo ""
echo "This script will install and configure:"
echo "  • MySQL 8.0+ with CDC configuration"
echo "  • Apache Kafka 2.13-3.7.0"
echo "  • ClickHouse 23.12+"
echo "  • Go 1.21+ for sink connector"
echo "  • Required development tools"
echo ""

# Ask for confirmation
read -p "Continue with complete setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Setup cancelled"
    exit 1
fi

echo ""
echo "🔍 Checking system requirements..."
echo ""

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew is not installed. Installing now..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for current session
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "✅ Homebrew is available"
fi

# Update Homebrew
echo "⬇️ Updating Homebrew..."
brew update

echo ""
echo "📦 Installing system dependencies..."
echo ""

# Install basic development tools
brew install wget curl git

# Install Java (required for Kafka)
if ! command -v java &> /dev/null; then
    echo "📦 Installing OpenJDK..."
    brew install openjdk@17
    echo 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"' >> ~/.zprofile
    export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
else
    echo "✅ Java is already installed"
    java -version
fi

# Install Go
if ! command -v go &> /dev/null; then
    echo "📦 Installing Go..."
    brew install go
else
    echo "✅ Go is already installed"
    go version
fi

echo ""
echo "🏗️ Setting up MySQL..."
echo ""

# Setup MySQL
"$SCRIPT_DIR/mysql.sh" setup

echo ""
echo "🏗️ Setting up Kafka..."
echo ""

# Setup Kafka
"$SCRIPT_DIR/kafka.sh" setup

echo ""
echo "🏗️ Setting up ClickHouse..."
echo ""

# Setup ClickHouse
"$SCRIPT_DIR/clickhouse.sh" setup

echo ""
echo "🏗️ Setting up Debezium..."
echo ""

# Setup Debezium
"$SCRIPT_DIR/debezium.sh" setup

echo ""
echo "🏗️ Building sink connector..."
echo ""

# Setup sink connector
"$SCRIPT_DIR/sink.sh" setup

echo ""
echo "🔧 Setting up additional tools..."
echo ""

# Install iTerm2 automation tool
if ! command -v itermocil &> /dev/null; then
    echo "📦 Installing itermocil for terminal management..."
    gem install itermocil
else
    echo "✅ itermocil is already installed"
fi

# Make all scripts executable
echo "🔧 Setting up script permissions..."
chmod +x "$SCRIPT_DIR"/*.sh

echo ""
echo "✅ Complete Setup Finished!"
echo "=========================="
echo ""
echo "📊 Installed Components:"
echo "  • MySQL 8.0+ (configured for CDC)"
echo "  • Apache Kafka (with Zookeeper)"
echo "  • ClickHouse (analytical database)"
echo "  • Debezium MySQL Connector"
echo "  • Go sink connector (compiled)"
echo "  • Development tools and dependencies"
echo ""
echo "🚀 Next Steps:"
echo "  1. Test individual components:"
echo "     ./scripts/mysql.sh test"
echo "     ./scripts/kafka.sh test"
echo "     ./scripts/clickhouse.sh status"
echo "     ./scripts/debezium.sh diagnose"
echo "     ./scripts/sink.sh status"
echo ""
echo "  2. Start the complete pipeline:"
echo "     ./scripts/start-pipeline.sh"
echo ""
echo "  3. Or start components individually:"
echo "     ./scripts/mysql.sh start"
echo "     ./scripts/kafka.sh start"
echo "     ./scripts/clickhouse.sh start"
echo "     ./scripts/debezium.sh start"
echo "     ./scripts/debezium.sh create-connector"
echo "     ./scripts/sink.sh start"
echo ""
echo "📚 Documentation:"
echo "  • README.md - Project overview"
echo "  • PIPELINE-SETUP.md - Detailed setup guide"
echo ""
echo "🎉 Your CDC pipeline is ready to use!"
echo ""
echo "🏥 Run health check:"
echo "     ./scripts/health-check.sh"