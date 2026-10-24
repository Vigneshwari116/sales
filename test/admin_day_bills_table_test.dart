import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/screen/admin_day_bills_screen.dart';

DayBillRow _sampleRow({
  required int billNo,
  required double grandTotal,
  String paymentMode = 'CASH',
}) {
  return DayBillRow(
    localId: 'id-$billNo',
    location: 'Win1',
    billNo: billNo,
    date: '2026-06-30',
    customerName: 'Customer $billNo',
    mobile: '',
    paymentMode: paymentMode,
    totalQty: 2,
    total: grandTotal / 1.05,
    gst: grandTotal - (grandTotal / 1.05),
    grandTotal: grandTotal,
    syncStatus: 'synced',
  );
}

void main() {
  testWidgets('day bills screen shows ledger table and min amount filter',
      (tester) async {
    final rows = [
      _sampleRow(billNo: 100, grandTotal: 100),
      _sampleRow(billNo: 200, grandTotal: 5000, paymentMode: 'UPI'),
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
    expect(find.text('GROUP'), findsOneWidget);
    expect(find.text('PCS'), findsOneWidget);
    expect(find.text('Customer 100'), findsOneWidget);
    expect(find.text('Customer 200'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pump();

    expect(find.text('Customer 100'), findsNothing);
    expect(find.text('Customer 200'), findsOneWidget);
    expect(find.textContaining('Showing 1 of 2 bills'), findsOneWidget);
  });
}
