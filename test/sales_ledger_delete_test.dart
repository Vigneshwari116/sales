import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/owner_delete_service.dart';

LocalLedgerEntry _sampleLedgerEntry() {
  return LocalLedgerEntry(
    localId: 'test-local-id',
    billNo: 1,
    date: '2026-08-31',
    customerName: 'Ledger Test Customer',
    paymentMode: 'CASH',
    total: 100,
    cgst: 2.5,
    sgst: 2.5,
    igst: 0,
    grandTotal: 105,
    syncStatus: 'pending',
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
  tearDown(() {
    OwnerDeleteService.instance.disable();
  });

  Future<void> pumpLedger(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SalesLedgerScreen(
          location: 'Win1',
          autoRefreshOnOpen: false,
          loadLedgerOverride: _loadSampleLedger,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Ledger Test Customer'), findsOneWidget);
  }

  Future<void> doubleTap(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('delete control is absent before owner authentication', (tester) async {
    await pumpLedger(tester);

    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
    expect(find.byTooltip('Delete bill'), findsNothing);
    expect(find.text('X'), findsNothing);
  });

  testWidgets('delete control appears only after owner authentication', (tester) async {
    await pumpLedger(tester);

    expect(find.byTooltip('Delete bill'), findsNothing);

    OwnerDeleteService.instance.enable();
    await tester.pump();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);
    expect(find.byTooltip('Delete bill'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets('incorrect password UI does not enable delete control', (tester) async {
    await pumpLedger(tester);

    await doubleTap(tester, find.text('SALES LEDGER'));

    expect(find.text('Owner password'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'not-the-owner-password');
    await tester.tap(find.text('Unlock'));
    await tester.pump();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
    expect(find.byTooltip('Delete bill'), findsNothing);
    expect(find.text('X'), findsNothing);
    expect(find.text('Incorrect password'), findsOneWidget);
  });

  testWidgets('delete mode disabled after leaving ledger screen', (tester) async {
    await pumpLedger(tester);

    OwnerDeleteService.instance.enable();
    await tester.pump();
    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });
}
