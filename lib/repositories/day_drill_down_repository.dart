import 'package:intl/intl.dart';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/services/location_bill_detail_seed_service.dart';
import 'package:sales/services/location_seed_service.dart';

class DaySummaryRow {
  final String day;
  final String label;
  final double grandTotal;
  final bool hasLineItemDetail;

  const DaySummaryRow({
    required this.day,
    required this.label,
    required this.grandTotal,
    required this.hasLineItemDetail,
  });
}

class DayBillRow {
  final String localId;
  final String location;
  final int billNo;
  final String date;
  final String customerName;
  final String mobile;
  final String paymentMode;
  final double total;
  final double gst;
  final double grandTotal;
  final String syncStatus;

  const DayBillRow({
    required this.localId,
    required this.location,
    required this.billNo,
    required this.date,
    required this.customerName,
    required this.mobile,
    required this.paymentMode,
    required this.total,
    required this.gst,
    required this.grandTotal,
    required this.syncStatus,
  });
}

class DayDrillDownRepository {
  static const int fullDetailBillThreshold = 40;
  static const int compactBillListThreshold = 2000;

  static Future<List<DaySummaryRow>> getDaySummariesForMonth({
    required int year,
    required int month,
    String? location,
  }) async {
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 0);
    return getDaySummaries(
      fromDate: from,
      toDate: to,
      location: location,
    );
  }

  static Future<List<DaySummaryRow>> getDaySummaries({
    required DateTime fromDate,
    required DateTime toDate,
    String? location,
  }) async {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    final summaries = <String, _MutableDaySummary>{};

    final locationNames = location == null
        ? allLocationCodes.map(displayNameForLocationCode).toList()
        : [location];

    for (final code in allLocationCodes) {
      final locationName = displayNameForLocationCode(code);
      if (!locationNames.contains(locationName)) {
        continue;
      }

      await LocationSeedService.ensureLocationSeeded(code);
      await LocationBillDetailSeedService.ensureLocationSeeded(code);

      final entries = await LocationDatabase.getLedgerEntries(
        location: locationName,
        from: _dateKey(from),
        to: _dateKey(to),
      );

      for (final entry in entries) {
        final bucket = summaries.putIfAbsent(
          entry.billDate,
          () => _MutableDaySummary(day: entry.billDate),
        );
        bucket.grandTotal += entry.grandTotal;
      }
    }

    final rows = <DaySummaryRow>[];
    for (final summary in summaries.values) {
      final hasDetail = await dayHasLineItemDetail(
        day: summary.day,
        location: location,
      );
      rows.add(
        DaySummaryRow(
          day: summary.day,
          label: _formatDayLabel(summary.day),
          grandTotal: summary.grandTotal,
          hasLineItemDetail: hasDetail,
        ),
      );
    }

    rows.sort((left, right) => right.day.compareTo(left.day));
    return rows;
  }

  static Future<List<DayBillRow>> getBillsForDay({
    required String day,
    String? location,
  }) async {
    final bills = <DayBillRow>[];

    final locationNames = location == null
        ? allLocationCodes.map(displayNameForLocationCode).toList()
        : [location];

    for (final code in allLocationCodes) {
      final locationName = displayNameForLocationCode(code);
      if (!locationNames.contains(locationName)) {
        continue;
      }

      await LocationSeedService.ensureLocationSeeded(code);
      await LocationBillDetailSeedService.ensureLocationSeeded(code);

      final entries = await LocationDatabase.getLedgerEntries(
        location: locationName,
        from: day,
        to: day,
      );

      for (final entry in entries) {
        bills.add(
          DayBillRow(
            localId: entry.localId,
            location: entry.location,
            billNo: entry.billNo,
            date: entry.billDate,
            customerName: entry.customerName,
            mobile: entry.mobile,
            paymentMode: entry.paymentMode,
            total: entry.totalAmount,
            gst: entry.totalCgst + entry.totalSgst + entry.totalIgst,
            grandTotal: entry.grandTotal,
            syncStatus: entry.syncStatus,
          ),
        );
      }
    }

    bills.sort((left, right) => right.billNo.compareTo(left.billNo));
    return bills;
  }

  static Future<bool> dayHasLineItemDetail({
    required String day,
    String? location,
  }) async {
    final locationNames = location == null
        ? allLocationCodes.map(displayNameForLocationCode).toList()
        : [location];

    for (final locationName in locationNames) {
      final hasDetail = await LocationDatabase.dayHasLineItemDetail(
        location: locationName,
        day: day,
      );
      if (hasDetail) {
        return true;
      }
    }
    return false;
  }

  static bool shouldUseCompactBillList(int billCount) {
    return billCount >= compactBillListThreshold;
  }

  static bool shouldShowFullBillDetails(int billCount) {
    return billCount <= fullDetailBillThreshold;
  }

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _formatDayLabel(String day) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(day));
    } catch (_) {
      return day;
    }
  }
}

class _MutableDaySummary {
  final String day;
  double grandTotal = 0;

  _MutableDaySummary({required this.day});
}
