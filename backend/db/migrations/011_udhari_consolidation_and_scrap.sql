-- =============================================================================
-- Migration 011: Scrap Battery Tracking & Udhari Consolidation History
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Add Scrap Battery Columns to customers table
ALTER TABLE customers 
ADD COLUMN IF NOT EXISTS scrap_battery_pending BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS scrap_received_date DATE NULL,
ADD COLUMN IF NOT EXISTS scrap_expected_value NUMERIC(10,2) DEFAULT 0.0,
ADD COLUMN IF NOT EXISTS scrap_received_value NUMERIC(10,2) DEFAULT 0.0;

-- Create Indexes for Scrap Battery filtering
CREATE INDEX IF NOT EXISTS idx_customers_scrap_pending ON customers(scrap_battery_pending);

-- 2. Create payment_transactions table to keep transaction history
CREATE TABLE IF NOT EXISTS payment_transactions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id       UUID REFERENCES payments(id) ON DELETE CASCADE,
    customer_id      UUID REFERENCES customers(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL, -- 'ADDITION' or 'PAYMENT'
    amount           NUMERIC(10,2) NOT NULL,
    notes            TEXT,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Create Indexes for transaction history queries
CREATE INDEX IF NOT EXISTS idx_payment_transactions_payment ON payment_transactions(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_customer ON payment_transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_created ON payment_transactions(created_at DESC);

-- 3. Backfill existing payment records into transactions history
-- Insert the ADDITION transaction
INSERT INTO payment_transactions (payment_id, customer_id, transaction_type, amount, notes, created_at)
SELECT id, customer_id, 'ADDITION', total_amount, 'Initial bill addition', created_at
FROM payments
ON CONFLICT DO NOTHING;

-- Insert the PAYMENT (settlement) transaction if paid_amount > 0
INSERT INTO payment_transactions (payment_id, customer_id, transaction_type, amount, notes, created_at)
SELECT id, customer_id, 'PAYMENT', paid_amount, 'Initial paid amount', created_at
FROM payments
WHERE paid_amount > 0
ON CONFLICT DO NOTHING;
