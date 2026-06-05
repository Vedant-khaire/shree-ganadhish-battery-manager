-- =============================================================================
-- Migration 005: SMART Udhari Reminders
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Extend service_reminders table to support Udhari reminders
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS reminder_category TEXT DEFAULT 'BATTERY';
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS linked_payment_id UUID REFERENCES payments(id) ON DELETE CASCADE;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS recurring_interval_days INTEGER DEFAULT 7;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS stop_when_settled BOOLEAN DEFAULT TRUE;

-- 2. Safely update or drop constraints to include 'UDHARI' as a valid reminder_type
ALTER TABLE service_reminders DROP CONSTRAINT IF EXISTS service_reminders_reminder_type_check;
ALTER TABLE service_reminders ADD CONSTRAINT service_reminders_reminder_type_check 
    CHECK (reminder_type IN ('WATER_CHECK', 'SERVICE', 'WARRANTY_EXPIRY', 'UDHARI'));

-- 3. Create indexes for Udhari recovery optimization
CREATE INDEX IF NOT EXISTS idx_reminders_linked_payment ON service_reminders(linked_payment_id);
CREATE INDEX IF NOT EXISTS idx_reminders_category ON service_reminders(reminder_category);
CREATE INDEX IF NOT EXISTS idx_reminders_date ON service_reminders(reminder_date);
