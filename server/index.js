const express = require('express');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const Database = require('better-sqlite3');
const path = require('path');
const postgres = require('./db.postgres');

const PORT = process.env.PORT || 3003;
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'sales.db');
const USE_POSTGRES = !!process.env.DATABASE_URL;

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

let db;

function initSqlite() {
  db = new Database(DB_PATH);
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

  const row = db.prepare('SELECT id FROM users WHERE username = ?').get('admin');
  if (!row) {
    const hash = bcrypt.hashSync('admin', 10);
    db.prepare('INSERT INTO users (username, password_hash) VALUES (?, ?)').run('admin', hash);
    console.log('Default user created: admin / admin');
  }
}

function mapSqliteBillRow(row) {
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

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    db: 'connected',
    engine: USE_POSTGRES ? 'postgresql' : 'sqlite',
  });
});

app.post('/api/login', async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ ok: false, error: 'Username and password required' });
  }

  try {
    if (USE_POSTGRES) {
      const user = await postgres.loginUser(username, password);
      if (!user) {
        return res.status(200).json({ ok: false, error: 'Invalid username or password' });
      }
      return res.json({ ok: true, user: { username: user.username } });
    }

    const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
    if (!user || !bcrypt.compareSync(password, user.password_hash)) {
      return res.status(200).json({ ok: false, error: 'Invalid username or password' });
    }
    return res.json({ ok: true, user: { username: user.username } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Login failed' });
  }
});

app.get('/api/bills/next-number', async (req, res) => {
  const location = req.query.location || 'Location 1';
  try {
    const billNo = USE_POSTGRES
      ? await postgres.getNextBillNumber(location)
      : (db.prepare('SELECT MAX(bill_no) AS max_no FROM bills WHERE location = ?').get(location)?.max_no || 0) + 1;
    res.json({ ok: true, billNo });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load bill number' });
  }
});

app.get('/api/bills/by-number/previous', async (req, res) => {
  const billNo = parseInt(req.query.billNo, 10);
  const location = req.query.location || 'Location 1';
  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  try {
    const row = USE_POSTGRES
      ? await postgres.getPreviousBill(location, billNo)
      : db.prepare(
          `SELECT * FROM bills WHERE location = ? AND bill_no < ? ORDER BY bill_no DESC LIMIT 1`
        ).get(location, billNo);

    if (!row) {
      return res.status(404).json({ ok: false, error: 'No previous bill found' });
    }

    const bill = USE_POSTGRES ? postgres.mapBillRow(row) : mapSqliteBillRow(row);
    res.json({ ok: true, bill });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load previous bill' });
  }
});

app.get('/api/bills/:billNo', async (req, res) => {
  const billNo = parseInt(req.params.billNo, 10);
  const location = req.query.location || 'Location 1';
  if (!Number.isFinite(billNo)) {
    return res.status(400).json({ ok: false, error: 'Invalid bill number' });
  }

  try {
    const row = USE_POSTGRES
      ? await postgres.getBill(location, billNo)
      : db.prepare('SELECT * FROM bills WHERE location = ? AND bill_no = ?').get(location, billNo);

    if (!row) {
      return res.status(404).json({ ok: false, error: 'Bill not found' });
    }

    const bill = USE_POSTGRES ? postgres.mapBillRow(row) : mapSqliteBillRow(row);
    res.json({ ok: true, bill });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Could not load bill' });
  }
});

app.post('/api/bills', async (req, res) => {
  const bill = req.body || {};
  const required = [
    'billNo', 'location', 'billDate', 'paymentMode', 'customerName', 'items',
    'totalQty', 'totalAmount', 'totalCgst', 'totalSgst', 'totalIgst', 'grandTotal',
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
    if (USE_POSTGRES) {
      await postgres.saveBill(bill);
    } else {
      const existing = db
        .prepare('SELECT id FROM bills WHERE location = ? AND bill_no = ?')
        .get(bill.location, bill.billNo);

      if (existing) {
        db.prepare(
          `UPDATE bills SET bill_date=?, payment_mode=?, customer_name=?, mobile=?,
           total_qty=?, total_amount=?, total_cgst=?, total_sgst=?, total_igst=?,
           grand_total=?, items_json=? WHERE location=? AND bill_no=?`
        ).run(
          bill.billDate, bill.paymentMode, bill.customerName, bill.mobile || '',
          bill.totalQty, bill.totalAmount, bill.totalCgst, bill.totalSgst,
          bill.totalIgst, bill.grandTotal, JSON.stringify(bill.items),
          bill.location, bill.billNo
        );
      } else {
        db.prepare(
          `INSERT INTO bills (bill_no, location, bill_date, payment_mode, customer_name, mobile,
           total_qty, total_amount, total_cgst, total_sgst, total_igst, grand_total, items_json)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).run(
          bill.billNo, bill.location, bill.billDate, bill.paymentMode, bill.customerName,
          bill.mobile || '', bill.totalQty, bill.totalAmount, bill.totalCgst, bill.totalSgst,
          bill.totalIgst, bill.grandTotal, JSON.stringify(bill.items)
        );
      }
    }

    res.json({ ok: true, billNo: bill.billNo });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: 'Failed to save bill' });
  }
});

app.get('/api/ledger', async (req, res) => {
  const location = req.query.location || 'Location 1';
  const { from, to } = req.query;

  try {
    let rows;
    if (USE_POSTGRES) {
      rows = await postgres.getLedger(location, from, to);
    } else {
      let sql = `SELECT bill_no, bill_date, payment_mode, total_amount, total_cgst,
                        total_sgst, total_igst, grand_total
                 FROM bills WHERE location = ?`;
      const params = [location];
      if (from) { sql += ' AND bill_date >= ?'; params.push(from); }
      if (to) { sql += ' AND bill_date <= ?'; params.push(to); }
      sql += ' ORDER BY bill_no ASC';
      rows = db.prepare(sql).all(...params);
    }

    const entries = rows.map((row) => ({
      billNo: row.bill_no,
      date: USE_POSTGRES && row.bill_date instanceof Date
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
  if (USE_POSTGRES) {
    await postgres.initPostgres();
    console.log('Using PostgreSQL database');
  } else {
    initSqlite();
    console.log(`Using SQLite database: ${DB_PATH}`);
  }

  app.listen(PORT, () => {
    console.log(`Sales Bill API listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
