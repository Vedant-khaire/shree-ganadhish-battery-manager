-- =============================================================================
-- Migration 003: Analytics and Follow-up support
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- Add is_followed_up column to batteries table
ALTER TABLE batteries ADD COLUMN IF NOT EXISTS is_followed_up BOOLEAN DEFAULT FALSE;

-- Add index on is_followed_up for fast analytics querying
CREATE INDEX IF NOT EXISTS idx_batteries_followed_up ON batteries(is_followed_up) WHERE is_followed_up = FALSE;
