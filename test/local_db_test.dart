import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'win1_test';
const _testLocationName = 'Win1';

Future<String> _testDbPath() async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, '${_testLocationCode}_sales.db');
}

Future<void> _deleteTestDb() async {
  final path = await _testDbPath();
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<Database> _openV1Database(String path) {
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
    },
  );
}

Map<String, dynamic> _sampleBillJson({
  int billNo = 1,
  List<BillItem>? items,
}) {
  final lineItems = items ??
      [
        BillItem(qty: 2, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
        BillItem(qty: 1, rate: 50, cgstPct: 2.5, sgstPct: 2.5),
      ];

  return SaleBill(
    billNo: billNo,
    location: _testLocationName,
    billDate: DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: 'Test Customer',
    mobile: '9999999999',
    items: lineItems,
    totalQty: lineItems.fold(0.0, (sum, item) => sum + item.qty),
    totalAmount: lineItems.fold(0.0, (sum, item) => sum + item.amount),
    totalCgst: lineItems.fold(0.0, (sum, item) => sum + item.cgst),
    totalSgst: lineItems.fold(0.0, (sum, item) => sum + item.sgst),
    totalIgst: 0,
    grandTotal: lineItems.fold(0.0, (sum, item) => sum + item.netAmt),
  ).toJson();
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('local_db_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation(_testLocationCode);
    await LocalDb.resetForTesting();
    await _deleteTestDb();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  group('LocalDb CRUD', () {
    test('insertBill round-trips line items via items_json', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final bill = SaleBill.fromJson(_sampleBillJson());
      final localId = await db.insertBill(bill);

      final stored = await db.getBillByNumber(
        location: _testLocationName,
        billNo: bill.billNo,
      );

      expect(stored, isNotNull);
      expect(stored!.localId, localId);
      expect(stored.bill.items.length, bill.items.length);
      expect(stored.bill.items[0].qty, bill.items[0].qty);
      expect(stored.bill.items[0].rate, bill.items[0].rate);
      expect(stored.bill.items[1].qty, bill.items[1].qty);
    });

    test('parseBillItems matches jsonEncode output', () {
      final items = [
        BillItem(qty: 3, rate: 75.5, cgstPct: 2.5, sgstPct: 2.5, igstPct: 0),
      ];
      final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
      final parsed = LocalDb.parseBillItems(encoded);

      expect(parsed.length, 1);
      expect(parsed.first.qty, 3);
      expect(parsed.first.rate, 75.5);
    });

    test('getNextBillNumber advances after insertBill', () async {
      final db = LocalDb.instance;
      await db.initialize();

      expect(await db.getNextBillNumber(_testLocationName), 1);

      final bill = SaleBill.fromJson(_sampleBillJson(billNo: 1));
      await db.insertBill(bill);

      expect(await db.getNextBillNumber(_testLocationName), 2);
    });

    test('insertBill aborts on duplicate bill_no instead of overwriting', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final bill = SaleBill.fromJson(_sampleBillJson(billNo: 42));
      await db.insertBill(bill);

      expect(
        () => db.insertBill(bill),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('getBillsBySyncStatus and markSynced', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final bill = SaleBill.fromJson(_sampleBillJson(billNo: 5));
      final localId = await db.insertBill(bill);

      final pending = await db.getBillsBySyncStatus(
        'pending',
        location: _testLocationName,
      );
      expect(pending.length, 1);
      expect(pending.first.localId, localId);

      await db.markSynced(localId);

      final synced = await db.getBillsBySyncStatus(
        'synced',
        location: _testLocationName,
      );
      expect(synced.length, 1);
      expect(
        (await db.getBillsBySyncStatus('pending', location: _testLocationName))
            .length,
        0,
      );
    });

    test('getPreviousBill returns highest bill below given number', () async {
      final db = LocalDb.instance;
      await db.initialize();

      for (final billNo in [1, 3, 7]) {
        await db.insertBill(
          SaleBill.fromJson(_sampleBillJson(billNo: billNo)),
        );
      }

      final previous = await db.getPreviousBill(
        location: _testLocationName,
        beforeBillNo: 7,
      );

      expect(previous, isNotNull);
      expect(previous!.bill.billNo, 3);
    });

    test('getLedgerEntries filters by date range', () async {
      final db = LocalDb.instance;
      await db.initialize();

      await db.insertBill(
        SaleBill.fromJson({
          ..._sampleBillJson(billNo: 1),
          'billDate': '2026-08-30',
        }),
      );
      await db.insertBill(
        SaleBill.fromJson({
          ..._sampleBillJson(billNo: 2),
          'billDate': '2026-08-31',
        }),
      );

      final entries = await db.getLedgerEntries(
        _testLocationName,
        from: '2026-08-31',
        to: '2026-08-31',
      );

      expect(entries.length, 1);
      expect(entries.first.billNo, 2);
    });

    test('getLastPullAt and setLastPullAt', () async {
      final db = LocalDb.instance;
      await db.initialize();

      expect(await db.getLastPullAt(_testLocationName), isNull);

      final timestamp = DateTime.utc(2026, 8, 31, 8, 0);
      await db.setLastPullAt(_testLocationName, timestamp);

      expect(
        await db.getLastPullAt(_testLocationName),
        timestamp,
      );
    });

    test('applyPulledBills inserts server bills and overwrites synced rows',
        () async {
      final db = LocalDb.instance;
      await db.initialize();

      final localBill = SaleBill.fromJson(_sampleBillJson(billNo: 1));
      await db.insertBill(localBill, syncStatus: 'synced');

      final pulledUpdate = SaleBill.fromJson({
        ..._sampleBillJson(billNo: 1),
        'customerName': 'Admin Edited',
      });
      final pulledNew = SaleBill.fromJson(_sampleBillJson(billNo: 2));

      final applied = await db.applyPulledBills([pulledUpdate, pulledNew]);

      expect(applied, 2);

      final updated = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 1,
      );
      expect(updated!.bill.customerName, 'Admin Edited');

      final inserted = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 2,
      );
      expect(inserted, isNotNull);
      expect(inserted!.syncStatus, 'synced');
    });

    test('applyPulledBills overwrites pending local bills (admin wins)', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final pendingBill = SaleBill.fromJson({
        ..._sampleBillJson(billNo: 5),
        'customerName': 'Local Pending',
      });
      await db.insertBill(pendingBill, syncStatus: 'pending');

      final pulled = SaleBill.fromJson({
        ..._sampleBillJson(billNo: 5),
        'customerName': 'Server Version',
      });

      final applied = await db.applyPulledBills([pulled]);

      expect(applied, 1);

      final stored = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 5,
      );
      expect(stored!.bill.customerName, 'Server Version');
      expect(stored.syncStatus, 'synced');
    });

    test('applyPulledBills applies server-side soft delete', () async {
      final db = LocalDb.instance;
      await db.initialize();

      await db.insertBill(
        SaleBill.fromJson(_sampleBillJson()),
        syncStatus: 'synced',
      );

      final pulled = SaleBill.fromJson({
        ..._sampleBillJson(),
        'deleted': true,
      });

      final applied = await db.applyPulledBills([pulled]);

      expect(applied, 1);

      final entries = await db.getLedgerEntries(_testLocationName);
      expect(entries, isEmpty);
    });

    test('markBillDeleted hides bill from ledger but keeps row in database',
        () async {
      final db = LocalDb.instance;
      await db.initialize();

      final localId = await db.insertBill(
        SaleBill.fromJson(_sampleBillJson()),
        syncStatus: 'synced',
      );
      await db.markBillDeleted(localId);

      final entries = await db.getLedgerEntries(_testLocationName);
      expect(entries, isEmpty);

      final stored = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 1,
      );
      expect(stored, isNotNull);

      final pending = await db.getBillsBySyncStatus(
        'pending',
        location: _testLocationName,
      );
      expect(pending, hasLength(1));
      expect(pending.first.bill.deleted, isTrue);
    });

    test('never-synced pending delete soft-deletes row and preserves bill number gap',
        () async {
      final db = LocalDb.instance;
      await db.initialize();

      expect(await db.getNextBillNumber(_testLocationName), 1);

      final localId = await db.insertBill(
        SaleBill.fromJson(_sampleBillJson(billNo: 1)),
      );
      expect(await db.getNextBillNumber(_testLocationName), 2);

      await db.markBillDeleted(localId);

      final sqlite = await db.database;
      final rows = await sqlite.query(
        'bills',
        where: 'local_id = ?',
        whereArgs: [localId],
      );
      expect(rows, hasLength(1));
      expect(rows.first['deleted'], 1);
      expect(rows.first['sync_status'], 'synced');

      final stored = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 1,
      );
      expect(stored, isNotNull);
      expect(stored!.bill.deleted, isTrue);

      final pending = await db.getBillsBySyncStatus(
        'pending',
        location: _testLocationName,
      );
      expect(pending, isEmpty);

      expect(await db.getNextBillNumber(_testLocationName), 2);

      await db.insertBill(SaleBill.fromJson(_sampleBillJson(billNo: 2)));
      expect(await db.getNextBillNumber(_testLocationName), 3);
    });
  });

  group('V1 to V2 migration', () {
    test('migrates all v1 rows and preserves line items', () async {
      final path = await _testDbPath();
      final v1 = await _openV1Database(path);

      final payload = _sampleBillJson(billNo: 10);
      await v1.insert('bills', {
        'local_id': 'legacy-1',
        'bill_no': 10,
        'location': _testLocationName,
        'payload': jsonEncode(payload),
        'sync_status': 'synced',
        'created_at': '2026-08-31T08:00:00.000Z',
      });
      await v1.close();

      final db = LocalDb.instance;
      await db.initialize();

      final stored = await db.getBillByNumber(
        location: _testLocationName,
        billNo: 10,
      );

      expect(stored, isNotNull);
      expect(stored!.bill.items.length, 2);
      expect(stored.bill.customerName, 'Test Customer');
      expect(await db.getNextBillNumber(_testLocationName), 11);

      final rawDb = await db.database;
      final backupExists = await rawDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='bills_v1_backup'",
      );
      expect(backupExists, isEmpty);
    });

    test('aborts migration on unparseable row without modifying schema', () async {
      final path = await _testDbPath();
      final v1 = await _openV1Database(path);

      await v1.insert('bills', {
        'local_id': 'good-row',
        'bill_no': 1,
        'location': _testLocationName,
        'payload': jsonEncode(_sampleBillJson(billNo: 1)),
        'sync_status': 'pending',
        'created_at': '2026-08-31T08:00:00.000Z',
      });
      await v1.insert('bills', {
        'local_id': 'bad-row',
        'bill_no': 2,
        'location': _testLocationName,
        'payload': 'not-valid-json',
        'sync_status': 'pending',
        'created_at': '2026-08-31T08:00:00.000Z',
      });
      await v1.close();

      final db = LocalDb.instance;

      await expectLater(
        db.initialize(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('migration aborted'),
              contains('bad-row'),
            ),
          ),
        ),
      );

      await LocalDb.resetForTesting();

      final inspection = await openDatabase(path);
      final tables = await inspection.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final tableNames = tables.map((row) => row['name'] as String).toList();

      expect(tableNames, contains('bills'));
      expect(tableNames, isNot(contains('bills_v1_backup')));

      final rows = await inspection.query('bills');
      expect(rows.length, 2);
      expect(rows.any((row) => row['local_id'] == 'bad-row'), isTrue);

      await inspection.close();
    });
  });
}
