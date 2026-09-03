import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/screen/bill_item.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('abstract_repo_test_');
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
    await AppConfig.setLocation('win1');
    await LocalDb.resetForTesting();
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('abstract reads do not close the active LocalDb connection', () async {
    final before = await LocalDb.instance.getNextBillNumber('Win1');

    await AbstractRepository.getSummaryForLocationCode(
      locationCode: 'win1',
      fromDate: DateTime(2026, 9, 3),
      toDate: DateTime(2026, 9, 3),
    );

    await AbstractRepository.getSummaryForLocationCode(
      locationCode: 'win2',
      fromDate: DateTime(2026, 9, 3),
      toDate: DateTime(2026, 9, 3),
    );

    final after = await LocalDb.instance.getNextBillNumber('Win1');
    expect(after, before);
  });

  test('abstract summary includes saved local bills for active location', () async {
    final bill = SaleBill(
      billNo: 1,
      location: 'Win1',
      billDate: DateTime(2026, 9, 3),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 100),
      ],
      totalQty: 1,
      totalAmount: 100,
      totalCgst: 2.5,
      totalSgst: 2.5,
      totalIgst: 0,
      grandTotal: 105,
    );

    await LocalDb.instance.insertPendingBill(bill);

    final summary = await AbstractRepository.getSummaryForLocationCode(
      locationCode: 'win1',
      fromDate: DateTime(2026, 9, 3),
      toDate: DateTime(2026, 9, 3),
    );

    expect(summary.totalSaleAmount, 100);
  });
}
