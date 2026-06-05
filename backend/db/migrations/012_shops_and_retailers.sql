-- =============================================================================
-- Migration 012: Shops / Retailers Module
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- 1. Create shops table
CREATE TABLE IF NOT EXISTS shops (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_name     TEXT NOT NULL,
    owner_name    TEXT NOT NULL,
    mobile        VARCHAR(15) NOT NULL,
    address       TEXT,
    is_archived   BOOLEAN DEFAULT FALSE,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Performance Indexes on shops
CREATE INDEX IF NOT EXISTS idx_shops_name ON shops(shop_name);
CREATE INDEX IF NOT EXISTS idx_shops_mobile ON shops(mobile);

-- 2. Create shop_purchases table
CREATE TABLE IF NOT EXISTS shop_purchases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id             UUID REFERENCES shops(id) ON DELETE RESTRICT,
    battery_model       TEXT NOT NULL,
    serial_number       TEXT NOT NULL, -- Mandatory
    invoice_number      TEXT NOT NULL, -- Invoice number field
    quantity            INTEGER DEFAULT 1,
    purchase_date       DATE NOT NULL,
    amount              NUMERIC(10,2) NOT NULL,
    udhari_amount       NUMERIC(10,2) DEFAULT 0.0,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Performance Indexes on shop_purchases
CREATE INDEX IF NOT EXISTS idx_shop_purchases_shop ON shop_purchases(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_purchases_date ON shop_purchases(purchase_date);
CREATE INDEX IF NOT EXISTS idx_shop_purchases_serial ON shop_purchases(serial_number);
CREATE INDEX IF NOT EXISTS idx_shop_purchases_invoice ON shop_purchases(invoice_number);

-- 3. Create shop_payments table for consolidated Udhari
CREATE TABLE IF NOT EXISTS shop_payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id         UUID UNIQUE REFERENCES shops(id) ON DELETE RESTRICT,
    total_amount    NUMERIC(10,2) NOT NULL DEFAULT 0.0,
    paid_amount     NUMERIC(10,2) NOT NULL DEFAULT 0.0,
    pending_amount  NUMERIC(10,2) NOT NULL DEFAULT 0.0,
    is_settled      BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Performance Indexes on shop_payments
CREATE INDEX IF NOT EXISTS idx_shop_payments_shop ON shop_payments(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_payments_settled ON shop_payments(is_settled);

-- 4. Create shop_payment_transactions table for ledger history
CREATE TABLE IF NOT EXISTS shop_payment_transactions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id       UUID REFERENCES shop_payments(id) ON DELETE CASCADE,
    shop_id          UUID REFERENCES shops(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL, -- 'ADDITION' or 'PAYMENT'
    amount           NUMERIC(10,2) NOT NULL,
    notes            TEXT,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Performance Indexes on shop_payment_transactions
CREATE INDEX IF NOT EXISTS idx_shop_payment_tx_payment ON shop_payment_transactions(payment_id);
CREATE INDEX IF NOT EXISTS idx_shop_payment_tx_shop ON shop_payment_transactions(shop_id);
