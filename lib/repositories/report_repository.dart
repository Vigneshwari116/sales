import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/services/location_seed_service.dart';

class ReportBillRow {
  final int billNo;
  final String date;
  final String customerName;
  final String mobile;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgstIgst;
  final double grandTotal;

  const ReportBillRow({
    required this.billNo,
    required this.date,
    required this.customerName,
    required this.mobile,
    required this.paymentMode,
    required this.total,
    required this.cgst,
    required this.sgstIgst,
    required this.grandTotal,
  });

  bool get isCashPayment => paymentMode.toUpperCase() == 'CASH';

  double get cash => isCashPayment ? grandTotal : 0;

  double get card => isCashPayment ? 0 : grandTotal;
}

class ReportTotals {
  final double cash;
  final double card;
  final double total;
  final double cgst;
  final double sgstIgst;
  final double grandTotal;

  const ReportTotals({
    required this.cash,
    required this.card,
    required this.total,
    required this.cgst,
    required this.sgstIgst,
    required this.grandTotal,
  });

  static const zero = ReportTotals(
    cash: 0,
    card: 0,
    total: 0,
    cgst: 0,
    sgstIgst: 0,
    grandTotal: 0,
  );
}

class ReportBreakdown {
  final List<ReportBillRow> rows;
  final ReportTotals grandTotal;

  const ReportBreakdown({
    required this.rows,
    required this.grandTotal,
  });
}

class ReportRepository {
  static Future<ReportBreakdown> getBreakdown({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);

    final allEntries = <LocalLedgerEntry>[];

    for (final code in allLocationCodes) {
      await LocationSeedService.ensureLocationSeeded(code);
      final entries = await LocationDatabase.getLedgerEntries(
        location: displayNameForLocationCode(code),
        from: fromKey,
        to: toKey,
      );
      allEntries.addAll(entries);
    }

    allEntries.sort((left, right) {
      final dateCompare = right.billDate.compareTo(left.billDate);
      if (dateCompare != 0) return dateCompare;
      return right.billNo.compareTo(left.billNo);
    });

    final rows = allEntries.map(_entryToRow).toList(growable: false);

    var cash = 0.0;
    var card = 0.0;
    var total = 0.0;
    var cgst = 0.0;
    var sgstIgst = 0.0;
    var grandTotalAmount = 0.0;

    for (final row in rows) {
      cash += row.cash;
      card += row.card;
      total += row.total;
      cgst += row.cgst;
      sgstIgst += row.sgstIgst;
      grandTotalAmount += row.grandTotal;
    }

    return ReportBreakdown(
      rows: rows,
      grandTotal: ReportTotals(
        cash: cash,
        card: card,
        total: total,
        cgst: cgst,
        sgstIgst: sgstIgst,
        grandTotal: grandTotalAmount,
      ),
    );
  }

  static ReportBillRow _entryToRow(LocalLedgerEntry entry) {
    return ReportBillRow(
      billNo: entry.billNo,
      date: entry.billDate,
      customerName: entry.customerName,
      mobile: entry.mobile,
      paymentMode: entry.paymentMode,
      total: entry.totalAmount,
      cgst: entry.totalCgst,
      sgstIgst: entry.totalSgst + entry.totalIgst,
      grandTotal: entry.grandTotal,
    );
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
