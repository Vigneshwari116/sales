const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const Database = require('better-sqlite3');
const path = require('path');

const PORT = process.env.PORT || 3003;
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'sales.db');

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS bills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    bill_no INTEGER NOT NULL,
    location TEXT NOT NULL,
    bill_date TEXT NOT NULL,
    payment_mode TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    mobile TEXT,
    total_qty REAL NOT NULL,
    total_amount REAL NOT NULL,
    total_cgst REAL NOT NULL,
    total_sgst REAL NOT NULL,
    total_igst REAL NOT NULL,
    grand_total REAL NOT NULL,
    items_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(location, bill_no)
  );

  CREATE INDEX IF NOT EXISTS idx_bills_location_date
    ON bills(location, bill_date);
`);

function ensureDefaultUser() {
  const row = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
  if (!row) {
    const hash = bcrypt.hashSync('admin', 10);
    db.prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)').run('admin', hash);
    console.log('Default user created: admin / admin');
  }
}

ensureDefaultUser();

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, db: 'connected' });
});

app.post('/api/login', (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ ok: false, error: 'Username and password required' });
  }

  const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return res.status(200).json({ ok: false, error: 'Invalid username or password' });
  }

  res.json({ ok: true, user: { username: user.username } });
});

app.get('/api/bills/next-number', (req, res) => {
  const location = req.query.location || 'Location 1';
  const row = db
    .prepare('SELECT MAX(bill_no) AS max_no FROM bills WHERE location = ?')
    .get(location);
  const next = (row?.max_no || 0) + 1;
  res.json({ ok: true, billNo: next });
});

app.get('/api/bills/:billNo', (req, res) => {
  const billNo = parseInt(req.params.billNo, 10);
  const location = req.query.location || 'Location 1';

  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  const row = db
    .prepare('SELECT * FROM bills WHERE location = ? AND bill_no = ?')
    .get(location, billNo);

  if (!row) {
    return res.status(404).json({ ok: false, error: 'Bill not found' });
  }

  res.json({ ok: true, bill: mapBillRow(row) });
});

app.get('/api/bills/by-number/previous', (req, res) => {
  const billNo = parseInt(req.query.billNo, 10);
  const location = req.query.location || 'Location 1';

  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  const row = db
    .prepare(
      `SELECT * FROM bills
       WHERE location = ? AND bill_no < ?
       ORDER BY bill_no DESC
       LIMIT 1`
    )
    .get(location, billNo);

  if (!row) {
    return res.status(404).json({ ok: false, error: 'No previous bill found' });
  }

  res.json({ ok: true, bill: mapBillRow(row) });
});

app.post('/api/bills', (req, res) => {
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
    const existing = db
      .prepare('SELECT id FROM bills WHERE location = ? AND bill_no = ?')
      .get(bill.location, bill.billNo);

    if (existing) {
      db.prepare(
        `UPDATE bills SET
          bill_date = ?,
          payment_mode = ?,
          customer_name = ?,
          mobile = ?,
          total_qty = ?,
          total_amount = ?,
          total_cgst = ?,
          total_sgst = ?,
          total_igst = ?,
          grand_total = ?,
          items_json = ?
        WHERE location = ? AND bill_no = ?`
      ).run(
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
        JSON.stringify(bill.items),
        bill.location,
        bill.billNo
      );
    } else {
      db.prepare(
        `INSERT INTO bills (
          bill_no, location, bill_date, payment_mode, customer_name, mobile,
          total_qty, total_amount, total_cgst, total_sgst, total_igst, grand_total, items_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(
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
        JSON.stringify(bill.items)
      );
    }

    res.json({ ok: true, billNo: bill.billNo });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Failed to save bill' });
  }
});

app.get('/api/ledger', (req, res) => {
  const location = req.query.location || 'Location 1';
  const from = req.query.from;
  const to = req.query.to;

  let sql = `SELECT bill_no, bill_date, payment_mode, total_amount, total_cgst,
                    total_sgst, total_igst, grand_total
             FROM bills
             WHERE location = ?`;
  const params = [location];

  if (from) {
    sql += ' AND bill_date >= ?';
    params.push(from);
  }
  if (to) {
    sql += ' AND bill_date <= ?';
    params.push(to);
  }

  sql += ' ORDER BY bill_no ASC';

  const rows = db.prepare(sql).all(...params);

  const entries = rows.map((row) => ({
    billNo: row.bill_no,
    date: row.bill_date,
    paymentMode: row.payment_mode,
    total: row.total_amount,
    cgst: row.total_cgst,
    sgst: row.total_sgst,
    igst: row.total_igst,
    grandTotal: row.grand_total,
  }));

  const summary = entries.reduce(
    (acc, e) => ({
      total: acc.total + e.total,
      cgst: acc.cgst + e.cgst,
      sgst: acc.sgst + e.sgst,
      igst: acc.igst + e.igst,
      grandTotal: acc.grandTotal + e.grandTotal,
    }),
    { total: 0, cgst: 0, sgst: 0, igst: 0, grandTotal: 0 }
  );

  res.json({ ok: true, entries, summary });
});

function mapBillRow(row) {
  return {
    billNo: row.bill_no,
    location: row.location,
    billDate: row.bill_date,
    paymentMode: row.payment_mode,
    customerName: row.customer_name,
    mobile: row.mobile || '',
    totalQty: row.total_qty,
    totalAmount: row.total_amount,
    totalCgst: row.total_cgst,
    totalSgst: row.total_sgst,
    totalIgst: row.total_igst,
    grandTotal: row.grand_total,
    items: JSON.parse(row.items_json),
  };
}

app.listen(PORT, () => {
  console.log(`Sales Bill API listening on port ${PORT}`);
  console.log(`Database: ${DB_PATH}`);
});
