import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';

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

  testWidgets('tapping mobile shows compact password field', (tester) async {
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

    await tester.tap(find.text('9876543210'));
    await tester.pumpAndSettle();

    expect(find.text('Password'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
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
}
