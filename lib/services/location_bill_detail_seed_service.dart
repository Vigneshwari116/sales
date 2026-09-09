import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/config/location_codes.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/location_seed_service.dart';

class LocationBillDetailSeedService {
  static const _seedVersion = '1';
  static final Map<String, Future<void>> _activeSeeds = {};
  static const _assetByLocation = {
    'win1': 'assets/seed/win1_bill_detail.csv',
    'win2': 'assets/seed/win2_bill_detail.csv',
    'win3': 'assets/seed/win3_bill_detail.csv',
  };

  static const _expectedHeaders = [
    'BILLNO',
    'DATE',
    'TIME',
    'LINENO',
    'QTY',
    'RATE',
    'AMOUNT',
    'DISCOUNT%',
    'DISCOUNTAMT',
    'CGSTAMT',
    'SGSTAMT',
    'IGST%',
    'IGSTAMT',
    'TOTALAMT',
    'PAYMENTMODE',
  ];

  static Future<void> ensureAllLocationsSeeded() async {
    for (final code in allLocationCodes) {
      await ensureLocationSeeded(code);
    }
  }

  static Future<void> ensureLocationSeeded(String locationCode) async {
    if (!isActiveLocationCode(locationCode)) {
      return;
    }

    await LocationSeedService.ensureLocationSeeded(locationCode);

    final running = _activeSeeds[locationCode];
    if (running != null) {
      await running;
      return;
    }

    final task = _seedLocation(locationCode);
    _activeSeeds[locationCode] = task;
    try {
      await task;
    } finally {
      _activeSeeds.remove(locationCode);
    }
  }

  static Future<void> _seedLocation(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final seedKey = 'location_bill_detail_seed_${locationCode}_v$_seedVersion';
    if (prefs.getBool(seedKey) == true) {
      return;
    }

    final assetPath = _assetByLocation[locationCode];
    if (assetPath == null) {
      return;
    }

    final content = await rootBundle.loadString(assetPath);
    final parsed = _parseCsv(content);
    if (!parsed.ok || parsed.detailsByBillNo.isEmpty) {
      return;
    }

    await LocationDatabase.applyImportedBillDetails(
      locationCode: locationCode,
      detailsByBillNo: parsed.detailsByBillNo,
    );

    await prefs.setBool(seedKey, true);
  }

  static ({
    bool ok,
    Map<int, ImportedBillDetail> detailsByBillNo,
    String? error,
  }) _parseCsv(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (lines.isEmpty) {
      return (ok: false, detailsByBillNo: const {}, error: 'CSV file is empty');
    }

    final header = _splitCsvLine(lines.first)
        .map((value) => value.trim().toUpperCase())
        .toList(growable: false);

    if (!_headersMatch(header)) {
      return (
        ok: false,
        detailsByBillNo: const {},
        error: 'Unexpected CSV header. Expected bill detail columns.',
      );
    }

    final lineRows = <_CsvLineRow>[];

    for (final line in lines.skip(1)) {
      final values = _splitCsvLine(line);
      if (values.length < _expectedHeaders.length) {
        continue;
      }

      final billNo = int.tryParse(values[0].trim());
      final billDate = _parseBillDate(values[1].trim());
      final lineNo = int.tryParse(values[3].trim());
      final qty = _parseAmount(values[4]);
      final rate = _parseAmount(values[5]);
      final amount = _parseAmount(values[6]);
      final cgstAmt = _parseAmount(values[9]);
      final sgstAmt = _parseAmount(values[10]);
      final igstPct = _parseAmount(values[11]);
      final igstAmt = _parseAmount(values[12]);
      final totalAmt = _parseAmount(values[13]);
      final paymentMode = values[14].trim();

      if (billNo == null ||
          billNo <= 0 ||
          billDate == null ||
          lineNo == null ||
          lineNo <= 0 ||
          qty <= 0 ||
          rate <= 0) {
        continue;
      }

      lineRows.add(
        _CsvLineRow(
          billNo: billNo,
          billDate: billDate,
          lineNo: lineNo,
          qty: qty,
          rate: rate,
          amount: amount,
          cgstAmt: cgstAmt,
          sgstAmt: sgstAmt,
          igstPct: igstPct,
          igstAmt: igstAmt,
          totalAmt: totalAmt,
          paymentMode: paymentMode,
        ),
      );
    }

    final grouped = <int, List<_CsvLineRow>>{};
    for (final row in lineRows) {
      grouped.putIfAbsent(row.billNo, () => []).add(row);
    }

    final detailsByBillNo = <int, ImportedBillDetail>{};
    for (final entry in grouped.entries) {
      final rows = entry.value;
      rows.sort((left, right) => left.lineNo.compareTo(right.lineNo));

      final items = rows.map(_toBillItem).toList(growable: false);
      final paymentMode = rows
          .map((row) => row.paymentMode)
          .firstWhere((mode) => mode.isNotEmpty, orElse: () => '');

      detailsByBillNo[entry.key] = ImportedBillDetail(
        billNo: entry.key,
        billDate: rows.first.billDate,
        paymentMode: _paymentModeFromCsv(paymentMode),
        items: items,
      );
    }

    return (ok: true, detailsByBillNo: detailsByBillNo, error: null);
  }

