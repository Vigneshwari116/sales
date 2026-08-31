import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/sales_ledger_screen.dart';

LocalLedgerEntry _sampleLedgerEntry() {
  return LocalLedgerEntry(
    localId: 'test-local-id',
    billNo: 1,
    date: '2026-08-31',
    customerName: 'Ledger Test Customer',
    mobile: '8888888888',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('ledger has no delete control', (tester) async {
    await pumpLedger(tester);

    expect(find.byTooltip('Delete bill'), findsNothing);
    expect(find.text('X'), findsNothing);
  });
}
