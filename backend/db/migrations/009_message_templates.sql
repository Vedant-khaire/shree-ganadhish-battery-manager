-- =============================================================================
-- Migration 009: Message Templates, Versioning, Logs & Shop Settings
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- 1. Create message_templates table
CREATE TABLE IF NOT EXISTS message_templates (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_name           TEXT UNIQUE NOT NULL,
    template_type           TEXT NOT NULL CHECK (template_type IN (
                                'SERVICE_REMINDER', 'WATER_CHECK', 'WARRANTY_EXPIRY', 'UDHARI_RECOVERY',
                                'SMS_SERVICE_REMINDER', 'SMS_WATER_CHECK', 'SMS_WARRANTY_EXPIRY', 'SMS_UDHARI_RECOVERY',
                                'EMAIL_BACKUP', 'CUSTOM_PROMOTION', 'CUSTOM_BROADCAST'
                            )),
    message_subject         TEXT NULL,
    message_body            TEXT NOT NULL,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    version_no              INTEGER NOT NULL DEFAULT 1,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create message_template_versions table for tracking version history
CREATE TABLE IF NOT EXISTS message_template_versions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id             UUID NOT NULL REFERENCES message_templates(id) ON DELETE CASCADE,
    version_no              INTEGER NOT NULL,
    message_subject         TEXT NULL,
    message_body            TEXT NOT NULL,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_template_version UNIQUE (template_id, version_no)
);

-- 3. Create message_logs table to permanently archive outgoing communications
CREATE TABLE IF NOT EXISTS message_logs (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_name           TEXT NOT NULL,
    mobile_number           TEXT NOT NULL,
    channel                 TEXT NOT NULL CHECK (channel IN ('SMS', 'WHATSAPP', 'EMAIL')),
    message_type            TEXT NOT NULL,
    message_body            TEXT NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'SENT',
    sent_at                 TIMESTAMPTZ DEFAULT NOW(),
    provider_id             TEXT NULL
);

-- 4. Create shop_settings table
CREATE TABLE IF NOT EXISTS shop_settings (
    id                      UUID PRIMARY KEY DEFAULT '00000000-0000-0000-0000-000000000001'::uuid,
    shop_name               TEXT NOT NULL DEFAULT 'Shree Ganadhish Battery Services',
    shop_address            TEXT NOT NULL DEFAULT 'Pune, Maharashtra, India',
    shop_mobile             TEXT NOT NULL DEFAULT '9730911213',
    whatsapp_number         TEXT NOT NULL DEFAULT '9730911213',
    gst_number              TEXT NULL,
    logo_url                TEXT NULL,
    backup_email            TEXT NOT NULL DEFAULT 'shreeganadhishbattery@gmail.com',
    sms_sender_name         TEXT NOT NULL DEFAULT 'SGABPL',
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Seed default shop settings row
INSERT INTO shop_settings (id, shop_name, shop_address, shop_mobile, whatsapp_number, backup_email, sms_sender_name)
VALUES (
    '00000000-0000-0000-0000-000000000001'::uuid,
    'Shree Ganadhish Battery Services',
    'Pune, Maharashtra, India',
    '9730911213',
    '9730911213',
    'shreeganadhishbattery@gmail.com',
    'SGABPL'
) ON CONFLICT (id) DO NOTHING;

-- 6. Seed default message templates
-- SERVICE_REMINDER (WhatsApp)
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'WhatsApp Service Reminder', 'SERVICE_REMINDER',
    'Hello {customer_name}, your battery {battery_model} (Serial: {battery_serial}) is due for its scheduled maintenance checkup. Please bring your battery/vehicle to {shop_name} for a quick service check. Contact: {shop_mobile}'
) ON CONFLICT (template_name) DO NOTHING;

-- WATER_CHECK (WhatsApp)
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'WhatsApp Inverter Water Check', 'WATER_CHECK',
    'Hello {customer_name}, this is a friendly reminder from {shop_name} to check the distilled water levels of your Inverter battery {battery_model}. Checking regularly ensures long battery life! Contact: {shop_mobile}'
) ON CONFLICT (template_name) DO NOTHING;

