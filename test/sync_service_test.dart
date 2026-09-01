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

SaleBill _pendingBill(int billNo) {
  final items = [
    BillItem(qty: 1, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
  ];

  return SaleBill(
    billNo: billNo,
    location: _testLocationName,
    billDate: DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: 'Customer $billNo',
    mobile: '9999999999',
    items: items,
    totalQty: items.fold(0.0, (sum, item) => sum + item.qty),
    totalAmount: items.fold(0.0, (sum, item) => sum + item.amount),
    totalCgst: items.fold(0.0, (sum, item) => sum + item.cgst),
    totalSgst: items.fold(0.0, (sum, item) => sum + item.sgst),
    totalIgst: 0,
    grandTotal: items.fold(0.0, (sum, item) => sum + item.netAmt),
  );
}

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${_testLocationCode}_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

Future<Map<int, String>> _syncStatusByBillNo(String location) async {
  final pending = await LocalDb.instance.getBillsBySyncStatus(
    'pending',
    location: location,
  );
  final synced = await LocalDb.instance.getBillsBySyncStatus(
    'synced',
    location: location,
  );

  final statuses = <int, String>{};
  for (final stored in pending) {
    statuses[stored.bill.billNo] = 'pending';
  }
  for (final stored in synced) {
    statuses[stored.bill.billNo] = 'synced';
  }
  return statuses;
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_service_test_');
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
    await SyncService.resetForTesting();
    await _deleteTestDb();
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  group('ManualPushResult', () {
    test('summaryMessage for successful sync', () {
      const result = ManualPushResult(ok: true, syncedCount: 12, failedCount: 0);
      expect(result.summaryMessage, '12 bills synced');
    });

    test('summaryMessage for single bill', () {
      const result = ManualPushResult(ok: true, syncedCount: 1, failedCount: 0);
      expect(result.summaryMessage, '1 bill synced');
    });

    test('summaryMessage when nothing pending', () {
      const result = ManualPushResult(ok: true, syncedCount: 0, failedCount: 0);
      expect(result.summaryMessage, 'No pending bills to sync');
    });

    test('summaryMessage for partial failure', () {
      const result = ManualPushResult(
        ok: false,
        syncedCount: 3,
        failedCount: 2,
        error: 'Some bills could not be synced',
      );
      expect(result.summaryMessage, '3 synced, 2 failed');
    });

    test('summaryMessage for offline', () {
      const result = ManualPushResult(
        ok: false,
        syncedCount: 0,
        failedCount: 0,
        error: 'No internet connection',
      );
      expect(result.summaryMessage, 'No internet connection');
    });
  });

  group('manualPush integration', () {
    test(
      'partial batch failure then retry syncs only remaining pending bills',
      () async {
        final db = LocalDb.instance;
        await db.initialize();

        for (var billNo = 1; billNo <= 12; billNo++) {
          await db.insertBill(_pendingBill(billNo));
        }

        final sync = SyncService.instance;
        sync.isOnlineOverride = () async => true;

        final postedBillNos = <int>[];
        var connectionDropped = true;

        sync.saveBillOverride = (bill) async {
          postedBillNos.add(bill.billNo);
          if (connectionDropped && bill.billNo >= 7) {
            return SalesApiResult.failure('Connection dropped');
          }
          return SalesApiResult.success(bill.billNo);
        };

        final firstResult = await sync.manualPush(_testLocationName);

        expect(firstResult.ok, isFalse);
        expect(firstResult.syncedCount, 6);
        expect(firstResult.failedCount, 6);
        expect(firstResult.error, 'Some bills could not be synced');
        expect(postedBillNos, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);

        final afterFirstFailure = await _syncStatusByBillNo(_testLocationName);
        for (var billNo = 1; billNo <= 6; billNo++) {
          expect(afterFirstFailure[billNo], 'synced');
        }
        for (var billNo = 7; billNo <= 12; billNo++) {
          expect(afterFirstFailure[billNo], 'pending');
        }

        connectionDropped = false;
        postedBillNos.clear();

        final secondResult = await sync.manualPush(_testLocationName);

        expect(secondResult.ok, isTrue);
        expect(secondResult.syncedCount, 6);
        expect(secondResult.failedCount, 0);
        expect(secondResult.error, isNull);
        expect(postedBillNos, [7, 8, 9, 10, 11, 12]);

        final afterRetry = await _syncStatusByBillNo(_testLocationName);
        for (var billNo = 1; billNo <= 12; billNo++) {
          expect(afterRetry[billNo], 'synced');
        }

        final stillPending = await db.getBillsBySyncStatus(
          'pending',
          location: _testLocationName,
        );
        expect(stillPending, isEmpty);
      },
    );

    test('manualPush pushes soft-deleted synced bill with deleted flag', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final localId = await db.insertBill(
        _pendingBill(1),
        syncStatus: 'synced',
      );
      await db.markBillDeleted(localId);

      final sync = SyncService.instance;
      sync.isOnlineOverride = () async => true;

      SaleBill? pushedBill;
      sync.saveBillOverride = (bill) async {
        pushedBill = bill;
        return SalesApiResult.success(bill.billNo);
      };

      final result = await sync.manualPush(_testLocationName);

      expect(result.ok, isTrue);
      expect(result.syncedCount, 1);
      expect(pushedBill, isNotNull);
      expect(pushedBill!.deleted, isTrue);

      final stillPending = await db.getBillsBySyncStatus(
        'pending',
        location: _testLocationName,
      );
      expect(stillPending, isEmpty);
    });
  });

  group('manualSync integration', () {
    test('manualSync pushes pending bills without deadlock', () async {
      final db = LocalDb.instance;
      await db.initialize();

      await db.insertBill(_pendingBill(1));
      await db.insertBill(_pendingBill(2));

      final sync = SyncService.instance;
      sync.isOnlineOverride = () async => true;
      sync.saveBillOverride = (bill) async => SalesApiResult.success(bill.billNo);
      sync.getBillUpdatesSinceOverride =
          ({required location, required since}) async {
        return SalesApiResult.success((
          bills: <SaleBill>[],
          serverTime: DateTime.now().toUtc(),
        ));
      };

      final result = await sync.manualSync(_testLocationName);

      expect(result.ok, isTrue);
      expect(result.pushedCount, 2);
      expect(result.pushFailedCount, 0);
      expect(result.summaryMessage, contains('2 bills pushed'));

      final stillPending = await db.getBillsBySyncStatus(
        'pending',
        location: _testLocationName,
      );
      expect(stillPending, isEmpty);
    });

    test('manualSync surfaces pull errors', () async {
      final db = LocalDb.instance;
      await db.initialize();

      final sync = SyncService.instance;
      sync.isOnlineOverride = () async => true;
      sync.getBillUpdatesSinceOverride = ({required location, required since}) async {
        return SalesApiResult.failure('Server error 503');
      };

      final result = await sync.manualSync(_testLocationName);

      expect(result.ok, isFalse);
      expect(result.pullError, contains('503'));
      expect(result.summaryMessage, contains('Sync failed'));
    });
  });
}
