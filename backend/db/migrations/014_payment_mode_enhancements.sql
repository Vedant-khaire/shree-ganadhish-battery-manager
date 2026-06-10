-- =============================================================================
-- Migration 014: Payment Mode Enhancements
-- Shree Ganadhish Auto Ele & Battery Services
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================

-- Add payment_mode column to payments table
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode TEXT;

-- Add payment_mode column to payment_transactions table
ALTER TABLE payment_transactions ADD COLUMN IF NOT EXISTS payment_mode TEXT;

-- Add payment_mode column to shop_payment_transactions table
ALTER TABLE shop_payment_transactions ADD COLUMN IF NOT EXISTS payment_mode TEXT;

-- Add scrap_payment_mode column to customers table
ALTER TABLE customers ADD COLUMN IF NOT EXISTS scrap_payment_mode TEXT;
