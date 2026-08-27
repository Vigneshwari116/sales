import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/receipt_service.dart';

class BillPrintService {
  static Future<String> saveReceiptToDesktop(SaleBill bill) async {
    final text = ReceiptService.buildReceiptText(bill);
    final desktop = await _desktopPath();
    final fileName = 'Bill_${bill.billNo}.txt';
    final file = File('$desktop${Platform.pathSeparator}$fileName');
    await file.writeAsString(text);
    return file.path;
  }

  static Future<void> printReceipt(SaleBill bill, {String? printerName}) async {
    final text = ReceiptService.buildReceiptText(bill);
    final doc = pw.Document();
    final style = pw.TextStyle(
      font: pw.Font.courier(),
      fontSize: 8,
      lineSpacing: 1.2,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) => [
          pw.Text(text, style: style),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'Bill_${bill.billNo}',
      usePrinterSettings: printerName != null,
    );
  }

  static Future<String> _desktopPath() async {
    if (!kIsWeb && Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return '$userProfile\\Desktop';
      }
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
