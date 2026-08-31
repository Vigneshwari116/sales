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
import 'package:sales/screen/admin_dashboard_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('admin_dashboard_test_');
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
    await SessionService.clearLogin();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
    await LocalDb.instance.initialize();
    await SessionService.saveLogin('admin', role: SessionRole.admin);
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await SessionService.clearLogin();
    await AppConfig.clearLocation();
  });

  Future<void> pumpAdminDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          ledgerScreenBuilder: (location) => SalesLedgerScreen(
            location: location,
            autoRefreshOnOpen: false,
            embeddedInDashboard: true,
            readOnly: true,
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
      if (find.byKey(const Key('admin_navigation_rail')).evaluate().isNotEmpty) {
        break;
      }
    }
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('admin_location_card_win1')).evaluate().isNotEmpty) {
        break;
      }
    }
  }

  testWidgets('admin dashboard shows NavigationRail and location grid by default',
      (tester) async {
    await pumpAdminDashboard(tester);

    expect(find.byKey(const Key('admin_navigation_rail')), findsOneWidget);
    expect(find.byKey(const Key('admin_location_card_win1')), findsOneWidget);
  });

  testWidgets('navigation rail switches to ledger section', (tester) async {
    await pumpAdminDashboard(tester);

    final rail = tester.widget<NavigationRail>(
      find.byKey(const Key('admin_navigation_rail')),
    );
    expect(rail.selectedIndex, 0);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('SALES LEDGER'), findsOneWidget);
  });

  testWidgets('navigation rail switches to sync section', (tester) async {
    await pumpAdminDashboard(tester);

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('admin_sync_now_button')), findsOneWidget);
  });
}
