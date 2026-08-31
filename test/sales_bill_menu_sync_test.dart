import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/repositories/ledger_repository.dart' as ledger_repo;
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'win1';

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${_testLocationCode}_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sales_bill_menu_test_');
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
    await SessionService.clearBillSession();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
    await LocalDb.instance.initialize();
    await LocalDb.instance.getNextBillNumber(
      AppConfig.displayLocationName,
    );
    SyncService.instance.start(location: AppConfig.displayLocationName);
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  Future<void> pumpBillScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SalesBillScreen(
          initialBillNo: 1,
          ledgerScreenBuilder: (location) => SalesLedgerScreen(
            location: location,
            autoRefreshOnOpen: false,
            loadLedgerOverride: () async => (
              entries: <ledger_repo.LocalLedgerEntry>[],
              summary: LedgerSummary(
                total: 0,
                cgst: 0,
                sgst: 0,
                igst: 0,
                grandTotal: 0,
              ),
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('BILL NO:'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('staff menu keeps ledger and sync; admin-only items stay out',
      (tester) async {
    await pumpBillScreen(tester);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();

    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('SYNC NOW'), findsOneWidget);
    expect(find.text('ABSTRACT'), findsNothing);
    expect(find.text('PRINTER SETTINGS'), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('ledger menu navigation works while manual push is in progress',
      (tester) async {
    await pumpBillScreen(tester);

    SyncService.instance.manualPushInProgress.value = true;
    await tester.pump();

    expect(find.text('Syncing bills to server...'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();

    await tester.tap(find.text('LEDGER'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SalesLedgerScreen), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
