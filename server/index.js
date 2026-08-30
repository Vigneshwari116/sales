const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const { Pool } = require('pg');

const PORT = process.env.PORT || 3003;

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL environment variable is required');
  process.exit(1);
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

async function initDatabase() {
  await pool.query(`
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
      UNIQUE (location, bill_no)
    );

    CREATE INDEX IF NOT EXISTS idx_bills_location_date
      ON bills (location, bill_date);
  `);

  const userCount = await pool.query('SELECT COUNT(*)::int AS count FROM users');
  if (userCount.rows[0].count === 0) {
    const hash = bcrypt.hashSync('admin', 10);
    await pool.query(
      'INSERT INTO users (username, password_hash) VALUES ($1, $2)',
      ['admin', hash]
    );
    console.log('Default user created: admin / admin');
  }
}

function mapBillRow(row) {
  return {
    billNo: row.bill_no,
    location: row.location,
    billDate:
      row.bill_date instanceof Date
        ? row.bill_date.toISOString().slice(0, 10)
        : String(row.bill_date).slice(0, 10),
    paymentMode: row.payment_mode,
    customerName: row.customer_name,
    mobile: row.mobile || '',
    totalQty: Number(row.total_qty),
    totalAmount: Number(row.total_amount),
    totalCgst: Number(row.total_cgst),
    totalSgst: Number(row.total_sgst),
    totalIgst: Number(row.total_igst),
    grandTotal: Number(row.grand_total),
    items:
      typeof row.items_json === 'string'
        ? JSON.parse(row.items_json)
        : row.items_json,
  };
}

function buildLedgerSummary(entries) {
  return entries.reduce(
    (acc, e) => ({
      total: acc.total + e.total,
      cgst: acc.cgst + e.cgst,
      sgst: acc.sgst + e.sgst,
      igst: acc.igst + e.igst,
      grandTotal: acc.grandTotal + e.grandTotal,
    }),
    { total: 0, cgst: 0, sgst: 0, igst: 0, grandTotal: 0 }
  );
}

app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true, db: 'connected', engine: 'postgresql' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, db: 'disconnected', engine: 'postgresql' });
  }
});

