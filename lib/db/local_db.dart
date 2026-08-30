import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/models/sale_bill.dart';

class LocalDb {
  static LocalDb? _instance;

  Database? _database;

  LocalDb._();

  static LocalDb get instance {
    _instance ??= LocalDb._();
    return _instance!;
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

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    var dbPath = await getDatabasesPath();
    var path = join(dbPath, '${AppConfig.locationCode}_sales.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bills (
            local_id TEXT PRIMARY KEY,
            bill_no INTEGER,
            location TEXT,
            payload TEXT,
            sync_status TEXT DEFAULT 'pending',
            created_at TEXT
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
      },
    );
  }

  Future<String> insertPendingBill(SaleBill bill) async {
    return insertSavedBill(bill, syncStatus: 'pending');
  }

  Future<String> insertSavedBill(
    SaleBill bill, {
    required String syncStatus,
  }) async {
    var localId = const Uuid().v4();
    var db = await database;

    await db.insert('bills', {
      'local_id': localId,
      'bill_no': bill.billNo,
      'location': bill.location,
      'payload': jsonEncode(bill.toJson()),
      'sync_status': syncStatus,
      'created_at': DateTime.now().toIso8601String(),
    });

    return localId;
  }

  Future<int> getNextBillNumber(String location) async {
    var db = await database;
    var result = await db.rawQuery(
      'SELECT MAX(bill_no) AS max_no FROM bills WHERE location = ?',
      [location],
    );

    var maxNo = result.first['max_no'];
    if (maxNo == null) {
      return 1;
    }

    return (maxNo as num).toInt() + 1;
  }

  Future<List<Map<String, dynamic>>> getPendingBills() async {
    var db = await database;
    return db.query(
      'bills',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getBillsForLedger({
    required String location,
  }) async {
    var db = await database;
    return db.query(
      'bills',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'bill_no DESC',
    );
  }

  Future<void> markBillSynced(String localId) async {
    var db = await database;
    await db.update(
      'bills',
      {'sync_status': 'synced'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
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

    try {
      var payload = jsonDecode(rows.first['payload'] as String)
          as Map<String, dynamic>;
      return SaleBill.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

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
    await db.update(
      'bills',
      {
        'payload': jsonEncode(bill.toJson()),
        'sync_status': 'pending',
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

      var payload = jsonEncode({
        'billNo': entry.billNo,
        'location': location,
        'billDate': entry.date,
        'paymentMode': entry.paymentMode,
        'customerName': '',
        'mobile': '',
        'items': <Map<String, dynamic>>[],
        'totalQty': 0,
        'totalAmount': entry.total,
        'totalCgst': entry.cgst,
        'totalSgst': entry.sgst,
        'totalIgst': entry.igst,
        'grandTotal': entry.grandTotal,
      });

      if (existing.isEmpty) {
        await db.insert('bills', {
          'local_id': const Uuid().v4(),
          'bill_no': entry.billNo,
          'location': location,
          'payload': payload,
          'sync_status': 'synced',
          'created_at': DateTime.now().toIso8601String(),
        });
        continue;
      }

      await db.update(
        'bills',
        {
          'payload': payload,
          'sync_status': 'synced',
        },
        where: 'local_id = ?',
        whereArgs: [existing.first['local_id']],
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
