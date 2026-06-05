-- =============================================================================
-- Migration 004: Service Reminders schema
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

CREATE TABLE IF NOT EXISTS service_reminders (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id             UUID REFERENCES customers(id) ON DELETE SET NULL,
    battery_id              UUID REFERENCES batteries(id) ON DELETE SET NULL,
    customer_name           TEXT NOT NULL,
    mobile_number           TEXT NOT NULL,
    battery_model           TEXT,
    battery_serial          TEXT,
    battery_type            TEXT,
    reminder_type           TEXT NOT NULL CHECK (reminder_type IN ('WATER_CHECK', 'SERVICE', 'WARRANTY_EXPIRY')),
    reminder_date           DATE NOT NULL,
    warranty_expiry         DATE,
    reminder_status         TEXT NOT NULL DEFAULT 'UPCOMING' CHECK (reminder_status IN ('UPCOMING', 'DUE', 'OVERDUE', 'COMPLETED', 'EXPIRED')),
    message_sent            BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at                 TIMESTAMPTZ,
    is_completed            BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived             BOOLEAN NOT NULL DEFAULT FALSE,
    notes                   TEXT,
    whatsapp_template       TEXT,
    whatsapp_delivery_status TEXT NOT NULL DEFAULT 'PENDING',
    whatsapp_message_id     TEXT,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reminders_date ON service_reminders(reminder_date);
CREATE INDEX IF NOT EXISTS idx_reminders_completed ON service_reminders(is_completed);
CREATE INDEX IF NOT EXISTS idx_reminders_status ON service_reminders(reminder_status);
CREATE INDEX IF NOT EXISTS idx_reminders_archived ON service_reminders(is_archived);
CREATE INDEX IF NOT EXISTS idx_reminders_customer ON service_reminders(customer_id);
CREATE INDEX IF NOT EXISTS idx_reminders_battery ON service_reminders(battery_id);
