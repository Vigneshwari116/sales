import 'package:sales/screen/bill_item.dart';

/// Header totals derived from line items (same rules as new-bill entry).
class BillTotals {
  final double totalQty;
  final double totalAmount;
  final double totalCgst;
  final double totalSgst;
  final double totalIgst;
  final double grandTotal;

  const BillTotals({
    required this.totalQty,
    required this.totalAmount,
    required this.totalCgst,
    required this.totalSgst,
    required this.totalIgst,
    required this.grandTotal,
  });

  double get totalGst => totalCgst + totalSgst + totalIgst;

  static BillTotals fromItems(List<BillItem> items) {
    var totalQty = 0.0;
    var totalAmount = 0.0;
    var totalCgst = 0.0;
    var totalSgst = 0.0;
    var totalIgst = 0.0;
    var grandTotal = 0.0;

    for (final item in items) {
      totalQty += item.qty;
      totalAmount += item.amount;
      totalCgst += item.cgst;
      totalSgst += item.sgst;
      totalIgst += item.igst;
      grandTotal += item.grossAmt;
    }

    return BillTotals(
      totalQty: totalQty,
      totalAmount: totalAmount,
      totalCgst: totalCgst,
      totalSgst: totalSgst,
      totalIgst: totalIgst,
      grandTotal: grandTotal,
    );
  }
}
