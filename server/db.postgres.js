const bcrypt = require('bcryptjs');
const { Pool } = require('pg');

let pool;

function getPool() {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error('DATABASE_URL is not set');
    }
    pool = new Pool({ connectionString });
  }
  return pool;
}

async function initPostgres() {
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username VARCHAR(100) NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

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
  `);

  const existing = await db.query(
    'SELECT id FROM users WHERE username = $1 LIMIT 1',
    ['admin']
  );
  if (existing.rowCount === 0) {
    const hash = bcrypt.hashSync('admin', 10);
    await db.query(
      'INSERT INTO users (username, password_hash) VALUES ($1, $2)',
      ['admin', hash]
    );
    console.log('Default user created: admin / admin');
  }
}

async function loginUser(username, password) {
  const result = await getPool().query(
    'SELECT * FROM users WHERE username = $1 LIMIT 1',
    [username]
  );
  const user = result.rows[0];
  if (!user || !bcrypt.compareSync(password, user.password_hash)) {
    return null;
  }
  return user;
}

async function getNextBillNumber(location) {
  const result = await getPool().query(
    'SELECT MAX(bill_no) AS max_no FROM bills WHERE location = $1',
    [location]
  );
  return (result.rows[0]?.max_no || 0) + 1;
}

async function getBill(location, billNo) {
  const result = await getPool().query(
    'SELECT * FROM bills WHERE location = $1 AND bill_no = $2 LIMIT 1',
    [location, billNo]
  );
  return result.rows[0] || null;
}

async function getPreviousBill(location, billNo) {
  const result = await getPool().query(
    `SELECT * FROM bills
     WHERE location = $1 AND bill_no < $2
     ORDER BY bill_no DESC
     LIMIT 1`,
    [location, billNo]
  );
  return result.rows[0] || null;
}

async function saveBill(bill) {
  const existing = await getPool().query(
    'SELECT id FROM bills WHERE location = $1 AND bill_no = $2 LIMIT 1',
    [bill.location, bill.billNo]
  );

  const itemsJson = JSON.stringify(bill.items);

  if (existing.rowCount > 0) {
    await getPool().query(
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
    await getPool().query(
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
}

async function getLedger(location, from, to) {
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
  const result = await getPool().query(sql, params);
  return result.rows;
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

module.exports = {
  initPostgres,
  loginUser,
  getNextBillNumber,
  getBill,
  getPreviousBill,
  saveBill,
  getLedger,
  mapBillRow,
};
