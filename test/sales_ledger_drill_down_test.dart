import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/sync_service.dart';

const _localId = 'drill-down-local-id';

LocalLedgerEntry _sampleLedgerEntry() {
  return LocalLedgerEntry(
    localId: _localId,
    billNo: 7,
    date: '2026-08-31',
    customerName: 'Drill Down Customer',
    mobile: '9999999999',
    paymentMode: 'CASH',
    total: 100,
    cgst: 2.5,
    sgst: 2.5,
    igst: 0,
    grandTotal: 105,
    syncStatus: 'synced',
  );
}

SaleBill _sampleBill() {
  final items = [
    BillItem(qty: 1, rate: 100, cgstPct: 2.5, sgstPct: 2.5),
  ];

  return SaleBill(
    billNo: 7,
    location: 'Win1',
    billDate: DateTime(2026, 8, 31),
    paymentMode: 'CASH',
    customerName: 'Drill Down Customer',
    mobile: '9999999999',
    items: items,
    totalQty: 1,
    totalAmount: items.first.amount,
    totalCgst: items.first.cgst,
    totalSgst: items.first.sgst,
    totalIgst: 0,
    grandTotal: items.first.netAmt,
  );
}

Future<
    ({
      List<LocalLedgerEntry> entries,
      LedgerSummary summary,
    })> _loadSampleLedger() async {
  final entry = _sampleLedgerEntry();
  return (
    entries: [entry],
    summary: LedgerSummary(
      total: entry.total,
      cgst: entry.cgst,
      sgst: entry.sgst,
      igst: entry.igst,
      grandTotal: entry.grandTotal,
    ),
  );
}

void main() {
  tearDown(() async {
    await SyncService.resetForTesting();
  });

  testWidgets('tapping ledger row opens read-only bill detail', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Win1',
          autoRefreshOnOpen: false,
          loadLedgerOverride: _loadSampleLedger,
          loadBillOverride: (localId) async {
            expect(localId, _localId);
            return _sampleBill();
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Drill Down Customer'), findsOneWidget);
    expect(find.text('9999999999'), findsOneWidget);

    await tester.tap(find.text('Drill Down Customer'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerBillDetailScreen), findsOneWidget);
    expect(find.text('BILL 7'), findsOneWidget);
    expect(find.text('9999999999'), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('shows snackbar when bill cannot be loaded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Win1',
          autoRefreshOnOpen: false,
          loadLedgerOverride: _loadSampleLedger,
          loadBillOverride: (_) async => null,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Drill Down Customer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not load bill'), findsOneWidget);
    expect(find.byType(LedgerBillDetailScreen), findsNothing);
  });

  testWidgets('row tap opens detail while manual push is in progress', (tester) async {
    SyncService.instance.manualPushInProgress.value = true;

    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Win1',
          autoRefreshOnOpen: false,
          loadLedgerOverride: _loadSampleLedger,
          loadBillOverride: (_) async => _sampleBill(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(SyncService.instance.manualPushInProgress.value, isTrue);

    await tester.tap(find.text('Drill Down Customer'));
    await tester.pumpAndSettle();

    expect(find.byType(LedgerBillDetailScreen), findsOneWidget);
    expect(find.text('BILL 7'), findsOneWidget);
  });
}
