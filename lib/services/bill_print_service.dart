import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/services/receipt_service.dart';

class BillPrintService {
  static Future<String> saveReceiptToDesktop(SaleBill bill) async {
    final text = ReceiptService.buildReceiptText(bill);
    final saveDir = await _receiptSaveDirectory();
    final datePart = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final fileName = 'Bill_${bill.billNo}_$datePart.txt';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsString(text);
    return file.path;
  }

  static Future<String> saveReceiptPdfToDesktop(SaleBill bill) async {
    final bytes = await _buildPdfBytes(bill, type: PrinterType.thermal);
    final saveDir = await _receiptSaveDirectory();
    final datePart = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final fileName = 'Bill_${bill.billNo}_$datePart.pdf';
    final file = File('$saveDir${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<bool> printReceipt(
    SaleBill bill, {
    required String printerName,
    PrinterType type = PrinterType.thermal,
  }) async {
    if (type == PrinterType.fast) {
      throw UnsupportedError(
        'Fast printer routing is not configured yet. '
        'Persist a fast printer in settings, but assign its print flow '
        'before calling printReceipt with PrinterType.fast.',
      );
    }

    final printers = await Printing.listPrinters();
    Printer? printer;

    for (final candidate in printers) {
      if (candidate.name == printerName || candidate.url == printerName) {
        printer = candidate;
        break;
      }
    }

    if (printer == null) {
      throw Exception('Printer "$printerName" not found');
    }

    final pdfBytes = await _buildPdfBytes(bill, type: type);

    final printed = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => pdfBytes,
      name: 'Bill_${bill.billNo}',
      usePrinterSettings: false,
    );

    return printed;
  }

  @visibleForTesting
  static Future<Uint8List> buildPdfBytes(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) {
    return _buildPdfBytes(bill, type: type);
  }

  static Future<Uint8List> _buildPdfBytes(
    SaleBill bill, {
    required PrinterType type,
  }) async {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    final lines = text.split('\n');
    final doc = pw.Document();
    final fontSize = type == PrinterType.thermal ? 5.4 : 7.0;
    const lineHeightMm = 2.2;
    const verticalMarginMm = 2.5;
    const bottomBufferMm = 10.0;
    const thermalPageWidthMm = 101.6;

    final contentHeightMm =
        lines.length * lineHeightMm + verticalMarginMm * 2 + bottomBufferMm;
    final pageWidthMm =
        type == PrinterType.thermal ? thermalPageWidthMm : thermalPageWidthMm;
    final marginLeftMm = type == PrinterType.thermal ? 3.0 : 3.0;
    final marginRightMm = type == PrinterType.thermal ? 3.0 : 3.0;
    final printableWidthMm = pageWidthMm - marginLeftMm - marginRightMm;

    final style = pw.TextStyle(
      font: pw.Font.courierBold(),
      fontSize: fontSize,
      lineSpacing: 0,
      height: 1,
      color: PdfColors.black,
    );

    final pageFormat = PdfPageFormat(
      pageWidthMm * PdfPageFormat.mm,
      contentHeightMm * PdfPageFormat.mm,
      marginLeft: marginLeftMm * PdfPageFormat.mm,
      marginRight: marginRightMm * PdfPageFormat.mm,
      marginTop: verticalMarginMm * PdfPageFormat.mm,
      marginBottom: verticalMarginMm * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (final line in lines)
              pw.SizedBox(
                width: printableWidthMm * PdfPageFormat.mm,
                child: pw.Text(
                  line.isEmpty ? ' ' : line,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static String _normalizedReceiptText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll('\r', ''))
        .join('\n')
        .trimRight();
  }

  static Future<String> _receiptSaveDirectory() async {
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads.path;
      }
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    }

    if (!kIsWeb && Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final desktop = '$home/Desktop';
        if (Directory(desktop).existsSync()) {
          return desktop;
        }
      }
    }

    if (!kIsWeb && Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Desktop';
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
}
