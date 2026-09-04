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
      usePrinterSettings: true,
    );

    return printed;
  }

  static Future<Uint8List> _buildPdfBytes(
    SaleBill bill, {
    required PrinterType type,
  }) async {
    final text = ReceiptService.buildReceiptText(bill);
    final doc = pw.Document();
    final fontSize = type == PrinterType.thermal ? 6.2 : 7.0;
    final style = pw.TextStyle(
      font: pw.Font.courierBold(),
      fontSize: fontSize,
      lineSpacing: 1.0,
      color: PdfColors.black,
    );

    final lines = text.split('\n');
    const lineHeightMm = 3.8;
    final contentHeightMm = lines.length * lineHeightMm + 8;
    final pageWidthMm = type == PrinterType.thermal ? 58.0 : 80.0;
    final marginLeftMm = type == PrinterType.thermal ? 1.5 : 3.0;
    final marginRightMm = type == PrinterType.thermal ? 2.5 : 3.0;
    final printableWidthMm = pageWidthMm - marginLeftMm - marginRightMm;
    final pageFormat = PdfPageFormat(
      pageWidthMm * PdfPageFormat.mm,
      contentHeightMm * PdfPageFormat.mm,
      marginLeft: marginLeftMm * PdfPageFormat.mm,
      marginRight: marginRightMm * PdfPageFormat.mm,
      marginTop: 2 * PdfPageFormat.mm,
      marginBottom: 2 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (final line in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 0.1),
                child: pw.SizedBox(
                  width: printableWidthMm * PdfPageFormat.mm,
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      line.isEmpty ? ' ' : line,
                      style: style,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return doc.save();
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
