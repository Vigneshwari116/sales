import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/summary_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/delete_all_bills_service.dart';
import 'package:sales/services/sync_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'win1_delete_all';
const _testLocationName = 'Win1';

Future<void> _deleteDbs(Directory root) async {
  for (final name in [
    '${_testLocationCode}_sales.db',
    SummaryDb.dbFileName,
  ]) {
    final file = File(p.join(root.path, name));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('delete_all_bills_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    await AppConfig.setLocation(_testLocationCode);
    await LocalDb.resetForTesting();
    await SummaryDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteDbs(tempDir);
    await DeleteAllBillsService.clearPullAnchorForTesting(_testLocationCode);
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await SummaryDb.resetForTesting();
    await SyncService.resetForTesting();
    await AppConfig.clearLocation();
    await _deleteDbs(tempDir);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deleteAllForLocation clears bills, counter, summaries, and pending',
      () async {
    final db = LocalDb.instance;
    await db.initialize();

    final items = [
      BillItem(qty: 1, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
    ];
    final bill = SaleBill(
      billNo: 1,
      location: _testLocationName,
      billDate: DateTime(2026, 3, 1),
      paymentMode: 'CASH',
      customerName: 'A',
      mobile: '1',
      items: items,
      totalQty: items.fold(0.0, (sum, item) => sum + item.qty),
      totalAmount: items.fold(0.0, (sum, item) => sum + item.amount),
      totalCgst: items.fold(0.0, (sum, item) => sum + item.cgst),
      totalSgst: items.fold(0.0, (sum, item) => sum + item.sgst),
      totalIgst: 0,
      grandTotal: items.fold(0.0, (sum, item) => sum + item.netAmt),
    );
    await db.insertBill(bill, syncStatus: 'pending');
    expect(await db.getNextBillNumber(_testLocationName), 2);

    await SummaryDb.instance.initialize();
    await SummaryDb.instance.applyBillDelta(
      location: _testLocationName,
      billDate: bill.billDate,
      delta: bill.grandTotal,
    );

    final result =
        await DeleteAllBillsService.deleteAllForLocation(_testLocationName);

    expect(result.ok, isTrue);
    expect(await db.getNextBillNumber(_testLocationName), 1);
    expect(
      (await db.getBillsBySyncStatus('pending', location: _testLocationName))
          .length,
      0,
    );
    expect(await db.getLastPullAt(_testLocationName), isNotNull);

    final dayTotal = await SummaryDb.instance.getTotalForDay(
      day: '2026-03-01',
      location: _testLocationName,
    );
    expect(dayTotal, 0);

    expect(SyncService.instance.pendingBillCount.value, 0);
  });
}
