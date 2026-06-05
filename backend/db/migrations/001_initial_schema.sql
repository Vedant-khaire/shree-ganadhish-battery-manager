-- =============================================================================
-- Migration 001: Core Tables
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- -------------------------
-- customers
-- -------------------------
CREATE TABLE IF NOT EXISTS customers (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name          TEXT NOT NULL,
    mobile        VARCHAR(15) NOT NULL,
    vehicle_no    VARCHAR(20),
    vehicle_type  TEXT,
    area          TEXT,
    pincode       VARCHAR(10),
    purchase_type TEXT DEFAULT 'RETAIL',   -- 'RETAIL' or 'SHOP'
    is_archived   BOOLEAN DEFAULT FALSE,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_mobile ON customers(mobile);
CREATE INDEX IF NOT EXISTS idx_customers_name   ON customers(name);
CREATE INDEX IF NOT EXISTS idx_customers_area   ON customers(area);

-- -------------------------
-- batteries
-- -------------------------
CREATE TABLE IF NOT EXISTS batteries (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id            UUID REFERENCES customers(id) ON DELETE RESTRICT,
    battery_type           TEXT NOT NULL,   -- '2W', '4W', 'TRUCK', 'INVERTER'
    model_number           TEXT,
    serial_number          TEXT,
    sale_date              DATE NOT NULL,
    warranty_months        INTEGER NOT NULL,
    warranty_expiry        DATE NOT NULL,   -- sale_date + warranty_months
    warranty_reminder_date DATE NOT NULL,   -- always sale_date + 12 months
    invoice_image_url      TEXT,            -- future: guarantee card / invoice image
    is_archived            BOOLEAN DEFAULT FALSE,
    created_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_batteries_serial ON batteries(serial_number)
    WHERE serial_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_batteries_model       ON batteries(model_number);
CREATE INDEX IF NOT EXISTS idx_batteries_customer    ON batteries(customer_id);
CREATE INDEX IF NOT EXISTS idx_batteries_sale_date   ON batteries(sale_date);

-- -------------------------
-- payments
-- -------------------------
CREATE TABLE IF NOT EXISTS payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id     UUID REFERENCES customers(id) ON DELETE RESTRICT,
    battery_id      UUID REFERENCES batteries(id) ON DELETE RESTRICT,
    total_amount    NUMERIC(10,2) NOT NULL,
    paid_amount     NUMERIC(10,2) DEFAULT 0,
    pending_amount  NUMERIC(10,2),          -- stored: total - paid
    reminder_note   TEXT,
    is_settled      BOOLEAN DEFAULT FALSE,
    is_archived     BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id);
CREATE INDEX IF NOT EXISTS idx_payments_settled  ON payments(is_settled);
CREATE INDEX IF NOT EXISTS idx_payments_created  ON payments(created_at);

-- -------------------------
-- activity_logs  (simple — 4 fields only)
-- -------------------------
CREATE TABLE IF NOT EXISTS activity_logs (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action     TEXT NOT NULL,   -- 'LOGIN', 'CUSTOMER_ADDED', 'PAYMENT_SETTLED', etc.
    device     TEXT,            -- 'mobile' or 'desktop'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_created ON activity_logs(created_at DESC);

-- -------------------------
-- settings  (single row, id = 1)
-- -------------------------
CREATE TABLE IF NOT EXISTS settings (
    id           INTEGER PRIMARY KEY DEFAULT 1,
    shop_name    TEXT DEFAULT 'Shree Ganadhish Auto Ele & Battery Services',
    shop_mobile  TEXT,
    shop_address TEXT
);

-- Seed default settings row (safe to run multiple times)
INSERT INTO settings (id, shop_name)
VALUES (1, 'Shree Ganadhish Auto Ele & Battery Services')
ON CONFLICT (id) DO NOTHING;
