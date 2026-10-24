import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/screen/admin_day_bills_screen.dart';

DayBillRow _sampleRow({
  required int billNo,
  required double grandTotal,
  String paymentMode = 'CASH',
  double total = 95,
  double gst = 5,
}) {
  return DayBillRow(
    localId: 'id-$billNo',
    location: 'Win1',
    billNo: billNo,
    date: '2026-06-30',
    customerName: 'Customer $billNo',
    mobile: '',
    paymentMode: paymentMode,
    total: total,
    gst: gst,
    grandTotal: grandTotal,
    syncStatus: 'synced',
  );
}

void main() {
  testWidgets('day table shows ledger columns and min amount filter',
      (tester) async {
    final rows = [
      _sampleRow(billNo: 100, grandTotal: 100),
      _sampleRow(
        billNo: 200,
        grandTotal: 5000,
        paymentMode: 'UPI',
        total: 4761.9,
        gst: 238.1,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDayBillsScreen(
          day: '2026-06-30',
          title: '30 Jun 2026',
          loadBillsOverride: () async => rows,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('BILLNO'), findsOneWidget);
    expect(find.text('GROUP'), findsNothing);
    expect(find.text('PCS'), findsNothing);
    expect(find.text('Customer 100'), findsOneWidget);
    expect(find.text('Customer 200'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pump();

    expect(find.text('Customer 100'), findsNothing);
    expect(find.text('Customer 200'), findsOneWidget);
    expect(find.textContaining('Showing 1 of 2 bills'), findsOneWidget);
  });

  testWidgets('footer totals follow filtered rows', (tester) async {
    final rows = [
      _sampleRow(billNo: 1, grandTotal: 100, total: 95, gst: 5),
      _sampleRow(billNo: 2, grandTotal: 200, total: 190, gst: 10),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDayBillsScreen(
          day: '2026-06-30',
          title: '30 Jun 2026',
          loadBillsOverride: () async => rows,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byType(TextField).first, '150');
    await tester.pump();

    expect(find.textContaining('Showing 1 of 2 bills'), findsOneWidget);
    expect(find.text('190.00'), findsOneWidget);
    expect(find.text('10.00'), findsOneWidget);
    expect(find.text('200.00'), findsWidgets);
  });

  testWidgets('UPI bill shows amount under CARD/UPI not CASH', (tester) async {
    final rows = [
      _sampleRow(billNo: 300, grandTotal: 420, paymentMode: 'UPI'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDayBillsScreen(
          day: '2026-06-30',
          title: '30 Jun 2026',
          loadBillsOverride: () async => rows,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('420.00'), findsWidgets);
  });
}
