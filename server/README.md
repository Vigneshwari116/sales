# Sales Bill API

Node.js API for saving bills, loading previous bills, and sales ledger reports.

## Database tables

| Table | Purpose | View in DBeaver |
|-------|---------|-----------------|
| `users` | Login only (admin) | You already see this |
| `bills` | **All saved sales bills** | Open this to see bill data |

Sales data is **not** stored in `users`. After setup, open the **`bills`** table in DBeaver.

## PostgreSQL setup (DBeaver / VPS)

Your database is `db_accounting_testing`. You already have `users`. Create `bills`:

1. Open DBeaver → connect to `db_accounting_testing`
2. Open SQL Editor
3. Run the script: `server/schema.postgresql.sql`
4. Refresh **Tables** under `public` — you should see **`bills`**

### View saved sales in DBeaver

```sql
SELECT bill_no, bill_date, customer_name, payment_mode, grand_total
FROM bills
ORDER BY bill_no DESC;
```

To see line items (rate, qty, amount):

```sql
SELECT bill_no, items_json
FROM bills
ORDER BY bill_no DESC;
```

## Run server with PostgreSQL

On your VPS, set the connection string and start the server:

```bash
export DATABASE_URL="postgresql://USER:PASSWORD@HOST:5432/db_accounting_testing"
cd server
npm install
npm start
```

Check: `GET http://your-server:3003/api/health` should return `"engine":"postgresql"`.

## Run locally (SQLite)

Without `DATABASE_URL`, the server uses `server/sales.db` (not visible in DBeaver PostgreSQL).

```bash
cd server
npm install
npm start
```

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/login` | Login |
| POST | `/api/bills` | Save bill → writes to **`bills`** table |
| GET | `/api/bills/:billNo` | Load bill |
| GET | `/api/bills/by-number/previous` | Previous bill |
| GET | `/api/bills/next-number` | Next bill number |
| GET | `/api/ledger` | Sales ledger |

## Why you only see login data

The `users` table is **only for login**. Bill data appears in **`bills`** after you:

1. Create the `bills` table (SQL script above)
2. Deploy the updated server with `DATABASE_URL` pointing to PostgreSQL
3. Click **SAVE** in the sales app

Then refresh `bills` in DBeaver to see the rows.
