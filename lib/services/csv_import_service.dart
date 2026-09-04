import 'dart:io';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/location_database.dart';

class CsvImportResult {
  final bool ok;
  final int importedCount;
  final int skippedCount;
  final String? error;

  const CsvImportResult({
    required this.ok,
    required this.importedCount,
    required this.skippedCount,
    this.error,
  });
}

class CsvImportService {
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

  static Future<CsvImportResult> importFile({
    required String locationCode,
    required String filePath,
  }) async {
    if (!isActiveLocationCode(locationCode)) {
      return const CsvImportResult(
        ok: false,
        importedCount: 0,
        skippedCount: 0,
        error: 'Invalid location',
      );
    }

    try {
      final content = await File(filePath).readAsString();
      return importCsvContent(
        locationCode: locationCode,
        content: content,
      );
    } catch (error) {
      return CsvImportResult(
        ok: false,
        importedCount: 0,
        skippedCount: 0,
        error: 'Could not read file: $error',
      );
    }
  }

  static Future<CsvImportResult> importCsvContent({
    required String locationCode,
    required String content,
  }) async {
    final parsed = _parseCsv(content);
    if (!parsed.ok) {
      return CsvImportResult(
        ok: false,
        importedCount: 0,
        skippedCount: 0,
        error: parsed.error,
      );
    }

    if (parsed.rows.isEmpty) {
      return const CsvImportResult(
        ok: false,
        importedCount: 0,
        skippedCount: 0,
        error: 'No bill rows found in CSV',
      );
    }

    final imported = await LocationDatabase.upsertImportedBills(
      locationCode: locationCode,
      rows: parsed.rows,
    );

    return CsvImportResult(
      ok: true,
      importedCount: imported,
      skippedCount: parsed.skippedCount,
    );
  }

  static ({
    bool ok,
    List<ImportedBillRow> rows,
    int skippedCount,
    String? error,
  }) _parseCsv(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return (
        ok: false,
        rows: const [],
        skippedCount: 0,
        error: 'CSV file is empty',
      );
    }

    final header = _splitCsvLine(lines.first)
        .map((value) => value.trim().toUpperCase())
        .toList(growable: false);

    if (!_headersMatch(header)) {
      return (
        ok: false,
        rows: const [],
        skippedCount: 0,
        error: 'Unexpected CSV header. Expected sales report columns.',
      );
    }

    final rows = <ImportedBillRow>[];
    var skipped = 0;

    for (final line in lines.skip(1)) {
      final values = _splitCsvLine(line);
      if (values.length < _expectedHeaders.length) {
        skipped++;
        continue;
      }

      final billNo = int.tryParse(values[0].trim());
      final billDate = values[1].trim();
      final name = values[2].trim();
      final mobile = values[3].trim();
      final cash = _parseAmount(values[4]);
      final cardUpi = _parseAmount(values[5]);
      final totalAmount = _parseAmount(values[6]);
      final totalCgst = _parseAmount(values[7]);
      final totalSgst = _parseAmount(values[8]);
      final totalIgst = _parseAmount(values[9]);
      final grandTotal = _parseAmount(values[10]);

      if (billNo == null || billNo <= 0 || billDate.isEmpty) {
        skipped++;
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
          totalAmount: totalAmount,
          totalCgst: totalCgst,
          totalSgst: totalSgst,
          totalIgst: totalIgst,
          grandTotal: grandTotal,
        ),
      );
    }

    return (ok: true, rows: rows, skippedCount: skipped, error: null);
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
