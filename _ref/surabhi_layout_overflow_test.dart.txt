import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/screen/bill_item.dart';
import 'package:surabhi/screen/sales_bill_screen.dart';
import 'package:surabhi/screen/staff_dashboard_screen.dart';
import 'package:surabhi/services/session_service.dart';
import 'package:surabhi/utils/money_format.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'main';

/// Matches [_SalesBillScreenState._gridFooterGrandRowHeight].
const _grandRowHeight = 48.0;

/// Body bottom inset; allows one device pixel for grid border painting.
const _maxGrandRowInsetFromBodyBottom = 9.0;

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/main_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('sales_bill_overflow_');
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
    await _deleteTestDb();
    await LocalDb.instance.initialize();
    await LocalDb.instance.getNextBillNumber(AppConfig.displayLocationName);
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  List<BillItem> billItems(int count) {
    return List.generate(
      count,
      (index) => BillItem(
        particular: 'ITEM ${index + 1}',
        qty: 1,
        rate: 10.0 + index,
      ),
    );
  }

  List<BillItem> tenItemsWithGrandTotal(double grandTotal) {
    final rate = grandTotal / 10;
    return List.generate(
      10,
      (index) => BillItem(
        particular: index == 0 ? 'AA' : 'ITEM ${index + 1}',
        qty: 1,
        rate: rate,
      ),
    );
  }

  double textFontSize(WidgetTester tester, Finder finder) {
    final text = tester.widget<Text>(finder);
    return text.style?.fontSize ?? 0;
  }

  double grandRowBottom(WidgetTester tester) {
    final grandText = tester.getRect(find.text('GRAND TOTAL'));
    return grandText.center.dy + _grandRowHeight / 2;
  }

  void expectGrandRowNearBodyBottom(WidgetTester tester) {
    final bodyBottom = tester.getRect(find.byType(Scaffold)).bottom;
    expect(
      bodyBottom - grandRowBottom(tester),
      lessThanOrEqualTo(_maxGrandRowInsetFromBodyBottom),
    );
  }

  Finder _gridHorizontalScrollView() => find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );

  Finder _gridHorizontalScrollbar() => find.ancestor(
        of: _gridHorizontalScrollView(),
        matching: find.byType(Scrollbar),
      );

  void expectListViewportMeetsTotalRow(WidgetTester tester) {
    final totalTop = tester.getRect(find.text('Total')).top;
    final bodyBottom = tester.getRect(_gridHorizontalScrollbar()).bottom;
    expect(bodyBottom, closeTo(totalTop, 1));
  }

  void expectGrandRowNearDashboardContentBottom(WidgetTester tester) {
    final billScreen = find.byType(SalesBillScreen);
    expect(billScreen, findsOneWidget);
    final contentBottom = tester.getRect(billScreen).bottom;
    expect(
      contentBottom - grandRowBottom(tester),
      lessThanOrEqualTo(_maxGrandRowInsetFromBodyBottom),
    );
  }

  Future<void> pumpStaffDashboardBill(
    WidgetTester tester, {
    List<BillItem>? items,
  }) async {
    if (items != null) {
      await SessionService.saveBillSession(
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

    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StaffDashboardScreen(),
      ),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty &&
          find.text('GRAND TOTAL').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectRow10AboveHorizontalScrollbar(WidgetTester tester) {
    final row10 = find.text('ITEM 10');
    expect(row10, findsOneWidget);
    final rowBottom = tester.getRect(row10).bottom;
    final footerTop = tester.getRect(find.text('Total')).top;
    expect(rowBottom, lessThan(footerTop));
  }

  Future<void> showRateValidationError(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('bill_rate_field')), '0');
    await tester.tap(find.byKey(const Key('bill_qty_field')));
    await tester.enterText(find.byKey(const Key('bill_qty_field')), '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Rate must be greater than 0'), findsOneWidget);
  }

  double maxVerticalListScrollExtent(WidgetTester tester) {
    var maxExtent = 0.0;
    final listViews = tester.widgetList<ListView>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.vertical,
      ),
    );
    for (final listView in listViews) {
      final controller = listView.controller;
      if (controller != null && controller.hasClients) {
        maxExtent = math.max(maxExtent, controller.position.maxScrollExtent);
      }
    }
    return maxExtent;
  }

  Future<void> pumpSalesBillDesktop(
    WidgetTester tester, {
    required List<BillItem> items,
    bool sidebarOpen = false,
  }) async {
    await SessionService.saveBillSession(
      location: AppConfig.displayLocationName,
      billNo: 1,
      billDate: DateTime(2026, 10, 13),
      paymentMode: 'UPI',
      customerName: 'TEST CUSTOMER',
      mobile: '9876543210',
      items: items,
      billSaved: false,
    );

    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SalesBillScreen(),
      ),
    );

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('BILL NO:').evaluate().isNotEmpty &&
          find.text('GRAND TOTAL').evaluate().isNotEmpty &&
          find.byIcon(Icons.close).evaluate().length >= items.length) {
        break;
      }
    }

    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    if (sidebarOpen) {
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.menu_open), findsWidgets);
    }
  }

  testWidgets(
      'staff dashboard bill pins grand row near content bottom at 1366x768',
      (tester) async {
    await pumpStaffDashboardBill(tester, items: billItems(3));

    expect(find.byKey(const Key('staff_dashboard_shell')), findsOneWidget);
    expect(find.text('BILL NO:'), findsOneWidget);
    expectGrandRowNearDashboardContentBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('sales bill desktop layout has no overflow at 1366x768 with 3 items',
      (tester) async {
    final items = [
      BillItem(particular: 'RICE', qty: 2, rate: 100),
      BillItem(particular: 'WHEAT FLOUR', qty: 1, rate: 250),
      BillItem(particular: 'SUGAR', qty: 3, rate: 45.5),
    ];

    await pumpSalesBillDesktop(tester, items: items);

    expect(find.text('BILL NO:'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNWidgets(3));
    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill desktop layout has no overflow with Today Sales panel visible',
      (tester) async {
    final items = [
      BillItem(particular: 'RICE', qty: 2, rate: 100),
      BillItem(particular: 'WHEAT FLOUR', qty: 1, rate: 250),
      BillItem(particular: 'SUGAR', qty: 3, rate: 45.5),
    ];

    await pumpSalesBillDesktop(tester, items: items);

    await tester.tap(find.byKey(const Key('today_sales_button')));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('today_sales_panel')).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('today_sales_panel')), findsOneWidget);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill pins grand row near body bottom at 1366x768 with 10 items',
      (tester) async {
    await pumpSalesBillDesktop(tester, items: billItems(10));

    for (var serial = 1; serial <= 10; serial++) {
      expect(find.text('$serial'), findsWidgets);
    }
    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill list viewport meets total row with one item at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: [BillItem(particular: 'RICE', qty: 1, rate: 100)],
    );

    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill pins grand row with sidebar open at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: billItems(10),
      sidebarOpen: true,
    );

    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill list viewport meets total with 15 items at 1366x768',
      (tester) async {
    await pumpSalesBillDesktop(tester, items: billItems(15));

    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'sales bill grid scrolls with 15 items while total rows stay pinned at 1366x768',
      (tester) async {
    // Sixteen lines exceed the ~15½ visible rows at 1366×768.
    await pumpSalesBillDesktop(tester, items: billItems(16));

    expect(maxVerticalListScrollExtent(tester), greaterThan(0));
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('GRAND TOTAL'), findsOneWidget);
    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);

    final verticalList = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalList.first, const Offset(0, -120));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('16'), findsWidgets);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('GRAND TOTAL'), findsOneWidget);
    expectListViewportMeetsTotalRow(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'grand total 7067.00 layout has no overflow at 1366x768 with 10 items',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: tenItemsWithGrandTotal(7067),
    );

    expect(find.text(formatMoneyAmount(7067)), findsWidgets);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'grand total 1234567.00 layout has no overflow at 1366x768 with 10 items',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: tenItemsWithGrandTotal(1234567),
    );

    expect(find.text(formatMoneyAmount(1234567)), findsWidgets);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'grid header and short cell render at font size 10 without shrink',
      (tester) async {
    await pumpSalesBillDesktop(
      tester,
      items: tenItemsWithGrandTotal(7067),
    );

    expect(textFontSize(tester, find.text('S.NO')), 10);
    expect(textFontSize(tester, find.text('AA')), 10);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets(
      'row 10 stays above horizontal scrollbar with rate error visible',
      (tester) async {
    await pumpSalesBillDesktop(tester, items: billItems(10));
    await showRateValidationError(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expectRow10AboveHorizontalScrollbar(tester);
    expectGrandRowNearBodyBottom(tester);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 11));
  });
}
