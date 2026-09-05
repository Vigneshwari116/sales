import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:sales/repositories/report_repository.dart';

class ReportExcelService {
  static Future<String> saveAndShareReport({
    required ReportBreakdown breakdown,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final bytes = _buildWorkbookBytes(
      breakdown: breakdown,
      fromDate: fromDate,
      toDate: toDate,
    );

    final saveDir = await _saveDirectory();
    final fileName = _fileName(
      breakdown: breakdown,
      fromDate: fromDate,
      toDate: toDate,
    );
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: 'Sales report',
      text: 'Sales report $fileName',
    );

    return file.path;
  }

  @visibleForTesting
  static Uint8List buildWorkbookBytes({
    required ReportBreakdown breakdown,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    return _buildWorkbookBytes(
      breakdown: breakdown,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  static Uint8List _buildWorkbookBytes({
    required ReportBreakdown breakdown,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Report';
    final sheet = excel[sheetName];
    final money = NumberFormat('#,##0.00');

    final periodHeader =
        breakdown.granularity == ReportGranularity.day ? 'DAY' : 'MONTH';
    final headers = [
      periodHeader,
      'CASH',
      'CARD/UPI',
      'TOTAL',
      'CGST',
      'SGST/IGST',
      'GRAND TOTAL',
    ];

    for (var column = 0; column < headers.length; column++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
          .value = TextCellValue(headers[column]);
    }

    var rowIndex = 1;
    for (final row in breakdown.rows) {
      _writeRow(
        sheet: sheet,
        rowIndex: rowIndex,
        label: row.label,
        cash: money.format(row.cash),
        card: money.format(row.card),
        total: money.format(row.total),
        cgst: money.format(row.cgst),
        sgstIgst: money.format(row.sgstIgst),
        grandTotal: money.format(row.grandTotal),
      );
      rowIndex++;
    }

    _writeRow(
      sheet: sheet,
      rowIndex: rowIndex,
      label: 'Grand Total',
      cash: money.format(breakdown.grandTotal.cash),
      card: money.format(breakdown.grandTotal.card),
      total: money.format(breakdown.grandTotal.total),
      cgst: money.format(breakdown.grandTotal.cgst),
      sgstIgst: money.format(breakdown.grandTotal.sgstIgst),
      grandTotal: money.format(breakdown.grandTotal.grandTotal),
    );

    return Uint8List.fromList(excel.encode()!);
  }

  static void _writeRow({
    required Sheet sheet,
    required int rowIndex,
    required String label,
    required String cash,
    required String card,
    required String total,
    required String cgst,
    required String sgstIgst,
    required String grandTotal,
  }) {
    final values = [label, cash, card, total, cgst, sgstIgst, grandTotal];
    for (var column = 0; column < values.length; column++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: rowIndex))
          .value = TextCellValue(values[column]);
    }
  }

  static String _fileName({
    required ReportBreakdown breakdown,
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    final fromPart = DateFormat('dd-MM-yyyy').format(fromDate);
    final toPart = DateFormat('dd-MM-yyyy').format(toDate);
    final rangePart = fromPart == toPart ? fromPart : '${fromPart}_to_$toPart';
    final granularityPart =
        breakdown.granularity == ReportGranularity.day ? 'Daily' : 'Monthly';
    return 'Report_${granularityPart}_$rangePart.xlsx';
  }

  static Future<String> _saveDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}
