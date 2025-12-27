-- ClickHouse Database Setup for MySQL to ClickHouse Sync
-- This script creates the necessary tables for receiving MySQL change events

-- Create a database for sync data
CREATE DATABASE IF NOT EXISTS mysql_sync;

-- Switch to the sync database
USE mysql_sync;

-- Sample customers table to match MySQL structure
CREATE TABLE customers (
    id UInt32,
    first_name String,
    last_name String,
    email String,
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    
    -- Debezium metadata
    op String,           -- operation: c=create, u=update, d=delete
    source_ts_ms UInt64, -- source timestamp
    ts_ms UInt64         -- event timestamp
) ENGINE = MergeTree()
ORDER BY id;

-- Create a sample products table
CREATE TABLE products (
    id UInt32,
    name String,
    description String,
    weight Float32,
    created_at DateTime DEFAULT now(),
    updated_at DateTime DEFAULT now(),
    
    -- Debezium metadata
    op String,
    source_ts_ms UInt64,
    ts_ms UInt64
) ENGINE = MergeTree()
ORDER BY id;

-- Show created tables
SHOW TABLES;

-- Display table structures
DESCRIBE customers;
DESCRIBE products;