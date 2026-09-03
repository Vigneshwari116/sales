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
    final style = pw.TextStyle(
      font: pw.Font.courierBold(),
      fontSize: type == PrinterType.thermal ? 7.2 : 8,
      lineSpacing: 1.1,
      color: PdfColors.black,
    );

    final lines = text.split('\n');
    final lineCount = lines.length;
    final heightMm = (lineCount * 3.8 + 8).clamp(90.0, 420.0);
    final pageFormat = PdfPageFormat(
      88 * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginLeft: 3 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final line in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 0.5),
                child: pw.FittedBox(
                  alignment: pw.Alignment.centerLeft,
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    line,
                    style: style,
                    maxLines: 1,
                    softWrap: false,
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
