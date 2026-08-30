import 'dart:convert';

import 'package:sales/db/local_db.dart';

class AbstractSummary {
  final double totalSaleAmount;
  final double totalGst;
  final double grandTotal;

  AbstractSummary({
    required this.totalSaleAmount,
    required this.totalGst,
    required this.grandTotal,
  });
}

class AbstractRepository {
  static Future<AbstractSummary> getSummaryForDateRange({
    required String location,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      var fromKey = _formatDate(fromDate);
      var toKey = _formatDate(toDate);
      var rows =
          await LocalDb.instance.getBillsForLedger(location: location);

      var totalSaleAmount = 0.0;
      var totalGst = 0.0;
      var grandTotal = 0.0;

      for (var row in rows) {
        var totals = _totalsForRow(row, fromKey: fromKey, toKey: toKey);
        if (totals == null) {
          continue;
        }

        totalSaleAmount += totals.$1;
        totalGst += totals.$2;
        grandTotal += totals.$3;
      }

      return AbstractSummary(
        totalSaleAmount: totalSaleAmount,
        totalGst: totalGst,
        grandTotal: grandTotal,
      );
    } catch (_) {
      return AbstractSummary(
        totalSaleAmount: 0,
        totalGst: 0,
        grandTotal: 0,
      );
    }
  }

  static (double, double, double)? _totalsForRow(
    Map<String, dynamic> row, {
    required String fromKey,
    required String toKey,
  }) {
    try {
      var payloadRaw = row['payload'] as String?;
      if (payloadRaw == null || payloadRaw.isEmpty) {
        return null;
      }

      var payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
      var billDate = payload['billDate'] as String? ?? '';

      if (billDate.compareTo(fromKey) < 0 || billDate.compareTo(toKey) > 0) {
        return null;
      }

      var saleAmount = (payload['totalAmount'] as num?)?.toDouble() ?? 0;
      var cgst = (payload['totalCgst'] as num?)?.toDouble() ?? 0;
      var sgst = (payload['totalSgst'] as num?)?.toDouble() ?? 0;
      var igst = (payload['totalIgst'] as num?)?.toDouble() ?? 0;
      var grand = (payload['grandTotal'] as num?)?.toDouble() ?? 0;

      return (saleAmount, cgst + sgst + igst, grand);
    } catch (_) {
      return null;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
