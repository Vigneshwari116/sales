-- Run this in DBeaver on database: db_accounting_testing
-- Schema: public

CREATE TABLE IF NOT EXISTS bills (
  id SERIAL PRIMARY KEY,
  bill_no INTEGER NOT NULL,
  location VARCHAR(100) NOT NULL,
  bill_date DATE NOT NULL,
  payment_mode VARCHAR(50) NOT NULL,
  customer_name VARCHAR(200) NOT NULL,
  mobile VARCHAR(30) DEFAULT '',
  total_qty NUMERIC(12, 2) NOT NULL,
  total_amount NUMERIC(12, 2) NOT NULL,
  total_cgst NUMERIC(12, 2) NOT NULL,
  total_sgst NUMERIC(12, 2) NOT NULL,
  total_igst NUMERIC(12, 2) NOT NULL,
  grand_total NUMERIC(12, 2) NOT NULL,
  items_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (location, bill_no)
);

CREATE INDEX IF NOT EXISTS idx_bills_location_date
  ON bills (location, bill_date);

-- After saving bills from the app, view data with:
-- SELECT * FROM bills ORDER BY bill_no DESC;
-- SELECT bill_no, bill_date, customer_name, grand_total FROM bills;
