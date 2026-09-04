#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const EXPECTED_HEADERS = [
  'BILLNO',
  'DATE',
  'NAME',
  'MOBILE',
  'CASH',
  'CARD/UPI',
  'TOTAL',
  'CGST',
  'SGST',
  'IGST',
  'GRAND TOTAL',
];

const LOCATION_MAP = {
  win1: 'Win1',
  bommasandra: 'Win1',
  win2: 'Win2',
  tippsandra: 'Win2',
  tippasandra: 'Win2',
  win3: 'Win3',
  garbhiv: 'Win3',
  grabhivapalya: 'Win3',
};

function usage() {
  console.log('Usage: node import-csv.js <location> <csv-file>');
  console.log('');
  console.log('Locations: win1 (Bommasandra), win2 (Tippasandra), win3 (Grabhivapalya)');
  console.log('');
  console.log('Example:');
  console.log('  DATABASE_URL=postgresql://... node import-csv.js win1 ./bommasandra_sales_report.csv');
  process.exit(1);
}

function resolveLocation(raw) {
  const key = String(raw || '').trim().toLowerCase();
  const location = LOCATION_MAP[key];
  if (!location) {
    throw new Error(`Unknown location "${raw}". Use win1, win2, or win3.`);
  }
  return location;
}

function splitCsvLine(line) {
  const values = [];
  let current = '';
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];

    if (char === '"') {
      const escaped = inQuotes && line[index + 1] === '"';
      if (escaped) {
        current += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === ',' && !inQuotes) {
      values.push(current);
      current = '';
      continue;
    }

    current += char;
  }

  values.push(current);
  return values;
}

function parseAmount(value) {
  const parsed = Number(String(value || '').trim());
  return Number.isFinite(parsed) ? parsed : 0;
}

function customerNameFromCsv(name) {
  const upper = String(name || '').trim().toUpperCase();
  if (!upper || upper === 'CASH' || upper === 'CARD' || upper === 'PPP') {
    return '';
  }
  return String(name || '').trim();
}

function paymentModeFromCsv({ cash, cardUpi, name }) {
  if (cash > 0 && cardUpi === 0) {
    return 'CASH';
  }

  const upper = String(name || '').trim().toUpperCase();
  if (upper === 'UPI' || upper === 'PPP') {
    return 'UPI';
  }

  return 'CARD';
}

function parseCsv(content) {
  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  if (lines.length === 0) {
    throw new Error('CSV file is empty');
  }

  const header = splitCsvLine(lines[0]).map((value) => value.trim().toUpperCase());
  if (header.length !== EXPECTED_HEADERS.length) {
    throw new Error('Unexpected CSV header. Expected sales report columns.');
  }

  for (let index = 0; index < EXPECTED_HEADERS.length; index += 1) {
    if (header[index] !== EXPECTED_HEADERS[index]) {
      throw new Error('Unexpected CSV header. Expected sales report columns.');
    }
  }

  const rows = [];
  let skipped = 0;

  for (const line of lines.slice(1)) {
    const values = splitCsvLine(line);
    if (values.length < EXPECTED_HEADERS.length) {
      skipped += 1;
      continue;
    }

    const billNo = Number.parseInt(values[0].trim(), 10);
    const billDate = values[1].trim();
    const name = values[2].trim();
    const mobile = values[3].trim();
    const cash = parseAmount(values[4]);
    const cardUpi = parseAmount(values[5]);
    const totalAmount = parseAmount(values[6]);
    const totalCgst = parseAmount(values[7]);
    const totalSgst = parseAmount(values[8]);
    const totalIgst = parseAmount(values[9]);
    const grandTotal = parseAmount(values[10]);

    if (!Number.isFinite(billNo) || billNo <= 0 || !billDate) {
      skipped += 1;
      continue;
    }

    rows.push({
      billNo,
      billDate,
      customerName: customerNameFromCsv(name),
      mobile,
      paymentMode: paymentModeFromCsv({ cash, cardUpi, name }),
      totalAmount,
      totalCgst,
      totalSgst,
      totalIgst,
      grandTotal,
    });
  }

  return { rows, skipped };
}

async function importRows(pool, location, rows) {
  const placeholderItem = JSON.stringify([
    {
      qty: 0,
      rate: 0,
      amount: 0,
      cgst: 0,
      sgst: 0,
      igst: 0,
    },
  ]);

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    for (const row of rows) {
      await client.query(
        `INSERT INTO bills (
          bill_no, location, bill_date, payment_mode, customer_name, mobile,
          total_qty, total_amount, total_cgst, total_sgst, total_igst, grand_total,
          items_json, deleted, updated_at
        ) VALUES ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,$10,$11,$12::jsonb,FALSE,NOW())
        ON CONFLICT (location, bill_no) DO UPDATE SET
          bill_date = EXCLUDED.bill_date,
          payment_mode = EXCLUDED.payment_mode,
          customer_name = EXCLUDED.customer_name,
          mobile = EXCLUDED.mobile,
          total_amount = EXCLUDED.total_amount,
          total_cgst = EXCLUDED.total_cgst,
          total_sgst = EXCLUDED.total_sgst,
          total_igst = EXCLUDED.total_igst,
          grand_total = EXCLUDED.grand_total,
          items_json = EXCLUDED.items_json,
          deleted = FALSE,
          updated_at = NOW()`,
        [
          row.billNo,
          location,
          row.billDate,
          row.paymentMode,
          row.customerName,
          row.mobile,
          row.totalAmount,
          row.totalCgst,
          row.totalSgst,
          row.totalIgst,
          row.grandTotal,
          placeholderItem,
        ]
      );
    }

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function main() {
  const [, , locationArg, csvPathArg] = process.argv;

  if (!locationArg || !csvPathArg) {
    usage();
  }

  if (!process.env.DATABASE_URL) {
    console.error('DATABASE_URL environment variable is required');
    process.exit(1);
  }

  const location = resolveLocation(locationArg);
  const csvPath = path.resolve(csvPathArg);

  if (!fs.existsSync(csvPath)) {
    console.error(`CSV file not found: ${csvPath}`);
    process.exit(1);
  }

  const content = fs.readFileSync(csvPath, 'utf8');
  const { rows, skipped } = parseCsv(content);

  if (rows.length === 0) {
    console.error('No bill rows found in CSV');
    process.exit(1);
  }

  const pool = new Pool({ connectionString: process.env.DATABASE_URL });

  try {
    await importRows(pool, location, rows);
    console.log(
      `Imported ${rows.length} bill(s) into ${location}` +
        (skipped > 0 ? ` (${skipped} row(s) skipped)` : '')
    );
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
