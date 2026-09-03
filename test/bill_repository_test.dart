import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
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

SaleBill _sampleBill({int billNo = 1, double rate = 100}) {
  return SaleBill(
    billNo: billNo,
    location: 'Win1',
    billDate: DateTime(2026, 9, 3),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [BillItem(qty: 1, rate: rate)],
    totalQty: 1,
    totalAmount: rate,
    totalCgst: 2.5,
    totalSgst: 2.5,
    totalIgst: 0,
    grandTotal: rate + 5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('bill_repository_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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

  test('offline save updates existing bill instead of failing duplicate', () async {
    final bill = _sampleBill();
    await LocalDb.instance.insertPendingBill(bill);

    final updated = _sampleBill(rate: 137);
    final result = await BillRepository.saveBill(updated);

    expect(result.ok, isTrue);

    final stored = await LocalDb.instance.getBillByNumber(
      location: 'Win1',
      billNo: 1,
    );
    expect(stored?.bill.totalAmount, 137);
  });
}
