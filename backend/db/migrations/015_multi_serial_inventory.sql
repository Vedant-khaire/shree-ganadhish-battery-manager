-- =============================================================================
-- Migration 015: Multi Serial Inventory and Physical Battery Unit Tracking
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Create battery_units table
CREATE TABLE IF NOT EXISTS battery_units (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name          TEXT NOT NULL,
    battery_type        TEXT NOT NULL,
    serial_number       TEXT UNIQUE NOT NULL,
    status              TEXT NOT NULL DEFAULT 'AVAILABLE', -- 'AVAILABLE', 'SOLD', 'DEFECTIVE', 'RETURNED'
    purchase_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    shop_source         TEXT, -- Supplier shop name
    shop_purchase_id    UUID REFERENCES shop_purchases(id) ON DELETE SET NULL, -- linked wholesale B2B sale
    customer_battery_id UUID REFERENCES batteries(id) ON DELETE SET NULL,      -- linked retail sale
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_battery_units_serial ON battery_units(serial_number);
CREATE INDEX IF NOT EXISTS idx_battery_units_status ON battery_units(status);
CREATE INDEX IF NOT EXISTS idx_battery_units_lookup ON battery_units(model_name, battery_type, status);

-- 2. Make shop_purchases.serial_number nullable for backward compatibility
ALTER TABLE shop_purchases ALTER COLUMN serial_number DROP NOT NULL;

-- 3. Migrate existing shop_purchases serial numbers to battery_units
INSERT INTO battery_units (model_name, battery_type, serial_number, status, purchase_date, shop_purchase_id)
SELECT 
    battery_model, 
    COALESCE((SELECT battery_type FROM battery_stock WHERE model_name = battery_model LIMIT 1), '4W'),
    serial_number, 
    'SOLD', 
    purchase_date, 
    id
FROM shop_purchases
WHERE serial_number IS NOT NULL AND TRIM(serial_number) != ''
ON CONFLICT (serial_number) DO NOTHING;

-- 4. Migrate existing batteries (retail customer sales) to battery_units
INSERT INTO battery_units (model_name, battery_type, serial_number, status, purchase_date, customer_battery_id)
SELECT 
    model_number, 
    battery_type, 
    serial_number, 
    'SOLD', 
    sale_date, 
    id
FROM batteries
WHERE serial_number IS NOT NULL AND TRIM(serial_number) != ''
ON CONFLICT (serial_number) DO NOTHING;
