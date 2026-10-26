import 'package:surabhi/screen/bill_item.dart';

/// GST-inclusive bill totals with 2-decimal tax lines and reconciled taxable.
class BillGstTotals {
  final double totalQty;
  final double totalAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double grandTotal;

  const BillGstTotals({
    required this.totalQty,
    required this.totalAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.grandTotal,
  });
}

double roundGstMoney(double value) {
  return (value * 100).roundToDouble() / 100;
}

double _uniformPct(
  Iterable<double> values, {
  required double fallback,
}) {
  final set = values.toSet();
  if (set.length == 1) {
    return set.first;
  }
  return fallback;
}

/// GST-inclusive totals from gross (rate × qty) and tax percents.
///
/// taxable_prelim = grandTotal / (1 + totalTax%/100)
/// each tax = round(taxable_prelim × pct / 100, 2)
/// taxable = grandTotal - CGST - SGST - IGST (exact reconciliation)
BillGstTotals computeBillGstTotals({
  required double grandTotal,
  required double totalQty,
  required double cgstPct,
  required double sgstPct,
  required double igstPct,
}) {
  final taxPct = cgstPct + sgstPct + igstPct;
  if (taxPct == 0 || grandTotal == 0) {
    return BillGstTotals(
      totalQty: totalQty,
      totalAmount: roundGstMoney(grandTotal),
      totalCgst: 0,
      totalSgst: 0,
      totalIgst: 0,
      grandTotal: roundGstMoney(grandTotal),
    );
  }

  final preliminary = grandTotal / (1 + taxPct / 100);
  final cgst = roundGstMoney(preliminary * cgstPct / 100);
  final sgst = roundGstMoney(preliminary * sgstPct / 100);
  final igst = roundGstMoney(preliminary * igstPct / 100);
  final taxable = roundGstMoney(grandTotal - cgst - sgst - igst);

  return BillGstTotals(
    totalQty: totalQty,
    totalAmount: taxable,
    totalCgst: cgst,
    totalSgst: sgst,
    totalIgst: igst,
    grandTotal: roundGstMoney(grandTotal),
  );
}

/// Bill totals from line items (sum of rate × qty, uniform tax % from items).
BillGstTotals computeBillGstTotalsFromItems(List<BillItem> items) {
  if (items.isEmpty) {
    return const BillGstTotals(
      totalQty: 0,
      totalAmount: 0,
      totalCgst: 0,
      totalSgst: 0,
      totalIgst: 0,
      grandTotal: 0,
    );
  }

  var grandTotal = 0.0;
  var totalQty = 0.0;
  for (final item in items) {
    grandTotal += item.grossAmt;
    totalQty += item.qty;
  }

  final cgstPct = _uniformPct(
    items.map((item) => item.cgstPct),
    fallback: items.first.cgstPct,
  );
  final sgstPct = _uniformPct(
    items.map((item) => item.sgstPct),
    fallback: items.first.sgstPct,
  );
  final igstPct = _uniformPct(
    items.map((item) => item.igstPct),
    fallback: items.first.igstPct,
  );

  return computeBillGstTotals(
    grandTotal: grandTotal,
    totalQty: totalQty,
    cgstPct: cgstPct,
    sgstPct: sgstPct,
    igstPct: igstPct,
  );
}

/// Per-line display split (same formula on one line's gross).
BillGstTotals gstTotalsForItem(BillItem item) {
  return computeBillGstTotals(
    grandTotal: item.grossAmt,
    totalQty: item.qty,
    cgstPct: item.cgstPct,
    sgstPct: item.sgstPct,
    igstPct: item.igstPct,
  );
}
