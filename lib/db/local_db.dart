import 'dart:convert';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

/// Summary row for the sales ledger (totals only — no line items).
class LedgerEntry {
  final String localId;
  final int billNo;
  final String location;
  final String date;
  final String customerName;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;
  final String syncStatus;
  final DateTime updatedAt;

  const LedgerEntry({
    required this.localId,
    required this.billNo,
    required this.location,
    required this.date,
    required this.customerName,
    required this.paymentMode,
    required this.total,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
    required this.syncStatus,
    required this.updatedAt,
  });
}

class LocalDb {
  static LocalDb? _instance;

  /// When set, [LocalDb] uses this directory instead of the app support dir.
  /// For unit tests only.
  static String? testSupportDirectory;

  Database? _database;

  LocalDb._();

  static LocalDb get instance {
    _instance ??= LocalDb._();
    return _instance!;
  }

  Future<String> _resolveSupportDirectory() async {
    final testDir = testSupportDirectory;
    if (testDir != null && testDir.isNotEmpty) {
      return testDir;
    }
    var supportDir = await getApplicationSupportDirectory();
    return supportDir.path;
  }

  Future<void> initialize() async {
    await database;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Clears the singleton — for unit tests only.
  static void resetForTest() {
    _instance = null;
    testSupportDirectory = null;
  }

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final supportPath = await _resolveSupportDirectory();
    var path = join(supportPath, '${AppConfig.locationCode}_sales.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV2Schema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
      },
    );
  }

  Future<void> _createV2Schema(Database db) async {
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
        created_at TEXT NOT NULL,
        UNIQUE (bill_no, location)
      )
    ''');

    await db.execute('''
      CREATE TABLE location_counters (
        location TEXT PRIMARY KEY,
        next_bill_no INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE location_sync_state (
        location TEXT PRIMARY KEY,
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

  Future<void> _migrateV1ToV2(Database db) async {
    await db.execute('ALTER TABLE bills RENAME TO bills_v1');

    await _createV2Schema(db);

    var oldRows = await db.query('bills_v1');
    for (var row in oldRows) {
      try {
        var payload = jsonDecode(row['payload'] as String)
            as Map<String, dynamic>;
        var bill = SaleBill.fromJson(payload);
        var now = row['created_at'] as String? ?? DateTime.now().toIso8601String();

        await db.insert('bills', _billToRow(
          localId: row['local_id'] as String,
          bill: bill,
          syncStatus: row['sync_status'] as String? ?? 'pending',
          createdAt: now,
          updatedAt: now,
        ));
      } catch (_) {
        // Skip rows that cannot be migrated.
      }
    }

    await db.execute('DROP TABLE bills_v1');

    // Seed counters from migrated bill numbers.
    var maxRows = await db.rawQuery(
      'SELECT location, MAX(bill_no) AS max_no FROM bills GROUP BY location',
    );
    for (var row in maxRows) {
      var location = row['location'] as String;
      var maxNo = (row['max_no'] as num?)?.toInt() ?? 0;
      await db.insert(
        'location_counters',
        {'location': location, 'next_bill_no': maxNo + 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Bill numbering (per-location counter — no server reservation)
  // ---------------------------------------------------------------------------

  /// Allocates and returns the next bill number for [location], atomically
  /// incrementing the per-location counter.
  Future<int> getNextBillNumber(String location) async {
    var db = await database;

    return db.transaction((txn) async {
      var rows = await txn.query(
        'location_counters',
        where: 'location = ?',
        whereArgs: [location],
        limit: 1,
      );

      if (rows.isEmpty) {
        await txn.insert('location_counters', {
          'location': location,
          'next_bill_no': 2,
        });
        return 1;
      }

      var next = (rows.first['next_bill_no'] as num).toInt();
      await txn.update(
        'location_counters',
        {'next_bill_no': next + 1},
        where: 'location = ?',
        whereArgs: [location],
      );
      return next;
    });
  }

  // ---------------------------------------------------------------------------
  // Auto-pull timestamp (per location)
  // ---------------------------------------------------------------------------

  Future<DateTime?> getLastPullAt(String location) async {
    var db = await database;
    var rows = await db.query(
      'location_sync_state',
      where: 'location = ?',
      whereArgs: [location],
      limit: 1,
    );

    if (rows.isEmpty || rows.first['last_pull_at'] == null) {
      return null;
    }

    return DateTime.tryParse(rows.first['last_pull_at'] as String);
  }

  Future<void> setLastPullAt(String location, DateTime value) async {
    var db = await database;
    await db.insert(
      'location_sync_state',
      {
        'location': location,
        'last_pull_at': value.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // CRUD — bills
  // ---------------------------------------------------------------------------

  /// Inserts a bill. Uses [ConflictAlgorithm.abort] on (bill_no, location) so
  /// numbering bugs fail loudly instead of silently overwriting.
  Future<String> insertBill(
    SaleBill bill, {
    String syncStatus = 'pending',
  }) async {
    var localId = const Uuid().v4();
    var now = DateTime.now().toIso8601String();
    var db = await database;

    await db.insert(
      'bills',
      _billToRow(
        localId: localId,
        bill: bill,
        syncStatus: syncStatus,
        createdAt: now,
        updatedAt: now,
      ),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return localId;
  }

  Future<List<Map<String, dynamic>>> getBillsBySyncStatus(
    String syncStatus, {
    String? location,
  }) async {
    var db = await database;

    if (location != null) {
      return db.query(
        'bills',
        where: 'sync_status = ? AND location = ?',
        whereArgs: [syncStatus, location],
        orderBy: 'bill_no ASC',
      );
    }

    return db.query(
      'bills',
      where: 'sync_status = ?',
      whereArgs: [syncStatus],
      orderBy: 'bill_no ASC',
    );
  }

  Future<void> markSynced(String localId) async {
    var db = await database;
    await db.update(
      'bills',
      {
        'sync_status': 'synced',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<SaleBill?> getBillByNumber({
    required String location,
    required int billNo,
  }) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      where: 'location = ? AND bill_no = ?',
      whereArgs: [location, billNo],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return billFromRow(rows.first);
  }

  /// Returns the bill with the highest [bill_no] strictly less than [billNo]
  /// for [location], or null if none exists.
  Future<SaleBill?> getPreviousBill({
    required String location,
    required int billNo,
  }) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      where: 'location = ? AND bill_no < ?',
      whereArgs: [location, billNo],
      orderBy: 'bill_no DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return billFromRow(rows.first);
  }

  Future<List<LedgerEntry>> getLedgerEntries(
    String location, {
    String? from,
    String? to,
  }) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'bill_no DESC',
    );

    var entries = <LedgerEntry>[];

    for (var row in rows) {
      var date = row['bill_date'] as String;
      if (!_isWithinDateRange(date, from: from, to: to)) {
        continue;
      }

      entries.add(LedgerEntry(
        localId: row['local_id'] as String,
        billNo: (row['bill_no'] as num).toInt(),
        location: row['location'] as String,
        date: date,
        customerName: row['customer_name'] as String? ?? '',
        paymentMode: row['payment_mode'] as String? ?? 'CASH',
        total: (row['total_amount'] as num).toDouble(),
        cgst: (row['total_cgst'] as num).toDouble(),
        sgst: (row['total_sgst'] as num).toDouble(),
        igst: (row['total_igst'] as num).toDouble(),
        grandTotal: (row['grand_total'] as num).toDouble(),
        syncStatus: row['sync_status'] as String? ?? 'pending',
        updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
            DateTime.now(),
      ));
    }

    return entries;
  }

  Future<SaleBill?> getBillByLocalId(String localId) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return billFromRow(rows.first);
  }

  // ---------------------------------------------------------------------------
  // JSON round-trip helpers
  // ---------------------------------------------------------------------------

  /// Encodes [items] as valid JSON (not Dart's [List.toString]).
  static String encodeItemsJson(List<BillItem> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }

  /// Parses [itemsJson] back into [BillItem] list. Must round-trip with
  /// [encodeItemsJson] without losing line items.
  static List<BillItem> parseItemsJson(String itemsJson) {
    final decoded = jsonDecode(itemsJson);
    if (decoded is! List) {
      return [];
    }

    return decoded
        .map((e) => BillItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Reconstructs a [SaleBill] from a database row, including parsed items.
  SaleBill billFromRow(Map<String, dynamic> row) {
    return SaleBill(
      billNo: (row['bill_no'] as num).toInt(),
      location: row['location'] as String,
      billDate: _parseBillDate(row['bill_date'] as String),
      paymentMode: row['payment_mode'] as String? ?? 'CASH',
      customerName: row['customer_name'] as String? ?? '',
      mobile: row['mobile'] as String? ?? '',
      items: parseItemsJson(row['items_json'] as String),
      totalQty: (row['total_qty'] as num).toDouble(),
      totalAmount: (row['total_amount'] as num).toDouble(),
      totalCgst: (row['total_cgst'] as num).toDouble(),
      totalSgst: (row['total_sgst'] as num).toDouble(),
      totalIgst: (row['total_igst'] as num).toDouble(),
      grandTotal: (row['grand_total'] as num).toDouble(),
    );
  }

  Map<String, Object?> _billToRow({
    required String localId,
    required SaleBill bill,
    required String syncStatus,
    required String createdAt,
    required String updatedAt,
  }) {
    return {
      'local_id': localId,
      'bill_no': bill.billNo,
      'location': bill.location,
      'bill_date': _formatBillDate(bill.billDate),
      'payment_mode': bill.paymentMode,
      'customer_name': bill.customerName,
      'mobile': bill.mobile,
      'items_json': encodeItemsJson(bill.items),
      'total_qty': bill.totalQty,
      'total_amount': bill.totalAmount,
      'total_cgst': bill.totalCgst,
      'total_sgst': bill.totalSgst,
      'total_igst': bill.totalIgst,
      'grand_total': bill.grandTotal,
      'sync_status': syncStatus,
      'updated_at': updatedAt,
      'created_at': createdAt,
    };
  }

  static String _formatBillDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime _parseBillDate(String value) {
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

  static bool _isWithinDateRange(
    String date, {
    String? from,
    String? to,
  }) {
    if (from == null && to == null) {
      return true;
    }

    try {
      var value = DateTime.parse(date);

      if (from != null) {
        var fromDate = DateTime.parse(from);
        if (value.isBefore(fromDate)) {
          return false;
        }
      }

      if (to != null) {
        var toDate = DateTime.parse(to);
        if (value.isAfter(toDate)) {
          return false;
        }
      }
    } catch (_) {
      return true;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Legacy helpers — kept so existing callers compile until later phases
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

  Future<List<Map<String, dynamic>>> getPendingBills() {
    return getBillsBySyncStatus('pending');
  }

  Future<List<Map<String, dynamic>>> getBillsForLedger({
    required String location,
  }) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'bill_no DESC',
    );

    // Legacy callers expect a `payload` JSON column.
    return rows.map((row) {
      final bill = billFromRow(row);
      return {
        'local_id': row['local_id'],
        'bill_no': row['bill_no'],
        'location': row['location'],
        'sync_status': row['sync_status'],
        'created_at': row['created_at'],
        'payload': jsonEncode(bill.toJson()),
      };
    }).toList();
  }

  Future<void> markBillSynced(String localId) => markSynced(localId);

  Future<void> deleteBill(String localId) async {
    var db = await database;
    await db.delete(
      'bills',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateSavedBill(String localId, SaleBill bill) async {
    var db = await database;
    var now = DateTime.now().toIso8601String();

    await db.update(
      'bills',
      {
        'bill_no': bill.billNo,
        'location': bill.location,
        'bill_date': _formatBillDate(bill.billDate),
        'payment_mode': bill.paymentMode,
        'customer_name': bill.customerName,
        'mobile': bill.mobile,
        'items_json': encodeItemsJson(bill.items),
        'total_qty': bill.totalQty,
        'total_amount': bill.totalAmount,
        'total_cgst': bill.totalCgst,
        'total_sgst': bill.totalSgst,
        'total_igst': bill.totalIgst,
        'grand_total': bill.grandTotal,
        'sync_status': 'pending',
        'updated_at': now,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
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
    var db = await database;

    for (var entry in entries) {
      var existing = await db.query(
        'bills',
        where: 'location = ? AND bill_no = ?',
        whereArgs: [location, entry.billNo],
        limit: 1,
      );

      if (existing.isNotEmpty &&
          existing.first['sync_status'] == 'pending') {
        continue;
      }

      var now = DateTime.now().toIso8601String();

      if (existing.isNotEmpty) {
        await db.update(
          'bills',
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
          'items_json': encodeItemsJson([]),
          'total_qty': 0,
          'total_amount': entry.total,
          'total_cgst': entry.cgst,
          'total_sgst': entry.sgst,
          'total_igst': entry.igst,
          'grand_total': entry.grandTotal,
          'sync_status': 'synced',
          'updated_at': now,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<String?> findLocalIdByBillNo({
    required String location,
    required int billNo,
  }) async {
    var db = await database;
    var rows = await db.query(
      'bills',
      columns: ['local_id'],
      where: 'location = ? AND bill_no = ?',
      whereArgs: [location, billNo],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['local_id'] as String;
  }

  Future<void> replaceGstMaster(List<Map<String, String>> rows) async {
    var db = await database;

    await db.transaction((txn) async {
      await txn.delete('gst_master_staging');

      for (var row in rows) {
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
    var db = await database;
    var existing = await db.query(
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

    var updates = <String, dynamic>{};
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
}
