import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/screen/bill_item.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

SaleBill _bill({
  required String location,
  required int billNo,
  String paymentMode = 'CASH',
  double grandTotal = 105,
}) {
  final items = [
    BillItem(qty: 1, rate: grandTotal, cgstPct: 2.5, sgstPct: 2.5),
  ];
  return SaleBill(
    billNo: billNo,
    location: location,
    billDate: DateTime(2026, 6, 30),
    paymentMode: paymentMode,
    customerName: 'Test',
    mobile: '9000000000',
    items: items,
    totalQty: 1,
    totalAmount: items.first.amount,
    totalCgst: items.first.cgst,
    totalSgst: items.first.sgst,
    totalIgst: 0,
    grandTotal: items.first.grossAmt,
  );
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('bill_repo_loc_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation('win1');
    await LocalDb.resetForTesting();
    BillRepository.saveBillApiOverride = null;
  });

  tearDown(() async {
    BillRepository.saveBillApiOverride = null;
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('saves Win2 bill into win2 database without touching Win1', () async {
    BillRepository.saveBillApiOverride =
        (bill) async => SalesApiResult.success(bill.billNo);

    final win1Db = LocalDb.instance;
    await win1Db.initialize();
    final win1LocalId = await win1Db.insertBill(
      _bill(location: 'Win1', billNo: 1),
      syncStatus: 'synced',
    );

    final win2Path = await LocationDatabase.dbPathForLocationCode('win2');
    final win2SeedDb = await openDatabase(win2Path, version: 3,
        onCreate: (db, version) async {
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
    });

    const win2LocalId = 'win2-bill-local-id';
    await win2SeedDb.insert('bills', {
      'local_id': win2LocalId,
      'bill_no': 99,
      'location': 'Win2',
      'bill_date': '2026-06-30',
      'payment_mode': 'CASH',
      'customer_name': 'Branch Two',
      'mobile': '',
      'items_json': '[]',
      'total_qty': 0,
      'total_amount': 100,
      'total_cgst': 2.5,
      'total_sgst': 2.5,
      'total_igst': 0,
      'grand_total': 105,
      'sync_status': 'synced',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted': 0,
    });
    await win2SeedDb.close();

    final updated = _bill(location: 'Win2', billNo: 99, paymentMode: 'UPI');
    final result = await BillRepository.saveBill(
      updated,
      updateLocalId: win2LocalId,
    );

    expect(result.ok, isTrue);

    final win1After = await win1Db.getBillByLocalId(win1LocalId);
    expect(win1After?.paymentMode, 'CASH');

    final win2After = await LocationDatabase.getBillByLocalId(
      locationCode: 'win2',
      localId: win2LocalId,
    );
    expect(win2After, isNotNull);
    expect(win2After!.paymentMode, 'UPI');
  });
}
