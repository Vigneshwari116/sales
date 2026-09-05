import 'package:intl/intl.dart';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/services/location_seed_service.dart';

enum ReportGranularity { day, month }

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

  static ReportTotals fromBills(Iterable<ReportBillRow> bills) {
    var cash = 0.0;
    var card = 0.0;
    var total = 0.0;
    var cgst = 0.0;
    var sgstIgst = 0.0;
    var grandTotalAmount = 0.0;

    for (final bill in bills) {
      cash += bill.cash;
      card += bill.card;
      total += bill.total;
      cgst += bill.cgst;
      sgstIgst += bill.sgstIgst;
      grandTotalAmount += bill.grandTotal;
    }

    return ReportTotals(
      cash: cash,
      card: card,
      total: total,
      cgst: cgst,
      sgstIgst: sgstIgst,
      grandTotal: grandTotalAmount,
    );
  }
}

class ReportPeriodGroup {
  final String label;
  final String sortKey;
  final List<ReportBillRow> bills;
  final ReportTotals subtotal;

  const ReportPeriodGroup({
    required this.label,
    required this.sortKey,
    required this.bills,
    required this.subtotal,
  });
}

class ReportBreakdown {
  final ReportGranularity granularity;
  final List<ReportPeriodGroup> groups;
  final ReportTotals grandTotal;

  const ReportBreakdown({
    required this.granularity,
    required this.groups,
    required this.grandTotal,
  });

  bool get hasBills => groups.any((group) => group.bills.isNotEmpty);

  String get periodTotalLabel =>
      granularity == ReportGranularity.day ? 'Day Total' : 'Month Total';
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

    final billsByPeriod = <String, List<ReportBillRow>>{};
    for (final period in _periodsForRange(from, to, granularity)) {
      billsByPeriod[period.sortKey] = [];
    }

    for (final code in allLocationCodes) {
      await LocationSeedService.ensureLocationSeeded(code);
      final entries = await LocationDatabase.getLedgerEntries(
        location: displayNameForLocationCode(code),
        from: fromKey,
        to: toKey,
      );

      for (final entry in entries) {
        final periodKey = _bucketKeyForBillDate(entry.billDate, granularity);
        final bucket = billsByPeriod[periodKey];
        if (bucket == null) continue;
        bucket.add(_entryToRow(entry));
      }
    }

    final groups = <ReportPeriodGroup>[];
    for (final period in _periodsForRange(from, to, granularity)) {
      final bills = billsByPeriod[period.sortKey] ?? [];
      bills.sort((left, right) {
        final dateCompare = right.date.compareTo(left.date);
        if (dateCompare != 0) return dateCompare;
        return right.billNo.compareTo(left.billNo);
      });

      groups.add(
        ReportPeriodGroup(
          label: period.label,
          sortKey: period.sortKey,
          bills: List.unmodifiable(bills),
          subtotal: ReportTotals.fromBills(bills),
        ),
      );
    }

    return ReportBreakdown(
      granularity: granularity,
      groups: groups,
      grandTotal: ReportTotals.fromBills(
        groups.expand((group) => group.bills),
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
