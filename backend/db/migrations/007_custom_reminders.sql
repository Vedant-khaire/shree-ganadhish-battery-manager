-- =============================================================================
-- Migration 007: Custom Reminder Intervals & Udhari Recovery Support
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Add columns to batteries table for custom schedules
ALTER TABLE batteries ADD COLUMN IF NOT EXISTS service_reminder_interval_months INTEGER;
ALTER TABLE batteries ADD COLUMN IF NOT EXISTS water_check_interval_months INTEGER;

-- 2. Backfill existing batteries data with default schedules
UPDATE batteries 
SET service_reminder_interval_months = 12 
WHERE service_reminder_interval_months IS NULL;

UPDATE batteries 
SET water_check_interval_months = 6 
WHERE battery_type = 'INVERTER' AND water_check_interval_months IS NULL;

-- 3. Update service_reminders constraints to support both 'UDHARI' and 'UDHARI_RECOVERY'
ALTER TABLE service_reminders DROP CONSTRAINT IF EXISTS service_reminders_reminder_type_check;
ALTER TABLE service_reminders ADD CONSTRAINT service_reminders_reminder_type_check 
    CHECK (reminder_type IN ('WATER_CHECK', 'SERVICE', 'WARRANTY_EXPIRY', 'UDHARI', 'UDHARI_RECOVERY'));
