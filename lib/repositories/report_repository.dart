import 'package:intl/intl.dart';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/services/location_seed_service.dart';

enum ReportGranularity { day, month }

class ReportRow {
  final String label;
  final String sortKey;
  final double cash;
  final double card;
  final double total;
  final double cgst;
  final double sgstIgst;
  final double grandTotal;

  const ReportRow({
    required this.label,
    required this.sortKey,
    required this.cash,
    required this.card,
    required this.total,
    required this.cgst,
    required this.sgstIgst,
    required this.grandTotal,
  });

  static ReportRow zero({required String label, required String sortKey}) {
    return ReportRow(
      label: label,
      sortKey: sortKey,
      cash: 0,
      card: 0,
      total: 0,
      cgst: 0,
      sgstIgst: 0,
      grandTotal: 0,
    );
  }

  ReportRow operator +(ReportRow other) {
    return ReportRow(
      label: label,
      sortKey: sortKey,
      cash: cash + other.cash,
      card: card + other.card,
      total: total + other.total,
      cgst: cgst + other.cgst,
      sgstIgst: sgstIgst + other.sgstIgst,
      grandTotal: grandTotal + other.grandTotal,
    );
  }
}

class ReportBreakdown {
  final ReportGranularity granularity;
  final List<ReportRow> rows;
  final ReportRow grandTotal;

  const ReportBreakdown({
    required this.granularity,
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
    final granularity = _granularityForRange(from, to);

    final buckets = <String, _MutableTotals>{};
    for (final period in _periodsForRange(from, to, granularity)) {
      buckets[period.sortKey] = _MutableTotals();
    }

    for (final code in allLocationCodes) {
      await LocationSeedService.ensureLocationSeeded(code);
      final entries = await LocationDatabase.getLedgerEntries(
        location: displayNameForLocationCode(code),
        from: fromKey,
        to: toKey,
      );
      for (final entry in entries) {
        final bucketKey = _bucketKeyForBillDate(entry.billDate, granularity);
        final bucket = buckets[bucketKey];
        if (bucket == null) continue;
        bucket.addEntry(entry);
      }
    }

    final rows = <ReportRow>[];
    for (final period in _periodsForRange(from, to, granularity)) {
      final totals = buckets[period.sortKey] ?? _MutableTotals();
      rows.add(totals.toRow(label: period.label, sortKey: period.sortKey));
    }

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
      granularity: granularity,
      rows: rows,
      grandTotal: ReportRow(
        label: 'Grand Total',
        sortKey: 'grand_total',
        cash: cash,
        card: card,
        total: total,
        cgst: cgst,
        sgstIgst: sgstIgst,
        grandTotal: grandTotalAmount,
      ),
    );
  }

  static bool isSingleCalendarMonth(DateTime fromDate, DateTime toDate) {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    return from.year == to.year && from.month == to.month;
  }

  static ReportGranularity _granularityForRange(DateTime from, DateTime to) {
    return isSingleCalendarMonth(from, to)
        ? ReportGranularity.day
        : ReportGranularity.month;
  }

  static List<({String label, String sortKey})> _periodsForRange(
    DateTime from,
    DateTime to,
    ReportGranularity granularity,
  ) {
    if (granularity == ReportGranularity.day) {
      final periods = <({String label, String sortKey})>[];
      var cursor = from;
      while (!cursor.isAfter(to)) {
        periods.add((
          label: DateFormat('dd MMM yyyy').format(cursor),
          sortKey: _dateKey(cursor),
        ));
        cursor = cursor.add(const Duration(days: 1));
      }
      return periods;
    }

    final periods = <({String label, String sortKey})>[];
    var year = from.year;
    var month = from.month;
    final endYear = to.year;
    final endMonth = to.month;

    while (year < endYear || (year == endYear && month <= endMonth)) {
      final monthDate = DateTime(year, month, 1);
      periods.add((
        label: DateFormat('MMM yyyy').format(monthDate),
        sortKey: '${year.toString().padLeft(4, '0')}-'
            '${month.toString().padLeft(2, '0')}',
      ));
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }

    return periods;
  }

  static String _bucketKeyForBillDate(
    String billDate,
    ReportGranularity granularity,
  ) {
    if (granularity == ReportGranularity.day) {
      return billDate;
    }

    try {
      final parsed = DateTime.parse(billDate);
      return '${parsed.year.toString().padLeft(4, '0')}-'
          '${parsed.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return billDate.length >= 7 ? billDate.substring(0, 7) : billDate;
    }
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _MutableTotals {
  double cash = 0;
  double card = 0;
  double total = 0;
  double cgst = 0;
  double sgstIgst = 0;
  double grandTotal = 0;

  void addEntry(LocalLedgerEntry entry) {
    if (_isCashPayment(entry.paymentMode)) {
      cash += entry.grandTotal;
    } else {
      card += entry.grandTotal;
    }
    total += entry.totalAmount;
    cgst += entry.totalCgst;
    sgstIgst += entry.totalSgst + entry.totalIgst;
    grandTotal += entry.grandTotal;
  }

  ReportRow toRow({required String label, required String sortKey}) {
    return ReportRow(
      label: label,
      sortKey: sortKey,
      cash: cash,
      card: card,
      total: total,
      cgst: cgst,
      sgstIgst: sgstIgst,
      grandTotal: grandTotal,
    );
  }

  bool _isCashPayment(String mode) => mode.toUpperCase() == 'CASH';
}
