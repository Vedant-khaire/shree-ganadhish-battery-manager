-- =============================================================================
-- Migration 006: Add missing notes column to batteries
-- Shree Ganadhish Auto Ele & Battery Services
-- =============================================================================

-- Add notes column to batteries table if it is missing
ALTER TABLE batteries ADD COLUMN IF NOT EXISTS notes TEXT;
