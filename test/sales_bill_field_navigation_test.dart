import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/screen/sales_bill_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('sales_bill_nav_test_');
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
    await LocalDb.instance.getNextBillNumber(AppConfig.displayLocationName);
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
      const MaterialApp(
        home: SalesBillScreen(initialBillNo: 1),
      ),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('BILL NO:'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tearDownBillScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 500));
  }

  final rateField = find.byKey(const Key('bill_rate_field'));
  final qtyField = find.byKey(const Key('bill_qty_field'));

  testWidgets('typing pause does not auto-advance rate or add line item',
      (tester) async {
    await pumpBillScreen(tester);

    await tester.tap(rateField);
    await tester.enterText(rateField, '100');
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.widget<TextField>(rateField).focusNode?.hasFocus, isTrue);
    expect(tester.widget<TextField>(qtyField).focusNode?.hasFocus, isFalse);

    await tester.tap(qtyField);
    await tester.enterText(qtyField, '2');
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byIcon(Icons.close), findsNothing);
    await tearDownBillScreen(tester);
  });

  testWidgets('enter on rate advances to qty; enter on qty adds item',
      (tester) async {
    await pumpBillScreen(tester);

    await tester.tap(rateField);
    await tester.enterText(rateField, '100');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(tester.widget<TextField>(qtyField).focusNode?.hasFocus, isTrue);

    await tester.enterText(qtyField, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tearDownBillScreen(tester);
  });

  testWidgets('double-tap mobile unlocks row edit mode', (tester) async {
    await pumpBillScreen(tester);

    await tester.tap(rateField);
    await tester.enterText(rateField, '100');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    await tester.enterText(qtyField, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);

    final mobileField = find.byKey(const Key('bill_mobile_field'));
    await tester.tap(mobileField);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(mobileField);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bill_edit_password_field')), findsOneWidget);
    await tearDownBillScreen(tester);
  });

  testWidgets('invalid rate shows inline error below field', (tester) async {
    await pumpBillScreen(tester);

    await tester.enterText(rateField, '0');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(find.text('Rate must be greater than 0'), findsOneWidget);
    await tearDownBillScreen(tester);
  });
}
