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
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/screen/admin_day_bills_screen.dart';
import 'package:sales/screen/bill_item.dart';
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
    tempDir = await Directory.systemTemp.createTemp('sales_bill_ui_test_');
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
    BillRepository.saveBillApiOverride =
        (bill) async => SalesApiResult.success(bill.billNo);
  });

  tearDown(() async {
    BillRepository.saveBillApiOverride = null;
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  Future<void> pumpBillScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
      if (find.byKey(const Key('bill_today_sales_button')).evaluate().isNotEmpty) {
        break;
      }
    }
  }

  testWidgets('hidden tax columns do not affect footer totals', (tester) async {
    final items = [
      BillItem(qty: 2, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
      BillItem(qty: 1, rate: 50, cgstPct: 2.5, sgstPct: 2.5),
    ];
    final expectedGrand =
        items.fold<double>(0, (sum, item) => sum + item.netAmt);
    final expectedPcs =
        items.fold<double>(0, (sum, item) => sum + item.qty);
    final expectedDisplayAmount =
        items.fold<double>(0, (sum, item) => sum + item.grossAmt);

    await SessionService.saveBillSession(
      location: AppConfig.displayLocationName,
      billNo: 1,
      billDate: DateTime.now(),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: items,
      billSaved: false,
    );

    await pumpBillScreen(tester);

    expect(find.text('CGST %'), findsNothing);
    expect(find.text('IGST'), findsNothing);
    expect(find.text('Total'), findsWidgets);
    expect(find.text('GRAND'), findsOneWidget);
    expect(find.textContaining('(total pcs)'), findsOneWidget);
    expect(find.textContaining(expectedPcs.toStringAsFixed(0)), findsWidgets);
    expect(find.text(expectedDisplayAmount.toStringAsFixed(0)), findsWidgets);
    expect(find.text(expectedGrand.toStringAsFixed(2)), findsOneWidget);

    final expectedTaxable =
        items.fold<double>(0, (sum, item) => sum + item.amount);
    final expectedCgst =
        items.fold<double>(0, (sum, item) => sum + item.cgst);
    expect(expectedTaxable, greaterThan(0));
    expect(expectedCgst, greaterThan(0));
  });

  testWidgets('TODAY SALES opens day bills for today', (tester) async {
    await pumpBillScreen(tester);

    await tester.tap(find.byKey(const Key('bill_today_sales_button')));
    await tester.pumpAndSettle();

    expect(find.byType(AdminDayBillsScreen), findsOneWidget);
    expect(find.textContaining('Today'), findsWidgets);
  });

  testWidgets('long-press row removes line after confirm', (tester) async {
    await pumpBillScreen(tester);

    final rateField = find.byKey(const Key('bill_rate_field'));
    final qtyField = find.byKey(const Key('bill_qty_field'));

    await tester.tap(rateField);
    await tester.enterText(rateField, '100');
    await tester.tap(qtyField);
    await tester.enterText(qtyField, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bill_table_row_0')), findsOneWidget);

    await tester.longPress(find.byKey(const Key('bill_table_row_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bill_table_row_0')), findsNothing);
  });
}
