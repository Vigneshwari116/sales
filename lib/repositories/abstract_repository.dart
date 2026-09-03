import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';

class AbstractSummary {
  final double totalSaleAmount;
  final double totalGst;

  AbstractSummary({
    required this.totalSaleAmount,
    required this.totalGst,
  });

  static AbstractSummary zero() =>
      AbstractSummary(totalSaleAmount: 0, totalGst: 0);
}

class AbstractRepository {
  static Future<AbstractSummary> getSummaryForDateRange({
    required String location,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final code = _locationCodeFromDisplayName(location);
    return getSummaryForLocationCode(
      locationCode: code,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  static Future<AbstractSummary> getSummaryForLocationCode({
    required String locationCode,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final fromKey = _formatDate(fromDate);
      final toKey = _formatDate(toDate);
      final rows = await _readBillsForLocationCode(locationCode);

      var totalSaleAmount = 0.0;
      var totalGst = 0.0;

      for (final row in rows) {
        final totals = _totalsForRow(row, fromKey: fromKey, toKey: toKey);
        if (totals == null) continue;
        totalSaleAmount += totals.$1;
        totalGst += totals.$2;
      }

      return AbstractSummary(
        totalSaleAmount: totalSaleAmount,
        totalGst: totalGst,
      );
    } catch (_) {
      return AbstractSummary.zero();
    }
  }

  static Future<AbstractSummary> getCrossLocationSummary({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    var totalSale = 0.0;
    var totalGst = 0.0;

    for (final code in allLocationCodes) {
      final summary = await getSummaryForLocationCode(
        locationCode: code,
        fromDate: fromDate,
        toDate: toDate,
      );
      totalSale += summary.totalSaleAmount;
      totalGst += summary.totalGst;
    }

    return AbstractSummary(
      totalSaleAmount: totalSale,
      totalGst: totalGst,
    );
  }

  static Future<List<Map<String, dynamic>>> _readBillsForLocationCode(
    String locationCode,
  ) async {
    final locationName = displayNameForLocationCode(locationCode);

    if (AppConfig.isLocationSet && AppConfig.locationCode == locationCode) {
      try {
        await LocalDb.instance.initialize();
        final entries = await LocalDb.instance.getLedgerEntries(locationName);
        return entries
            .map(
              (entry) => {
                'bill_date': entry.billDate,
                'total_amount': entry.totalAmount,
                'grand_total': entry.grandTotal,
                'total_cgst': entry.totalCgst,
                'total_sgst': entry.totalSgst,
                'total_igst': entry.totalIgst,
              },
            )
            .toList(growable: false);
      } catch (_) {
        return const [];
      }
    }

    final supportDir = await getApplicationSupportDirectory();
    final dbPath = join(supportDir.path, '${locationCode}_sales.db');
    if (await File(dbPath).exists()) {
      return _readBillsFromLocationFile(
        locationCode: locationCode,
        locationName: locationName,
      );
    }

    return const [];
  }

  static Future<List<Map<String, dynamic>>> _readBillsFromLocationFile({
    required String locationCode,
    required String locationName,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final path = join(supportDir.path, '${locationCode}_sales.db');
    final file = File(path);
    if (!await file.exists()) {
      return const [];
    }

    // Use a separate connection so closing it does not shut down LocalDb.
    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      return await db.query(
        'bills',
        where: 'deleted = 0 AND location = ?',
        whereArgs: [locationName],
        columns: [
          'bill_date',
          'total_amount',
          'grand_total',
          'total_cgst',
          'total_sgst',
          'total_igst',
        ],
      );
    } finally {
      await db.close();
    }
  }

  static String _locationCodeFromDisplayName(String location) {
    switch (location) {
      case 'Win1':
        return 'win1';
      case 'Win2':
        return 'win2';
      case 'Win3':
        return 'win3';
      case 'Win4':
        return 'win4';
      default:
        return location.toLowerCase();
    }
  }

  static (double, double)? _totalsForRow(
    Map<String, dynamic> row, {
    required String fromKey,
    required String toKey,
  }) {
    final billDate = row['bill_date'] as String?;
    if (billDate == null) return null;
    if (billDate.compareTo(fromKey) < 0 || billDate.compareTo(toKey) > 0) {
      return null;
    }

    final saleAmount = (row['total_amount'] as num?)?.toDouble() ??
        (row['grand_total'] as num?)?.toDouble() ??
        0;
    final cgst = (row['total_cgst'] as num?)?.toDouble() ?? 0;
    final sgst = (row['total_sgst'] as num?)?.toDouble() ?? 0;
    final igst = (row['total_igst'] as num?)?.toDouble() ?? 0;

    return (saleAmount, cgst + sgst + igst);
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
