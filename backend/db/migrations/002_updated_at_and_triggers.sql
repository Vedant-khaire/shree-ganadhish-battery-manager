-- =============================================================================
-- Migration 002: Add updated_at column + auto-update trigger
-- Run AFTER 001_initial_schema.sql
-- =============================================================================

-- Add updated_at to customers, batteries, payments
ALTER TABLE customers  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE batteries  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE payments   ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- =============================================================================
-- Reusable trigger function
-- =============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- =============================================================================
-- Attach trigger to each table
-- =============================================================================
DROP TRIGGER IF EXISTS set_customers_updated_at ON customers;
CREATE TRIGGER set_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_batteries_updated_at ON batteries;
CREATE TRIGGER set_batteries_updated_at
    BEFORE UPDATE ON batteries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS set_payments_updated_at ON payments;
CREATE TRIGGER set_payments_updated_at
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- PostgreSQL aggregate function for dashboard pending payments
-- Used by dashboard service via db.rpc("get_pending_payment_stats", {})
-- =============================================================================
CREATE OR REPLACE FUNCTION get_pending_payment_stats()
RETURNS TABLE(count BIGINT, total_amount NUMERIC) AS $$
    SELECT
        COUNT(*)::BIGINT         AS count,
        COALESCE(SUM(pending_amount), 0) AS total_amount
    FROM payments
    WHERE is_settled = FALSE
      AND is_archived = FALSE;
$$ LANGUAGE SQL STABLE;
