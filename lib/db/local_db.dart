import 'dart:convert';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

/// A bill row joined with its local metadata for reads.
class StoredBill {
  final String localId;
  final SaleBill bill;
  final String syncStatus;
  final String updatedAt;

  const StoredBill({
    required this.localId,
    required this.bill,
    required this.syncStatus,
    required this.updatedAt,
  });
}

/// Summary row for ledger listings (no line items).
class LocalLedgerEntry {
  final String localId;
  final int billNo;
  final String location;
  final String billDate;
  final String paymentMode;
  final String customerName;
  final String mobile;
  final double totalQty;
  final double totalAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double grandTotal;
  final String syncStatus;
  final String updatedAt;

  const LocalLedgerEntry({
    required this.localId,
    required this.billNo,
    required this.location,
    required this.billDate,
    required this.paymentMode,
    required this.customerName,
    required this.mobile,
    required this.totalQty,
    required this.totalAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.grandTotal,
    required this.syncStatus,
    required this.updatedAt,
  });
}

class LocalDb {
  static LocalDb? _instance;

  Database? _database;

  LocalDb._();

  static LocalDb get instance {
    _instance ??= LocalDb._();
    return _instance!;
  }

  static const int _dbVersion = 2;

  Future<void> initialize() async {
    await database;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  // ---------------------------------------------------------------------------
  // Phase 1 CRUD
  // ---------------------------------------------------------------------------

  /// Inserts a bill. Uses [ConflictAlgorithm.abort] on (bill_no, location) so
  /// numbering bugs fail loudly instead of silently overwriting.
  Future<String> insertBill(
    SaleBill bill, {
    String syncStatus = 'pending',
  }) async {
    final localId = const Uuid().v4();
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'bills',
      _billToRow(bill, localId: localId, syncStatus: syncStatus, updatedAt: now),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await _advanceNextBillNo(bill.location, bill.billNo);
    return localId;
  }

  Future<List<StoredBill>> getBillsBySyncStatus(
    String syncStatus, {
    String? location,
  }) async {
    final db = await database;
    final where = location == null
        ? 'sync_status = ?'
        : 'sync_status = ? AND location = ?';
    final whereArgs =
        location == null ? [syncStatus] : [syncStatus, location];

    final rows = await db.query(
      'bills',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'bill_no ASC',
    );

    return rows
        .map(_rowToStoredBill)
        .whereType<StoredBill>()
        .toList(growable: false);
  }

  Future<void> markSynced(String localId) async {
    final db = await database;
    await db.update(
      'bills',
      {
        'sync_status': 'synced',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<StoredBill?> getBillByNumber({
    required String location,
    required int billNo,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'location = ? AND bill_no = ?',
      whereArgs: [location, billNo],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _rowToStoredBill(rows.first);
  }

  /// Returns the bill with the highest bill_no strictly less than [beforeBillNo].
  Future<StoredBill?> getPreviousBill({
    required String location,
    required int beforeBillNo,
  }) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'location = ? AND bill_no < ?',
      whereArgs: [location, beforeBillNo],
      orderBy: 'bill_no DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _rowToStoredBill(rows.first);
  }

  Future<List<LocalLedgerEntry>> getLedgerEntries(
    String location, {
    String? from,
    String? to,
  }) async {
    final db = await database;
    final whereParts = <String>['location = ?'];
    final whereArgs = <Object?>[location];

    if (from != null) {
      whereParts.add('bill_date >= ?');
      whereArgs.add(from);
    }
    if (to != null) {
      whereParts.add('bill_date <= ?');
      whereArgs.add(to);
    }

    final rows = await db.query(
      'bills',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'bill_no DESC',
    );

    return rows
        .map(_rowToLedgerEntry)
        .whereType<LocalLedgerEntry>()
        .toList(growable: false);
  }

  /// Parses [items_json] back into [BillItem] list. Must round-trip with
  /// [jsonEncode] used on insert — line items must not be lost on read.
  static List<BillItem> parseBillItems(String itemsJson) {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .map((entry) => BillItem.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Per-location counters / sync metadata (Phase 1 schema)
  // ---------------------------------------------------------------------------

  Future<int> getNextBillNumber(String location) async {
    await _ensureLocationMeta(location);
    final db = await database;
    final rows = await db.query(
      'location_meta',
      columns: ['next_bill_no'],
      where: 'location = ?',
      whereArgs: [location],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 1;
    }

    return (rows.first['next_bill_no'] as num).toInt();
  }

  Future<DateTime?> getLastPullAt(String location) async {
    await _ensureLocationMeta(location);
    final db = await database;
    final rows = await db.query(
      'location_meta',
      columns: ['last_pull_at'],
      where: 'location = ?',
      whereArgs: [location],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final raw = rows.first['last_pull_at'] as String?;
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }

  Future<void> setLastPullAt(String location, DateTime timestamp) async {
    await _ensureLocationMeta(location);
    final db = await database;
    await db.update(
      'location_meta',
      {'last_pull_at': timestamp.toUtc().toIso8601String()},
      where: 'location = ?',
      whereArgs: [location],
    );
  }

  // ---------------------------------------------------------------------------
  // Backward-compatible shims (removed in later phases as callers migrate)
  // ---------------------------------------------------------------------------

  Future<String> insertPendingBill(SaleBill bill) {
    return insertBill(bill, syncStatus: 'pending');
  }

  Future<String> insertSavedBill(
    SaleBill bill, {
    required String syncStatus,
  }) {
    return insertBill(bill, syncStatus: syncStatus);
  }

  Future<List<Map<String, dynamic>>> getPendingBills() async {
    final stored = await getBillsBySyncStatus('pending');
    return stored.map(_storedBillToLegacyRow).toList(growable: false);
  }

  Future<void> markBillSynced(String localId) => markSynced(localId);

  Future<List<Map<String, dynamic>>> getBillsForLedger({
    required String location,
  }) async {
    final entries = await getLedgerEntries(location);
    return entries.map(_ledgerEntryToLegacyRow).toList(growable: false);
  }

  Future<SaleBill?> getBillByLocalId(String localId) async {
    final db = await database;
    final rows = await db.query(
      'bills',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _rowToStoredBill(rows.first)?.bill;
  }

  Future<void> deleteBill(String localId) async {
    final db = await database;
    await db.delete(
      'bills',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateSavedBill(String localId, SaleBill bill) async {
    final db = await database;
    await db.update(
      'bills',
      {
        'bill_no': bill.billNo,
        'location': bill.location,
        'bill_date': _formatDate(bill.billDate),
        'payment_mode': bill.paymentMode,
        'customer_name': bill.customerName,
        'mobile': bill.mobile,
        'items_json': jsonEncode(bill.items.map((e) => e.toJson()).toList()),
        'total_qty': bill.totalQty,
        'total_amount': bill.totalAmount,
        'total_cgst': bill.totalCgst,
        'total_sgst': bill.totalSgst,
        'total_igst': bill.totalIgst,
        'grand_total': bill.grandTotal,
        'sync_status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<String?> findLocalIdByBillNo({
    required String location,
    required int billNo,
  }) async {
    final stored = await getBillByNumber(location: location, billNo: billNo);
    return stored?.localId;
  }

  Future<void> mergeLedgerFromServer({
    required String location,
    required List<({
      int billNo,
      String date,
      String paymentMode,
      double total,
      double cgst,
      double sgst,
      double igst,
      double grandTotal,
    })> entries,
  }) async {
    final db = await database;

    for (final entry in entries) {
      final existing = await db.query(
        'bills',
        where: 'location = ? AND bill_no = ?',
        whereArgs: [location, entry.billNo],
        limit: 1,
      );

      if (existing.isNotEmpty &&
          existing.first['sync_status'] == 'pending') {
        continue;
      }

      final now = DateTime.now().toUtc().toIso8601String();

      if (existing.isNotEmpty) {
        await db.update(
          {
            'bill_date': entry.date,
            'payment_mode': entry.paymentMode,
            'total_amount': entry.total,
            'total_cgst': entry.cgst,
            'total_sgst': entry.sgst,
            'total_igst': entry.igst,
            'grand_total': entry.grandTotal,
            'sync_status': 'synced',
            'updated_at': now,
          },
          where: 'local_id = ?',
          whereArgs: [existing.first['local_id']],
        );
        continue;
      }

      await db.insert(
        'bills',
        {
          'local_id': const Uuid().v4(),
          'bill_no': entry.billNo,
          'location': location,
          'bill_date': entry.date,
          'payment_mode': entry.paymentMode,
          'customer_name': '',
          'mobile': '',
          'items_json': jsonEncode(<Map<String, dynamic>>[]),
          'total_qty': 0,
          'total_amount': entry.total,
          'total_cgst': entry.cgst,
          'total_sgst': entry.sgst,
          'total_igst': entry.igst,
          'grand_total': entry.grandTotal,
          'sync_status': 'synced',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<void> replaceGstMaster(List<Map<String, String>> rows) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('gst_master_staging');

      for (final row in rows) {
        await txn.insert('gst_master_staging', row);
      }

      await txn.delete('gst_master');

      await txn.rawInsert(
        'INSERT INTO gst_master (key, value) '
        'SELECT key, value FROM gst_master_staging',
      );

      await txn.delete('gst_master_staging');
    });
  }

  Future<void> updateSyncMeta({
    required String location,
    String? expectedDbName,
    String? lastGstVersion,
  }) async {
    final db = await database;
    final existing = await db.query(
      'sync_meta',
      where: 'location = ?',
      whereArgs: [location],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('sync_meta', {
        'location': location,
        'expected_db_name': expectedDbName,
        'last_gst_version': lastGstVersion,
      });
      return;
    }

    final updates = <String, dynamic>{};
    if (expectedDbName != null) {
      updates['expected_db_name'] = expectedDbName;
    }
    if (lastGstVersion != null) {
      updates['last_gst_version'] = lastGstVersion;
    }

    if (updates.isEmpty) {
      return;
    }

    await db.update(
      'sync_meta',
      updates,
      where: 'location = ?',
      whereArgs: [location],
    );
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  Future<Database> _initDb() async {
    final supportDir = await getApplicationSupportDirectory();
    final path = join(supportDir.path, '${AppConfig.locationCode}_sales.db');

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        local_id TEXT PRIMARY KEY,
        bill_no INTEGER NOT NULL,
        location TEXT NOT NULL,
        bill_date TEXT NOT NULL,
        payment_mode TEXT NOT NULL,
        customer_name TEXT NOT NULL DEFAULT '',
        mobile TEXT NOT NULL DEFAULT '',
        items_json TEXT NOT NULL,
        total_qty REAL NOT NULL,
        total_amount REAL NOT NULL,
        total_cgst REAL NOT NULL,
        total_sgst REAL NOT NULL,
        total_igst REAL NOT NULL,
        grand_total REAL NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL,
        UNIQUE (bill_no, location)
      )
    ''');

    await db.execute('''
      CREATE TABLE location_meta (
        location TEXT PRIMARY KEY,
        next_bill_no INTEGER NOT NULL DEFAULT 1,
        last_pull_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE gst_master (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE gst_master_staging (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_meta (
        location TEXT PRIMARY KEY,
        expected_db_name TEXT,
        last_gst_version TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateV1ToV2(db);
    }
  }

  Future<void> _migrateV1ToV2(Database db) async {
    final hasPayloadColumn = await _tableHasColumn(db, 'bills', 'payload');
    if (!hasPayloadColumn) {
      return;
    }

    final oldRows = await db.query('bills');
    await db.execute('DROP TABLE IF EXISTS bills');

    await db.execute('''
      CREATE TABLE bills (
        local_id TEXT PRIMARY KEY,
        bill_no INTEGER NOT NULL,
        location TEXT NOT NULL,
        bill_date TEXT NOT NULL,
        payment_mode TEXT NOT NULL,
        customer_name TEXT NOT NULL DEFAULT '',
        mobile TEXT NOT NULL DEFAULT '',
        items_json TEXT NOT NULL,
        total_qty REAL NOT NULL,
        total_amount REAL NOT NULL,
        total_cgst REAL NOT NULL,
        total_sgst REAL NOT NULL,
        total_igst REAL NOT NULL,
        grand_total REAL NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        updated_at TEXT NOT NULL,
        UNIQUE (bill_no, location)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS location_meta (
        location TEXT PRIMARY KEY,
        next_bill_no INTEGER NOT NULL DEFAULT 1,
        last_pull_at TEXT
      )
    ''');

    var maxBillNoByLocation = <String, int>{};

    for (final row in oldRows) {
      try {
        final payload = jsonDecode(row['payload'] as String)
            as Map<String, dynamic>;
        final bill = SaleBill.fromJson(payload);
        final localId = row['local_id'] as String? ?? const Uuid().v4();
        final syncStatus = row['sync_status'] as String? ?? 'pending';
        final updatedAt = row['created_at'] as String? ??
            DateTime.now().toUtc().toIso8601String();

        await db.insert(
          'bills',
          _billToRow(
            bill,
            localId: localId,
            syncStatus: syncStatus,
            updatedAt: updatedAt,
          ),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final currentMax = maxBillNoByLocation[bill.location] ?? 0;
        if (bill.billNo > currentMax) {
          maxBillNoByLocation[bill.location] = bill.billNo;
        }
      } catch (_) {
        // Skip rows that cannot be migrated.
      }
    }

    for (final entry in maxBillNoByLocation.entries) {
      await db.insert(
        'location_meta',
        {
          'location': entry.key,
          'next_bill_no': entry.value + 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<bool> _tableHasColumn(
    Database db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> _ensureLocationMeta(String location) async {
    final db = await database;
    final rows = await db.query(
      'location_meta',
      where: 'location = ?',
      whereArgs: [location],
      limit: 1,
    );

    if (rows.isEmpty) {
      await db.insert('location_meta', {
        'location': location,
        'next_bill_no': 1,
      });
    }
  }

  Future<void> _advanceNextBillNo(String location, int usedBillNo) async {
    await _ensureLocationMeta(location);
    final db = await database;
    final next = usedBillNo + 1;

    await db.rawUpdate(
      '''
      UPDATE location_meta
      SET next_bill_no = MAX(next_bill_no, ?)
      WHERE location = ?
      ''',
      [next, location],
    );
  }

  static Map<String, Object?> _billToRow(
    SaleBill bill, {
    required String localId,
    required String syncStatus,
    required String updatedAt,
  }) {
    return {
      'local_id': localId,
      'bill_no': bill.billNo,
      'location': bill.location,
      'bill_date': _formatDate(bill.billDate),
      'payment_mode': bill.paymentMode,
      'customer_name': bill.customerName,
      'mobile': bill.mobile,
      'items_json': jsonEncode(bill.items.map((e) => e.toJson()).toList()),
      'total_qty': bill.totalQty,
      'total_amount': bill.totalAmount,
      'total_cgst': bill.totalCgst,
      'total_sgst': bill.totalSgst,
      'total_igst': bill.totalIgst,
      'grand_total': bill.grandTotal,
      'sync_status': syncStatus,
      'updated_at': updatedAt,
    };
  }

  static StoredBill? _rowToStoredBill(Map<String, dynamic> row) {
    try {
      final itemsJson = row['items_json'] as String? ?? '[]';
      return StoredBill(
        localId: row['local_id'] as String,
        bill: SaleBill(
          billNo: (row['bill_no'] as num).toInt(),
          location: row['location'] as String,
          billDate: _parseDate(row['bill_date'] as String),
          paymentMode: row['payment_mode'] as String? ?? 'CASH',
          customerName: row['customer_name'] as String? ?? '',
          mobile: row['mobile'] as String? ?? '',
          items: parseBillItems(itemsJson),
          totalQty: (row['total_qty'] as num).toDouble(),
          totalAmount: (row['total_amount'] as num).toDouble(),
          totalCgst: (row['total_cgst'] as num).toDouble(),
          totalSgst: (row['total_sgst'] as num).toDouble(),
          totalIgst: (row['total_igst'] as num).toDouble(),
          grandTotal: (row['grand_total'] as num).toDouble(),
        ),
        syncStatus: row['sync_status'] as String? ?? 'pending',
        updatedAt: row['updated_at'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static LocalLedgerEntry? _rowToLedgerEntry(Map<String, dynamic> row) {
    try {
      return LocalLedgerEntry(
        localId: row['local_id'] as String,
        billNo: (row['bill_no'] as num).toInt(),
        location: row['location'] as String,
        billDate: row['bill_date'] as String,
        paymentMode: row['payment_mode'] as String? ?? 'CASH',
        customerName: row['customer_name'] as String? ?? '',
        mobile: row['mobile'] as String? ?? '',
        totalQty: (row['total_qty'] as num).toDouble(),
        totalAmount: (row['total_amount'] as num).toDouble(),
        totalCgst: (row['total_cgst'] as num).toDouble(),
        totalSgst: (row['total_sgst'] as num).toDouble(),
        totalIgst: (row['total_igst'] as num).toDouble(),
        grandTotal: (row['grand_total'] as num).toDouble(),
        syncStatus: row['sync_status'] as String? ?? 'pending',
        updatedAt: row['updated_at'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _storedBillToLegacyRow(StoredBill stored) {
    return {
      'local_id': stored.localId,
      'bill_no': stored.bill.billNo,
      'location': stored.bill.location,
      'payload': jsonEncode(stored.bill.toJson()),
      'sync_status': stored.syncStatus,
      'created_at': stored.updatedAt,
    };
  }

  static Map<String, dynamic> _ledgerEntryToLegacyRow(LocalLedgerEntry entry) {
    return {
      'local_id': entry.localId,
      'bill_no': entry.billNo,
      'location': entry.location,
      'payload': jsonEncode({
        'billNo': entry.billNo,
        'location': entry.location,
        'billDate': entry.billDate,
        'paymentMode': entry.paymentMode,
        'customerName': entry.customerName,
        'mobile': entry.mobile,
        'items': <Map<String, dynamic>>[],
        'totalQty': entry.totalQty,
        'totalAmount': entry.totalAmount,
        'totalCgst': entry.totalCgst,
        'totalSgst': entry.totalSgst,
        'totalIgst': entry.totalIgst,
        'grandTotal': entry.grandTotal,
      }),
      'sync_status': entry.syncStatus,
      'created_at': entry.updatedAt,
    };
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    return DateTime.tryParse(value) ?? DateTime.now();
  }
}
