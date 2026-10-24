import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

SaleBill _sampleBill() {
  final items = [
    BillItem(qty: 2, rate: 150, cgstPct: 2.5, sgstPct: 2.5),
    BillItem(qty: 1, rate: 200, cgstPct: 2.5, sgstPct: 2.5),
  ];

  return SaleBill(
    billNo: 42,
    location: 'Win1',
    billDate: DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: 'Detail Test Customer',
    mobile: '9876543210',
    items: items,
    totalQty: items.fold(0.0, (sum, item) => sum + item.qty),
    totalAmount: items.fold(0.0, (sum, item) => sum + item.amount),
    totalCgst: items.fold(0.0, (sum, item) => sum + item.cgst),
    totalSgst: items.fold(0.0, (sum, item) => sum + item.sgst),
    totalIgst: 0,
    grandTotal: items.fold(0.0, (sum, item) => sum + item.netAmt),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('ledger_detail_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation('win1');
    await LocalDb.resetForTesting();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  testWidgets('shows bill header, customer, line items, and totals', (tester) async {
    final bill = _sampleBill();

    await tester.pumpWidget(
      MaterialApp(
        home: LedgerBillDetailScreen(
          bill: bill,
          localId: 'detail-test-id',
          syncStatus: 'synced',
        ),
      ),
    );

    expect(find.text('BILL 42'), findsOneWidget);
    expect(find.text('Detail Test Customer'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('CASH'), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Location: Win1'), findsOneWidget);

    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Grand Total'), findsOneWidget);
  });

  testWidgets('staff EDIT asks for password before enabling save', (tester) async {
    final bill = _sampleBill();

    await tester.pumpWidget(
      MaterialApp(
        home: LedgerBillDetailScreen(
          bill: bill,
          localId: 'detail-test-id',
          syncStatus: 'synced',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();

    expect(find.text('Enter edit password'), findsOneWidget);
  });

  testWidgets('shows empty items message when bill has no line items', (tester) async {
    final bill = SaleBill(
      billNo: 1,
      location: 'Win1',
      billDate: DateTime(2026, 8, 31),
      paymentMode: 'CASH',
      customerName: 'Empty Bill',
      mobile: '',
      items: const [],
      totalQty: 0,
      totalAmount: 0,
      totalCgst: 0,
      totalSgst: 0,
      totalIgst: 0,
      grandTotal: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LedgerBillDetailScreen(
          bill: bill,
          localId: 'empty-bill-id',
          syncStatus: 'pending',
        ),
      ),
    );

    expect(
      find.text('This bill has no line items stored locally.'),
      findsOneWidget,
    );
    expect(find.text('Pending sync'), findsOneWidget);
  });

  testWidgets('back button pops bill detail screen', (tester) async {
    final bill = _sampleBill();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LedgerBillDetailScreen(
                      bill: bill,
                      localId: 'detail-test-id',
                      syncStatus: 'synced',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerBillDetailScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerBillDetailScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
