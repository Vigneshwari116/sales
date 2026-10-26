import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/screen/staff_dashboard_screen.dart';
import 'package:sales/widgets/collapsible_sidebar.dart';
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
const _grandRowHeight = 48.0;
const _maxGrandRowInsetFromBodyBottom = 9.0;

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
    tempDir = await Directory.systemTemp.createTemp('sales_bill_surabhi_ui_');
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

  List<BillItem> billItems(int count) {
    return List.generate(
      count,
      (index) => BillItem(
        qty: 1,
        rate: 10.0 + index,
      ),
    );
  }

  Future<void> saveItems(List<BillItem> items) {
    return SessionService.saveBillSession(
      location: AppConfig.displayLocationName,
      billNo: 1,
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'UPI',
      customerName: 'TEST CUSTOMER',
      mobile: '9876543210',
      items: items,
      billSaved: false,
    );
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (ready()) return;
    }
  }

  void setView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder grandTotalInBill() {
    return find.descendant(
      of: find.byType(SalesBillScreen),
      matching: find.text('GRAND TOTAL'),
    );
  }

  double grandRowBottom(WidgetTester tester) {
    final grandText = tester.getRect(grandTotalInBill());
    return grandText.center.dy + _grandRowHeight / 2;
  }

  void expectGrandRowNearBillBottom(WidgetTester tester) {
    final contentBottom = tester.getRect(find.byType(SalesBillScreen)).bottom;
    expect(
      contentBottom - grandRowBottom(tester),
      lessThanOrEqualTo(_maxGrandRowInsetFromBodyBottom),
    );
  }

  Future<void> pumpStaffBill(
    WidgetTester tester, {
    required Size size,
    required List<BillItem> items,
    required bool sidebarOpen,
  }) async {
    await saveItems(items);
    setView(tester, size);

    await tester.pumpWidget(
      const MaterialApp(
        home: StaffDashboardScreen(),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.text('BILL NO:').evaluate().isNotEmpty &&
          grandTotalInBill().evaluate().isNotEmpty &&
          find.byIcon(Icons.close).evaluate().length >= items.length,
    );

    if (sidebarOpen) {
      await tester.tap(find.byKey(const Key('sidebar_hamburger_toggle')));
      await tester.pump(const Duration(milliseconds: 300));
      final sidebar = tester.widget<CollapsibleSidebar>(
        find.byKey(const Key('staff_collapsible_sidebar')),
      );
      expect(sidebar.expanded, isTrue);
    }

    expect(find.text('TODAY SALES'), findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> pumpBill(
    WidgetTester tester, {
    required List<BillItem> items,
    Size size = const Size(1366, 768),
    bool embedded = false,
  }) async {
    await saveItems(items);
    setView(tester, size);
    await tester.pumpWidget(
      MaterialApp(
        home: SalesBillScreen(
          embeddedInDashboard: embedded,
          initialBillNo: items.isEmpty ? 1 : null,
        ),
      ),
    );
    await pumpUntil(
      tester,
      () => find.text('BILL NO:').evaluate().isNotEmpty,
    );
    if (items.isNotEmpty) {
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.close).evaluate().length >= items.length,
      );
    }
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final size in const <Size>[
    Size(1280, 720),
    Size(1366, 768),
    Size(1920, 1080),
  ]) {
    for (final sidebarOpen in const [false, true]) {
      testWidgets(
        'no overflow at ${size.width.toInt()}x${size.height.toInt()} '
        'sidebar ${sidebarOpen ? 'open' : 'collapsed'}',
        (tester) async {
          await pumpStaffBill(
            tester,
            size: size,
            items: billItems(3),
            sidebarOpen: sidebarOpen,
          );
          expectGrandRowNearBillBottom(tester);
          expect(find.text('TODAY SALES'), findsNothing);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
          await tester.pump(const Duration(seconds: 11));
        },
      );
    }
  }

  testWidgets('tax columns scroll into view and amount is taxable',
      (tester) async {
    await pumpBill(
      tester,
      items: [BillItem(qty: 2, rate: 100)],
      embedded: true,
    );

    expect(find.text('TODAY SALES'), findsNothing);
    expect(find.text('CGST %'), findsOneWidget);
    expect(find.text('SGST %'), findsOneWidget);
    expect(find.text('IGST'), findsOneWidget);
    expect(find.text('TOTAL'), findsWidgets);
    expect(find.text('190'), findsWidgets);
    expect(find.text('200'), findsWidgets);

    final scroll = find.byKey(const Key('grid_horizontal_scroll'));
    final before = tester.getTopLeft(find.text('CGST %')).dx;
    final viewportRight =
        tester.getTopLeft(scroll).dx + tester.getSize(scroll).width;
    expect(before, greaterThan(viewportRight - 1));

    await tester.drag(scroll, const Offset(-240, 0));
    await tester.pump();

    final after = tester.getTopLeft(find.text('CGST %')).dx;
    expect(after, lessThan(before));
    expect(after, lessThan(viewportRight));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('amount in words stays on one line for a long total',
      (tester) async {
    await pumpBill(
      tester,
      items: [BillItem(qty: 1, rate: 1234567)],
      embedded: true,
    );

    final words = amountInWords(1234567).toUpperCase();
    final finder = find.byKey(const Key('grand_total_words'));
    final text = tester.widget<Text>(finder);
    expect(text.data, words);
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(words.length, greaterThan(40));

    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(paragraph.size.height, lessThanOrEqualTo(16));
    final fitted = find.ancestor(of: finder, matching: find.byType(FittedBox));
    expect(tester.getSize(fitted).width, lessThanOrEqualTo(250));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('validation message does not move the table', (tester) async {
    await pumpBill(
      tester,
      items: billItems(2),
      embedded: true,
    );

    final tableTop = tester.getTopLeft(find.text('S.NO')).dy;
    await tester.enterText(find.byKey(const Key('bill_rate_field')), '0');
    await tester.tap(find.byKey(const Key('bill_qty_field')));
    await tester.enterText(find.byKey(const Key('bill_qty_field')), '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Rate must be greater than 0'), findsOneWidget);
    expect(tester.getTopLeft(find.text('S.NO')).dy, tableTop);

    final amount = tester.getRect(find.byKey(const Key('bill_amount_field')));
    final message = tester.getRect(find.text('Rate must be greater than 0'));
    expect(message.left, greaterThan(amount.right - 1));
    expect((message.center.dy - amount.center.dy).abs(), lessThan(20));
    expect(message.height, lessThanOrEqualTo(22));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('red X deletes a line and long-press asks first', (tester) async {
    await pumpBill(
      tester,
      items: [BillItem(qty: 2, rate: 100)],
      embedded: true,
    );

    expect(find.byIcon(Icons.close), findsOneWidget);
    final amountCell = find.descendant(
      of: find.byKey(const Key('grid_horizontal_scroll')),
      matching: find.text('190'),
    );
    await tester.longPress(amountCell);
    await tester.pumpAndSettle();
    expect(find.text('Remove this line?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(amountCell, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Remove this line?'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
