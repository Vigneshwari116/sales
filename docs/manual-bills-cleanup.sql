-- Review before running on the VPS. Nothing here auto-executes.

-- =============================================================================
-- 1) Preview test rows only (safe SELECT)
-- =============================================================================
SELECT bill_no, location, customer_name, mobile, bill_date, grand_total
FROM bills
WHERE bill_no IN (881677, 99999)
   OR customer_name ILIKE 'E2E%'
   OR customer_name ILIKE 'SyncProbe%'
   OR customer_name ILIKE 'Sync Integration%'
ORDER BY location, bill_no;

-- =============================================================================
-- 2) Delete ONLY known test / probe rows
-- =============================================================================
BEGIN;

DELETE FROM bills
WHERE bill_no IN (881677, 99999)
   OR customer_name ILIKE 'E2E%'
   OR customer_name ILIKE 'SyncProbe%'
   OR customer_name ILIKE 'Sync Integration%';

-- Optional: confirm what remains for Win3 before COMMIT
-- SELECT bill_no, customer_name, mobile FROM bills WHERE location = 'Win3' ORDER BY bill_no;

COMMIT;
-- Or ROLLBACK; if the preview looked wrong.

-- =============================================================================
-- 3) FULL WIPE of all bills across every location (keeps table/schema)
--    Use only if you intentionally want a clean slate after demo/testing.
-- =============================================================================
BEGIN;

TRUNCATE TABLE bills RESTART IDENTITY;

COMMIT;
-- Or ROLLBACK;
