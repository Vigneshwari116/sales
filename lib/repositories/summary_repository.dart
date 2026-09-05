import 'package:intl/intl.dart';

import 'package:sales/db/summary_db.dart';

class SummaryRepository {
  static Future<double> getTodayTotal({String? location}) {
    if (location == null) {
      return SummaryDb.instance.getTodayTotalAllLocations();
    }
    final today = DateTime.now();
    final day = _dayKey(today);
    return SummaryDb.instance.getTotalForDay(day: day, location: location);
  }

  static Future<double> getRangeTotal({
    required DateTime fromDate,
    required DateTime toDate,
    String? location,
  }) {
    return SummaryDb.instance.getRangeTotal(
      fromDate: fromDate,
      toDate: toDate,
      location: location,
    );
  }

  static Future<List<MonthSummaryRow>> getMonthTotalsForYear({
    required int year,
    String? location,
  }) {
    return SummaryDb.instance.getMonthTotalsForYear(
      year: year,
      location: location,
    );
  }

  static Future<List<DaySummaryRow>> getDayTotalsForMonth({
    required int year,
    required int month,
    String? location,
  }) {
    return SummaryDb.instance.getDayTotalsForMonth(
      year: year,
      month: month,
      location: location,
    );
  }

  static String formatMonthLabel(int month) {
    return DateFormat('MMMM').format(DateTime(2000, month, 1));
  }

  static String _dayKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
