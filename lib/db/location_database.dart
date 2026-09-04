import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';

/// Opens and reads per-location SQLite files used by admin views.
class LocationDatabase {
  static const int schemaVersion = 3;

  static Future<String> dbPathForLocationCode(String locationCode) async {
    final supportDir = await getApplicationSupportDirectory();
    return join(supportDir.path, '${locationCode.toLowerCase()}_sales.db');
  }

  static String displayNameForCode(String locationCode) {
    return displayNameForLocationCode(locationCode);
  }

  static Future<List<LocalLedgerEntry>> getLedgerEntries({
    required String location,
    String? from,
    String? to,
  }) async {
    final locationCode = _locationCodeFromDisplayName(location);
    final locationName = displayNameForLocationCode(locationCode);

    if (AppConfig.isLocationSet && AppConfig.locationCode == locationCode) {
      try {
        await LocalDb.instance.initialize();
        return LocalDb.instance.getLedgerEntries(
          locationName,
          from: from,
          to: to,
        );
      } catch (_) {
        return const [];
      }
    }

    return _readLedgerFromFile(
      locationCode: locationCode,
      locationName: locationName,
      from: from,
      to: to,
    );
  }

  static Future<bool> hasBills(String locationCode) async {
    final locationName = displayNameForLocationCode(locationCode);

    if (AppConfig.isLocationSet && AppConfig.locationCode == locationCode) {
      try {
        await LocalDb.instance.initialize();
        final db = await LocalDb.instance.database;
        final rows = await db.rawQuery(
          'SELECT COUNT(*) AS count FROM bills WHERE location = ? AND deleted = 0',
          [locationName],
        );
        return ((rows.first['count'] as num?)?.toInt() ?? 0) > 0;
      } catch (_) {
        return false;
      }
    }

    final path = await dbPathForLocationCode(locationCode);
    if (!await File(path).exists()) {
      return false;
    }

    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM bills WHERE location = ? AND deleted = 0',
        [locationName],
      );
      return ((rows.first['count'] as num?)?.toInt() ?? 0) > 0;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  }

  static Future<int> upsertImportedBills({
    required String locationCode,
    required List<ImportedBillRow> rows,
  }) async {
    if (rows.isEmpty) {
      return 0;
    }

    final locationName = displayNameForLocationCode(locationCode);
    final now = DateTime.now().toUtc().toIso8601String();
    var imported = 0;

    if (AppConfig.isLocationSet && AppConfig.locationCode == locationCode) {
      await LocalDb.instance.initialize();
      final db = await LocalDb.instance.database;

      await db.transaction((txn) async {
        imported = await _upsertRows(
          txn,
          locationName: locationName,
          rows: rows,
          now: now,
        );
        await _advanceNextBillNo(txn, locationName, rows);
      });

      return imported;
    }

    final path = await dbPathForLocationCode(locationCode);
    final db = await _openWritableDatabase(path);

    try {
      await db.transaction((txn) async {
        imported = await _upsertRows(
          txn,
          locationName: locationName,
          rows: rows,
          now: now,
        );
        await _advanceNextBillNo(txn, locationName, rows);
      });
    } finally {
      await db.close();
    }

    return imported;
  }

  static Future<List<LocalLedgerEntry>> _readLedgerFromFile({
    required String locationCode,
    required String locationName,
    String? from,
    String? to,
  }) async {
    final path = await dbPathForLocationCode(locationCode);
    if (!await File(path).exists()) {
      return const [];
    }

    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final whereParts = <String>['location = ?', 'deleted = 0'];
      final whereArgs = <Object?>[locationName];

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
    } finally {
      await db.close();
    }
  }

  static Future<int> _upsertRows(
    DatabaseExecutor txn,
    {
    required String locationName,
    required List<ImportedBillRow> rows,
    required String now,
  }) async {
    const chunkSize = 400;
    var imported = 0;

    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = start + chunkSize > rows.length
          ? rows.length
          : start + chunkSize;
      final chunk = rows.sublist(start, end);
      final batch = txn.batch();

      for (final row in chunk) {
        batch.insert(
          'bills',
          {
            'local_id': const Uuid().v4(),
            'bill_no': row.billNo,
            'location': locationName,
            'bill_date': row.billDate,
            'payment_mode': row.paymentMode,
            'customer_name': row.customerName,
            'mobile': row.mobile,
            'items_json': jsonEncode(<Map<String, dynamic>>[]),
            'total_qty': 0,
            'total_amount': row.totalAmount,
            'total_cgst': row.totalCgst,
            'total_sgst': row.totalSgst,
            'total_igst': row.totalIgst,
            'grand_total': row.grandTotal,
            'sync_status': 'synced',
            'updated_at': now,
            'deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      imported += chunk.length;
    }

    return imported;
  }

  static Future<void> _advanceNextBillNo(
    DatabaseExecutor txn,
    String locationName,
    List<ImportedBillRow> rows,
  ) async {
    final maxBillNo = rows.map((row) => row.billNo).reduce(
          (left, right) => left > right ? left : right,
        );
    final nextBillNo = maxBillNo + 1;

    final existing = await txn.query(
      'location_meta',
      where: 'location = ?',
      whereArgs: [locationName],
      limit: 1,
    );

    if (existing.isEmpty) {
      await txn.insert('location_meta', {
        'location': locationName,
        'next_bill_no': nextBillNo,
      });
      return;
    }

    final currentNext =
        (existing.first['next_bill_no'] as num?)?.toInt() ?? 1;
    if (nextBillNo > currentNext) {
      await txn.update(
        'location_meta',
        {'next_bill_no': nextBillNo},
        where: 'location = ?',
        whereArgs: [locationName],
      );
    }
  }

  static Future<Database> _openWritableDatabase(String path) async {
    return openDatabase(
      path,
      version: schemaVersion,
      singleInstance: false,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
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
        deleted INTEGER NOT NULL DEFAULT 0,
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

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      final columns = await db.rawQuery('PRAGMA table_info(bills)');
      final hasDeleted = columns.any((column) => column['name'] == 'deleted');
      if (!hasDeleted) {
        await db.execute(
          'ALTER TABLE bills ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
        );
      }
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
        syncStatus: row['sync_status'] as String? ?? 'synced',
        updatedAt: row['updated_at'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static String _locationCodeFromDisplayName(String location) {
    return locationCodeFromDisplayName(location);
  }
}

class ImportedBillRow {
  final int billNo;
  final String billDate;
  final String customerName;
  final String mobile;
  final String paymentMode;
  final double totalAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double grandTotal;

  const ImportedBillRow({
    required this.billNo,
    required this.billDate,
    required this.customerName,
    required this.mobile,
    required this.paymentMode,
    required this.totalAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.grandTotal,
  });
}
