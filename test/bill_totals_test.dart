import 'package:flutter_test/flutter_test.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/utils/bill_totals.dart';

void main() {
  test('IGST-only line keeps tax in IGST bucket', () {
    final item = BillItem(
      qty: 2,
      rate: 150,
      cgstPct: 0,
      sgstPct: 0,
      igstPct: 5,
    );

    final totals = BillTotals.fromItems([item]);

    expect(totals.grandTotal, 300);
    expect(totals.totalCgst, 0);
    expect(totals.totalSgst, 0);
    expect(totals.totalIgst, closeTo(14.29, 0.01));
    expect(totals.totalAmount + totals.totalIgst, closeTo(300, 0.01));
  });

  test('mixed CGST/SGST lines preserve split', () {
    final item = BillItem(qty: 1, rate: 105, cgstPct: 2.5, sgstPct: 2.5);
    final totals = BillTotals.fromItems([item]);

    expect(totals.totalCgst, closeTo(totals.totalSgst, 0.001));
    expect(totals.totalIgst, 0);
    expect(totals.grandTotal, 105);
  });
}
