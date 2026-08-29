import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:sales/models/sale_bill.dart';

class LocalDb {
  static LocalDb? _instance;

  Database? _database;

  LocalDb._();

  static LocalDb get instance {
    _instance ??= LocalDb._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sales_local.db');

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
    var localId = const Uuid().v4();
    var db = await database;

    await db.insert('bills', {
      'local_id': localId,
      'bill_no': bill.billNo,
      'location': bill.location,
      'payload': jsonEncode(bill.toJson()),
      'sync_status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    return localId;
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

  Future<void> markBillSynced(String localId) async {
    var db = await database;
    await db.update(
      'bills',
      {'sync_status': 'synced'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
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
