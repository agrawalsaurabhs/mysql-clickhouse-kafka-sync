-- MySQL Database Setup for Change Data Capture
-- This script creates sample databases and tables for the MySQL to ClickHouse sync demo

-- Create inventory database
CREATE DATABASE IF NOT EXISTS inventory;
USE inventory;

-- Create customers table
CREATE TABLE customers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create products table
CREATE TABLE products (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    weight DECIMAL(8,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert sample data into customers
INSERT INTO customers (first_name, last_name, email) VALUES
('John', 'Doe', 'john.doe@example.com'),
('Jane', 'Smith', 'jane.smith@example.com'),
('Bob', 'Johnson', 'bob.johnson@example.com'),
('Alice', 'Williams', 'alice.williams@example.com'),
('Charlie', 'Brown', 'charlie.brown@example.com');

-- Insert sample data into products  
INSERT INTO products (name, description, weight) VALUES
('Laptop Computer', 'High-performance laptop for professionals', 2.5),
('Wireless Mouse', 'Ergonomic wireless mouse with USB receiver', 0.15),
('Keyboard', 'Mechanical keyboard with backlit keys', 1.2),
('Monitor', '27-inch 4K display with USB-C connectivity', 5.8),
('Headphones', 'Noise-cancelling wireless headphones', 0.3);

-- Show the created data
SELECT 'Customers Table:' as Info;
SELECT * FROM customers;

SELECT 'Products Table:' as Info;
SELECT * FROM products;

-- Show table structures
SELECT 'Customers Table Structure:' as Info;
DESCRIBE customers;

SELECT 'Products Table Structure:' as Info;
DESCRIBE products;