import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/repositories/ledger_repository.dart';

class LedgerPdfService {
  static Future<String> saveLedgerPdf({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final bytes = await _buildPdfBytes(
      location: location,
      entries: entries,
      summary: summary,
      fromDate: fromDate,
      toDate: toDate,
    );

    final saveDir = await _saveDirectory();
    final fromPart = DateFormat('dd-MM-yyyy').format(fromDate);
    final toPart = DateFormat('dd-MM-yyyy').format(toDate);
    final rangePart = fromPart == toPart ? fromPart : '${fromPart}_to_$toPart';
    final fileName = 'Ledger_${location}_$rangePart.pdf';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> shareLedgerPdf({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final bytes = await _buildPdfBytes(
      location: location,
      entries: entries,
      summary: summary,
      fromDate: fromDate,
      toDate: toDate,
    );

    final fromPart = DateFormat('dd-MM-yyyy').format(fromDate);
    final toPart = DateFormat('dd-MM-yyyy').format(toDate);
    final rangePart = fromPart == toPart ? fromPart : '${fromPart}_to_$toPart';

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Ledger_${location}_$rangePart.pdf',
    );
  }

  static Future<Uint8List> _buildPdfBytes({
    required String location,
    required List<LocalLedgerEntry> entries,
    required LedgerSummary summary,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final doc = pw.Document();
    final headerStyle = pw.TextStyle(
      font: pw.Font.helveticaBold(),
      fontSize: 11,
      color: PdfColors.black,
    );
    final cellStyle = pw.TextStyle(
      font: pw.Font.helvetica(),
      fontSize: 8,
      color: PdfColors.black,
    );
    final money = NumberFormat('#,##0.00');

    final fromPart = DateFormat('dd-MMM-yy').format(fromDate);
    final toPart = DateFormat('dd-MMM-yy').format(toDate);
    final rangeLabel =
        fromPart == toPart ? fromPart : '$fromPart — $toPart';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text('SALES LEDGER — $location', style: headerStyle),
          pw.SizedBox(height: 4),
          pw.Text('Period: $rangeLabel', style: cellStyle),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'BILLNO',
              'DATE',
              'NAME',
              'MOBILE',
              'CASH',
              'CARD/UPI',
              'TOTAL',
              'GST',
              'GRAND TOTAL',
            ],
            data: [
              for (final entry in entries)
                [
                  '${entry.billNo}',
                  _formatDate(entry.date),
                  entry.customerName,
                  entry.mobile.isEmpty ? '—' : entry.mobile,
                  _cashColumnAmount(entry),
                  _cardColumnAmount(entry),
                  money.format(entry.total),
                  money.format(entry.cgst + entry.sgst + entry.igst),
                  money.format(entry.grandTotal),
                ],
              [
                '',
                '',
                '',
                '',
                money.format(_cashTotal(entries)),
                money.format(_cardTotal(entries)),
                money.format(summary.total),
                money.format(summary.cgst + summary.sgst + summary.igst),
                money.format(summary.grandTotal),
              ],
            ],
            headerStyle: pw.TextStyle(
              font: pw.Font.helveticaBold(),
              fontSize: 8,
            ),
            cellStyle: cellStyle,
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 20,
          ),
        ],
      ),
    );

    return doc.save();
  }

  static String _formatDate(String value) {
    try {
      return DateFormat('dd-MMM-yy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  static String formatPayMode(String mode) {
    final upper = mode.toUpperCase();
    if (upper == 'CASH') {
      return 'CASH';
    }
    return 'CARD/UPI';
  }

  static bool _isCashPayment(String mode) => mode.toUpperCase() == 'CASH';

  static String _cashColumnAmount(LocalLedgerEntry entry) {
    if (!_isCashPayment(entry.paymentMode)) {
      return '';
    }
    return NumberFormat('#,##0.00').format(entry.grandTotal);
  }

  static String _cardColumnAmount(LocalLedgerEntry entry) {
    if (_isCashPayment(entry.paymentMode)) {
      return '';
    }
    return NumberFormat('#,##0.00').format(entry.grandTotal);
  }

  static double _cashTotal(List<LocalLedgerEntry> entries) {
    return entries
        .where((entry) => _isCashPayment(entry.paymentMode))
        .fold(0.0, (sum, entry) => sum + entry.grandTotal);
  }

  static double _cardTotal(List<LocalLedgerEntry> entries) {
    return entries
        .where((entry) => !_isCashPayment(entry.paymentMode))
        .fold(0.0, (sum, entry) => sum + entry.grandTotal);
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