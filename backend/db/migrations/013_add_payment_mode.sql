-- =============================================================================
-- Migration 013: Add payment_mode Column
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- Add payment_mode column to customers table
ALTER TABLE customers ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'Cash';

-- Add payment_mode column to shop_purchases table
ALTER TABLE shop_purchases ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'Cash';
