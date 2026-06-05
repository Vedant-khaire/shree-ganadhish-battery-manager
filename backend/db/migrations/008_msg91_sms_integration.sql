-- =============================================================================
-- Migration 008: MSG91 SMS Integration Support
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- Add SMS-related columns to the service_reminders table
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_sent BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_sent_at TIMESTAMPTZ;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_delivery_status TEXT NOT NULL DEFAULT 'PENDING';
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_message_id TEXT;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_error_message TEXT;
ALTER TABLE service_reminders ADD COLUMN IF NOT EXISTS sms_retry_count INTEGER NOT NULL DEFAULT 0;

-- Create indexes to optimize SMS service lookups
CREATE INDEX IF NOT EXISTS idx_reminders_sms_sent ON service_reminders(sms_sent);
CREATE INDEX IF NOT EXISTS idx_reminders_sms_status ON service_reminders(sms_delivery_status);
CREATE INDEX IF NOT EXISTS idx_reminders_sms_message_id ON service_reminders(sms_message_id);
