-- =============================================================================
-- Migration 002: Battery Stock table
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

CREATE TABLE IF NOT EXISTS battery_stock (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name          TEXT NOT NULL,
    battery_type        TEXT NOT NULL,          -- '2W', '4W', 'TRUCK', 'INVERTER'
    quantity            INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    low_stock_threshold INTEGER NOT NULL DEFAULT 2 CHECK (low_stock_threshold >= 0),
    is_archived         BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(model_name, battery_type)
);

CREATE INDEX IF NOT EXISTS idx_stock_model_type ON battery_stock(model_name, battery_type);
CREATE INDEX IF NOT EXISTS idx_stock_archived ON battery_stock(is_archived);

-- Update batteries table to include optional notes column
ALTER TABLE batteries ADD COLUMN IF NOT EXISTS notes TEXT;