app.post('/api/login', async (req, res) => {
  const username = String(req.body?.username ?? '').trim();
  const password = String(req.body?.password ?? '');
  if (!username || !password) {
    return res.status(400).json({ ok: false, error: 'Username and password required' });
  }

  try {
    const result = await pool.query(
      'SELECT * FROM users WHERE LOWER(username) = LOWER($1) LIMIT 1',
      [username]
    );
    const user = result.rows[0];
    if (!user || !bcrypt.compareSync(password, user.password_hash)) {
      return res.status(200).json({ ok: false, error: 'Invalid username or password' });
    }
    res.json({ ok: true, user: { username: user.username } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Login failed' });
  }
});

app.get('/api/bills/next-number', async (req, res) => {
  const location = req.query.location;
  if (!location) {
    return res.status(400).json({ error: 'location parameter is required' });
  }
  try {
    const result = await pool.query(
      'SELECT MAX(bill_no) AS max_no FROM bills WHERE location = $1',
      [location]
    );
    const billNo = (result.rows[0]?.max_no || 0) + 1;
    res.json({ ok: true, billNo });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load bill number' });
  }
});

app.get('/api/bills/by-number/previous', async (req, res) => {
  const billNo = parseInt(req.query.billNo, 10);
  const location = req.query.location;
  if (!location) {
    return res.status(400).json({ error: 'location parameter is required' });
  }
  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  try {
    const result = await pool.query(
      `SELECT * FROM bills
       WHERE location = $1 AND bill_no < $2
       ORDER BY bill_no DESC
       LIMIT 1`,
      [location, billNo]
    );
    const row = result.rows[0];
    if (!row) {
      return res.status(404).json({ ok: false, error: 'No previous bill found' });
    }
    res.json({ ok: true, bill: mapBillRow(row) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load previous bill' });
  }
});

app.get('/api/bills/:billNo', async (req, res) => {
  const billNo = parseInt(req.params.billNo, 10);
  const location = req.query.location;
  if (!location) {
    return res.status(400).json({ error: 'location parameter is required' });
  }
  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  try {
    const result = await pool.query(
      'SELECT * FROM bills WHERE location = $1 AND bill_no = $2 LIMIT 1',
      [location, billNo]
    );
    const row = result.rows[0];
    if (!row) {
      return res.status(404).json({ ok: false, error: 'Bill not found' });
    }
    res.json({ ok: true, bill: mapBillRow(row) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load bill' });
  }
});

app.post('/api/bills', async (req, res) => {
  const bill = req.body || {};
  const required = [
    'billNo',
    'location',
    'billDate',
    'paymentMode',
    'customerName',
    'items',
    'totalQty',
    'totalAmount',
    'totalCgst',
    'totalSgst',
    'totalIgst',
    'grandTotal',
  ];

  for (const key of required) {
    if (bill[key] === undefined || bill[key] === null) {
      return res.status(400).json({ ok: false, error: `Missing field: ${key}` });
    }
  }

  if (!Array.isArray(bill.items) || bill.items.length === 0) {
    return res.status(400).json({ ok: false, error: 'At least one item is required' });
  }

  try {
    const existing = await pool.query(
      'SELECT id FROM bills WHERE location = $1 AND bill_no = $2 LIMIT 1',
      [bill.location, bill.billNo]
    );

    const itemsJson = JSON.stringify(bill.items);

    if (existing.rowCount > 0) {
      await pool.query(
        `UPDATE bills SET
          bill_date = $1,
          payment_mode = $2,
          customer_name = $3,
          mobile = $4,
          total_qty = $5,
          total_amount = $6,
          total_cgst = $7,
          total_sgst = $8,
          total_igst = $9,
          grand_total = $10,
          items_json = $11::jsonb
        WHERE location = $12 AND bill_no = $13`,
        [
          bill.billDate,
          bill.paymentMode,
          bill.customerName,
          bill.mobile || '',
          bill.totalQty,
          bill.totalAmount,
          bill.totalCgst,
          bill.totalSgst,
          bill.totalIgst,
          bill.grandTotal,
          itemsJson,
          bill.location,
          bill.billNo,
        ]
      );
    } else {
      await pool.query(
        `INSERT INTO bills (
          bill_no, location, bill_date, payment_mode, customer_name, mobile,
          total_qty, total_amount, total_cgst, total_sgst, total_igst, grand_total, items_json
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13::jsonb)`,
        [
          bill.billNo,
          bill.location,
          bill.billDate,
          bill.paymentMode,
          bill.customerName,
          bill.mobile || '',
          bill.totalQty,
          bill.totalAmount,
          bill.totalCgst,
          bill.totalSgst,
          bill.totalIgst,
          bill.grandTotal,
          itemsJson,
        ]
      );
    }

    res.json({ ok: true, billNo: bill.billNo });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Failed to save bill' });
  }
});

app.get('/api/ledger', async (req, res) => {
  const location = req.query.location;
  if (!location) {
    return res.status(400).json({ error: 'location parameter is required' });
  }
  const { from, to } = req.query;

  try {
    let sql = `SELECT bill_no, bill_date, payment_mode, total_amount, total_cgst,
                      total_sgst, total_igst, grand_total
               FROM bills
               WHERE location = $1`;
    const params = [location];

    if (from) {
      params.push(from);
      sql += ` AND bill_date >= $${params.length}`;
    }
    if (to) {
      params.push(to);
      sql += ` AND bill_date <= $${params.length}`;
    }

    sql += ' ORDER BY bill_no ASC';
    const result = await pool.query(sql, params);

    const entries = result.rows.map((row) => ({
      billNo: row.bill_no,
      date:
        row.bill_date instanceof Date
          ? row.bill_date.toISOString().slice(0, 10)
          : String(row.bill_date).slice(0, 10),
      paymentMode: row.payment_mode,
      total: Number(row.total_amount),
      cgst: Number(row.total_cgst),
      sgst: Number(row.total_sgst),
      igst: Number(row.total_igst),
      grandTotal: Number(row.grand_total),
    }));

    res.json({ ok: true, entries, summary: buildLedgerSummary(entries) });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load ledger' });
  }
});

async function start() {
  await initDatabase();
  console.log('Using PostgreSQL database');

  app.listen(PORT, () => {
    console.log(`Sales Bill API listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
