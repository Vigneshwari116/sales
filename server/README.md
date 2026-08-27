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

## API routes (unchanged)

| Method | Path |
|--------|------|
| GET | `/api/health` |
| POST | `/api/login` |
| GET | `/api/bills/next-number?location=Location%201` |
| GET | `/api/bills/:billNo?location=Location%201` |
| GET | `/api/bills/by-number/previous?billNo=5&location=Location%201` |
| POST | `/api/bills` |
| GET | `/api/ledger?location=Location%201` |

## View data in DBeaver

```sql
SELECT bill_no, bill_date, customer_name, payment_mode, grand_total
FROM bills
ORDER BY bill_no DESC;
```