  static BillItem _toBillItem(_CsvLineRow row) {
    final grossAmt = row.totalAmt > 0 ? row.totalAmt : row.qty * row.rate;
    final taxable = row.amount > 0 ? row.amount : grossAmt;
    final totalTax = row.cgstAmt + row.sgstAmt + row.igstAmt;

    if (row.igstAmt > 0 || row.igstPct > 0) {
      final double pct = row.igstPct > 0
          ? row.igstPct
          : taxable > 0
              ? (row.igstAmt / taxable) * 100
              : 0.0;
      return BillItem(
        qty: row.qty,
        rate: row.rate,
        cgstPct: 0.0,
        sgstPct: 0.0,
        igstPct: pct,
      );
    }

    final double cgstPct =
        taxable > 0 ? (row.cgstAmt / taxable) * 100 : 2.5;
    final double sgstPct =
        taxable > 0 ? (row.sgstAmt / taxable) * 100 : 2.5;

    if (totalTax <= 0) {
      return BillItem(
        qty: row.qty,
        rate: row.rate,
        cgstPct: 0.0,
        sgstPct: 0.0,
      );
    }

    return BillItem(
      qty: row.qty,
      rate: row.rate,
      cgstPct: cgstPct,
      sgstPct: sgstPct,
    );
  }

  static String? _parseBillDate(String value) {
    if (value.isEmpty) {
      return null;
    }

    try {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        return value;
      }

      final parsed = DateFormat('dd-MMM-yy').parse(value);
      return DateFormat('yyyy-MM-dd').format(parsed);
    } catch (_) {
      return null;
    }
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

  static String _paymentModeFromCsv(String mode) {
    final upper = mode.trim().toUpperCase();
    if (upper.isEmpty) {
      return '';
    }
    if (upper == 'CASH') {
      return 'CASH';
    }
    if (upper == 'PPP' || upper == 'UPI') {
      return 'UPI';
    }
    return 'CARD';
  }
}

class _CsvLineRow {
  final int billNo;
  final String billDate;
  final int lineNo;
  final double qty;
  final double rate;
  final double amount;
  final double cgstAmt;
  final double sgstAmt;
  final double igstPct;
  final double igstAmt;
  final double totalAmt;
  final String paymentMode;

  const _CsvLineRow({
    required this.billNo,
    required this.billDate,
    required this.lineNo,
    required this.qty,
    required this.rate,
    required this.amount,
    required this.cgstAmt,
    required this.sgstAmt,
    required this.igstPct,
    required this.igstAmt,
    required this.totalAmt,
    required this.paymentMode,
  });
}

