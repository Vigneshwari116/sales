-- PostgreSQL schema for Sales Bill API
-- Database: salesbill_db (on db_accounting_testing host, port 5434)
-- Run manually in DBeaver if needed; the server also auto-creates on startup.

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS bills (
  id SERIAL PRIMARY KEY,
  bill_no INTEGER NOT NULL,
  location TEXT NOT NULL,
  bill_date DATE NOT NULL,
  payment_mode TEXT NOT NULL,
  customer_name TEXT NOT NULL,
  mobile TEXT,
  total_qty DOUBLE PRECISION NOT NULL,
  total_amount DOUBLE PRECISION NOT NULL,
  total_cgst DOUBLE PRECISION NOT NULL,
  total_sgst DOUBLE PRECISION NOT NULL,
  total_igst DOUBLE PRECISION NOT NULL,
  grand_total DOUBLE PRECISION NOT NULL,
  items_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (location, bill_no)
);

CREATE INDEX IF NOT EXISTS idx_bills_location_date
  ON bills (location, bill_date);

CREATE INDEX IF NOT EXISTS idx_bills_location_updated_at
  ON bills (location, updated_at);

-- View saved bills:
-- SELECT bill_no, bill_date, customer_name, grand_total, items_json FROM bills ORDER BY bill_no DESC;
