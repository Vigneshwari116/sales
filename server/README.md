# Sales Bill API (PostgreSQL)

Node.js API for login, saving bills, previous bill, and sales ledger.

**Requires `DATABASE_URL`** — SQLite is no longer supported.

## Environment

```bash
export DATABASE_URL="postgresql://USER:PASSWORD@HOST:5434/salesbill_db"
export PORT=3003
```

## Run locally

```bash
cd server
npm install
npm start
```

Health check: `GET /api/health` → `{"ok":true,"db":"connected","engine":"postgresql"}`

## Docker deploy (VPS)

1. Edit `docker-compose.yml` — set `DATABASE_URL` to your Postgres on port **5434**, database **salesbill_db**
2. Rebuild and start:

```bash
cd server
docker compose up -d --build
```

## Tables (auto-created on startup)

| Table | Purpose |
|-------|---------|
| `users` | Login (`id`, `username`, `password_hash`) |
| `bills` | All saved sales bills |

If `users` is empty, default **admin / admin** is created.

## API routes

| Method | Path |
|--------|------|
| GET | `/api/health` |
| POST | `/api/login` |
| GET | `/api/bills/next-number?location=Win1` |
| GET | `/api/sync/bill-updates?location=Win1&since=<iso>` |
| GET | `/api/bills/updates-since?location=Win1&since=<iso>` |
| GET | `/api/bills/:billNo?location=Win1` (`:billNo` digits only) |
| GET | `/api/bills/by-number/previous?billNo=5&location=Win1` |
| POST | `/api/bills` |
| GET | `/api/ledger?location=Win1` |
| GET | `/api/gst/sync?location=win1` |
| POST | `/api/gst/config` |
| POST | `/api/locations/reset` |

## Import historical sales CSV

Use the sales-report CSV format (`BILLNO,DATE,NAME,MOBILE,CASH,CARD/UPI,TOTAL,CGST,SGST,IGST,GRAND TOTAL`):

```bash
cd server
DATABASE_URL="postgresql://USER:PASSWORD@HOST:5434/salesbill_db" \
  npm run import-csv -- win1 /path/to/bommasandra_sales_report.csv
```

Locations: `win1` (Bommasandra), `win2` (Tippasandra), `win3` (Grabhivapalya).

In the Flutter admin app, you can also import the same CSV from **Admin → SYNC → IMPORT CSV**, then use **DATE RANGE** in Abstract or Ledger to view the uploaded bills.

> Prefer `/api/sync/bill-updates` for pulls. Older VPS builds may still
> treat `/api/bills/updates-since` as `/api/bills/:billNo` and return
> `Invalid bill number`; the Flutter client falls back to ledger +
> per-bill GET when that happens.

## View data in DBeaver

```sql
SELECT bill_no, bill_date, customer_name, payment_mode, grand_total
FROM bills
ORDER BY bill_no DESC;
```
