-- =============================================================================
-- Migration 010: Complete removal of SMS tables, columns, and templates
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Drop SMS-related columns from the service_reminders table
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_sent;
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_sent_at;
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_delivery_status;
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_message_id;
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_error_message;
ALTER TABLE service_reminders DROP COLUMN IF EXISTS sms_retry_count;

-- 2. Delete SMS templates from message_templates
DELETE FROM message_templates WHERE template_type LIKE 'SMS_%';

-- 3. Modify template_type check constraint in message_templates
ALTER TABLE message_templates DROP CONSTRAINT IF EXISTS message_templates_template_type_check;
ALTER TABLE message_templates ADD CONSTRAINT message_templates_template_type_check CHECK (
    template_type IN (
        'SERVICE_REMINDER', 'WATER_CHECK', 'WARRANTY_EXPIRY', 'UDHARI_RECOVERY',
        'EMAIL_BACKUP', 'CUSTOM_PROMOTION', 'CUSTOM_BROADCAST'
      )
);
