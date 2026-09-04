import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/location_database.dart';

class LocationSeedService {
  static const _seedVersion = '1';
  static const _assetByLocation = {
    'win1': 'assets/seed/win1_sales.csv',
    'win2': 'assets/seed/win2_sales.csv',
    'win3': 'assets/seed/win3_sales.csv',
  };

  static const _expectedHeaders = [
    'BILLNO',
    'DATE',
    'NAME',
    'MOBILE',
    'CASH',
    'CARD/UPI',
    'TOTAL',
    'CGST',
    'SGST',
    'IGST',
    'GRAND TOTAL',
  ];

  /// Loads bundled sales CSV data into each location database when empty.
  static Future<void> ensureAllLocationsSeeded() async {
    for (final code in allLocationCodes) {
      await ensureLocationSeeded(code);
    }
  }

  static Future<void> ensureLocationSeeded(String locationCode) async {
    if (!isActiveLocationCode(locationCode)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final seedKey = 'location_seed_${locationCode}_v$_seedVersion';
    if (prefs.getBool(seedKey) == true) {
      return;
    }

    if (await LocationDatabase.hasBills(locationCode)) {
      await prefs.setBool(seedKey, true);
      return;
    }

    final assetPath = _assetByLocation[locationCode];
    if (assetPath == null) {
      return;
    }

    final content = await rootBundle.loadString(assetPath);
    final parsed = _parseCsv(content);
    if (!parsed.ok || parsed.rows.isEmpty) {
      return;
    }

    await LocationDatabase.upsertImportedBills(
      locationCode: locationCode,
      rows: parsed.rows,
    );

    await prefs.setBool(seedKey, true);
  }

  static ({
    bool ok,
    List<ImportedBillRow> rows,
    String? error,
  }) _parseCsv(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return (ok: false, rows: const [], error: 'CSV file is empty');
    }

    final header = _splitCsvLine(lines.first)
        .map((value) => value.trim().toUpperCase())
        .toList(growable: false);

    if (!_headersMatch(header)) {
      return (
        ok: false,
        rows: const [],
        error: 'Unexpected CSV header. Expected sales report columns.',
      );
    }

    final rows = <ImportedBillRow>[];

    for (final line in lines.skip(1)) {
      final values = _splitCsvLine(line);
      if (values.length < _expectedHeaders.length) {
        continue;
      }

      final billNo = int.tryParse(values[0].trim());
      final billDate = values[1].trim();
      final name = values[2].trim();
      final mobile = values[3].trim();
      final cash = _parseAmount(values[4]);
      final cardUpi = _parseAmount(values[5]);

      if (billNo == null || billNo <= 0 || billDate.isEmpty) {
        continue;
      }

      rows.add(
        ImportedBillRow(
          billNo: billNo,
          billDate: billDate,
          customerName: _customerNameFromCsv(name),
          mobile: mobile,
          paymentMode: _paymentModeFromCsv(
            cash: cash,
            cardUpi: cardUpi,
            name: name,
          ),
          totalAmount: _parseAmount(values[6]),
          totalCgst: _parseAmount(values[7]),
          totalSgst: _parseAmount(values[8]),
          totalIgst: _parseAmount(values[9]),
          grandTotal: _parseAmount(values[10]),
        ),
      );
    }

    return (ok: true, rows: rows, error: null);
  }

  static bool _headersMatch(List<String> header) {
    if (header.length != _expectedHeaders.length) {
      return false;
    }

    for (var index = 0; index < _expectedHeaders.length; index++) {
      if (header[index] != _expectedHeaders[index]) {
        return false;
      }
    }

    return true;
  }

  static List<String> _splitCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < line.length; index++) {
      final char = line[index];

      if (char == '"') {
        final isEscapedQuote =
            inQuotes && index + 1 < line.length && line[index + 1] == '"';
        if (isEscapedQuote) {
          buffer.write('"');
          index++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
        continue;
      }

      buffer.write(char);
    }

    values.add(buffer.toString());
    return values;
  }

  static double _parseAmount(String value) {
    return double.tryParse(value.trim()) ?? 0;
  }

  static String _customerNameFromCsv(String name) {
    final upper = name.trim().toUpperCase();
    if (upper.isEmpty || upper == 'CASH' || upper == 'CARD' || upper == 'PPP') {
      return '';
    }
    return name.trim();
  }

  static String _paymentModeFromCsv({
    required double cash,
    required double cardUpi,
    required String name,
  }) {
    if (cash > 0 && cardUpi == 0) {
      return 'CASH';
    }

    final upper = name.trim().toUpperCase();
    if (upper == 'UPI' || upper == 'PPP') {
      return 'UPI';
    }

    return 'CARD';
  }
}