-- WARRANTY_EXPIRY (WhatsApp)
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'WhatsApp Warranty Expiry warning', 'WARRANTY_EXPIRY',
    'Hello {customer_name}, please note that the guarantee period of your battery {battery_model} (Serial: {battery_serial}) will expire in 5 days on {expiry_date}. Contact {shop_name} at {shop_mobile} for any queries.'
) ON CONFLICT (template_name) DO NOTHING;

-- UDHARI_RECOVERY (WhatsApp)
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'WhatsApp Udhari Recovery Reminder', 'UDHARI_RECOVERY',
    'Namaste {customer_name},
Aapke battery account me ₹{pending_amount} baki hai.
Kripaya payment clear kare.

* {shop_name} ({shop_mobile})'
) ON CONFLICT (template_name) DO NOTHING;

-- SMS_SERVICE_REMINDER
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'SMS Service Reminder', 'SMS_SERVICE_REMINDER',
    'Hello {customer_name}, battery {battery_model} (Serial: {battery_serial}) due for service checkup. Please bring to {shop_name}. Contact {shop_mobile}'
) ON CONFLICT (template_name) DO NOTHING;

-- SMS_WATER_CHECK
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'SMS Inverter Water Check', 'SMS_WATER_CHECK',
    'Hello {customer_name}, please check distilled water level of Inverter battery {battery_model}. Shree Ganadhish Battery. Contact {shop_mobile}'
) ON CONFLICT (template_name) DO NOTHING;

-- SMS_WARRANTY_EXPIRY
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'SMS Warranty Expiry warning', 'SMS_WARRANTY_EXPIRY',
    'Hello {customer_name}, battery {battery_model} (Serial: {battery_serial}) warranty expires in 5 days on {expiry_date}. Contact {shop_name} at {shop_mobile}'
) ON CONFLICT (template_name) DO NOTHING;

-- SMS_UDHARI_RECOVERY
INSERT INTO message_templates (template_name, template_type, message_body)
VALUES (
    'SMS Udhari Recovery Reminder', 'SMS_UDHARI_RECOVERY',
    'Namaste {customer_name}, Aapke battery account me Rs. {pending_amount} pending baki hai. Kripaya payment clear kare. - {shop_name}'
) ON CONFLICT (template_name) DO NOTHING;

-- EMAIL_BACKUP
INSERT INTO message_templates (template_name, template_type, message_subject, message_body)
VALUES (
    'Email Database Backup Notification', 'EMAIL_BACKUP',
    '{shop_name} Backup - {period_label}',
    '{shop_name} Battery Management Backup

This backup was generated automatically.

Included:
- Customers
- Batteries
- Payments
- Stock
- Reminders

Generated At: {timestamp}

Please store this backup securely.'
) ON CONFLICT (template_name) DO NOTHING;

-- 7. Seed template initial versions history
INSERT INTO message_template_versions (template_id, version_no, message_subject, message_body)
SELECT id, 1, message_subject, message_body FROM message_templates ON CONFLICT DO NOTHING;

-- 8. Add triggers for managing updated_at dates
CREATE OR REPLACE TRIGGER trigger_message_templates_updated_at
    BEFORE UPDATE ON message_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trigger_shop_settings_updated_at
    BEFORE UPDATE ON shop_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 9. Create indexes for performance lookup
CREATE INDEX IF NOT EXISTS idx_template_type ON message_templates(template_type);
CREATE INDEX IF NOT EXISTS idx_template_active ON message_templates(is_active);
CREATE INDEX IF NOT EXISTS idx_log_channel ON message_logs(channel);
CREATE INDEX IF NOT EXISTS idx_log_sent_at ON message_logs(sent_at);
CREATE INDEX IF NOT EXISTS idx_log_type ON message_logs(message_type);
