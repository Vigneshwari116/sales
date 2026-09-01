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
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/sync_service.dart';

import 'test_guards.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _staffLocationCode = 'win3';
const _staffLocationName = 'Win3';

SaleBill _syncedBill({required int billNo, required String customerName}) {
  final items = [
    BillItem(qty: 1, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
  ];

  return SaleBill(
    billNo: billNo,
    location: _staffLocationName,
    billDate: DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: customerName,
    mobile: '9876543210',
    items: items,
    totalQty: 1,
    totalAmount: items.first.amount,
    totalCgst: items.first.cgst,
    totalSgst: items.first.sgst,
    totalIgst: 0,
    grandTotal: items.first.netAmt,
  );
}

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${_staffLocationCode}_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    enableProductionNetworkGuard();
    tempDir = await Directory.systemTemp.createTemp('admin_edit_pull_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    disableProductionNetworkGuard();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation(_staffLocationCode);
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  test(
    'admin edit from server updates staff local copy after pull (no staff push)',
    () async {
      final db = LocalDb.instance;
      await db.initialize();

      final localId = await db.insertBill(
        _syncedBill(billNo: 3, customerName: 'Original Name'),
        syncStatus: 'synced',
      );

      final adminEdited =
          _syncedBill(billNo: 3, customerName: 'Admin Corrected Name');

      final sync = SyncService.instance;
      sync.isOnlineOverride = () async => true;
      sync.getBillUpdatesSinceOverride =
          ({required location, required since}) async {
        expect(location, _staffLocationName);
        return SalesApiResult.success((
          bills: [adminEdited],
          serverTime: DateTime.now().toUtc(),
        ));
      };

      final pullResult = await sync.pullAdminUpdates(_staffLocationName);

      expect(pullResult.ok, isTrue);
      expect(pullResult.pulledCount, 1);

      final loaded = await db.getBillByLocalId(localId);
      expect(loaded, isNotNull);
      expect(loaded!.customerName, 'Admin Corrected Name');
    },
  );
}
