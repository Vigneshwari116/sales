import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/esc_pos_receipt_service.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/services/receipt_service.dart';
import 'package:sales/services/thermal_raw_printer.dart';

class BillPrintService {
  /// TVS RP3200: 80mm roll; 70mm content area keeps left/right data visible.
  static const double thermalPageWidthMm = 80.0;
  static const double thermalPrintableWidthMm = 70.0;
  static const double _thermalMarginMm =
      (thermalPageWidthMm - thermalPrintableWidthMm) / 2;

  /// RP3200 Font A (12×24 dots): 48 columns, 1.50×3.00mm per character.
  static const double thermalFontSizePt = 8.0;
  static const double thermalCharWidthMm = 1.50;
  static const double thermalLineSpacingMm = 4.25;

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

    if (type == PrinterType.thermal && !kIsWeb && Platform.isWindows) {
      final escPosBytes = EscPosReceiptService.buildReceiptBytes(bill);
      return printRawEscPos(
        printerName: printerName,
        data: escPosBytes,
      );
    }

    final layout = _computePageLayout(
      _normalizedReceiptText(ReceiptService.buildReceiptText(bill)),
      type: type,
    );

    final printed = await Printing.directPrintPdf(
      printer: printer,
      onLayout: (_) async => _buildPdfBytesFromLayout(layout),
      name: 'Bill_${bill.billNo}',
      format: layout.pageFormat,
      dynamicLayout: false,
      usePrinterSettings: false,
    );

    return printed;
  }

  @visibleForTesting
  static Future<Uint8List> buildPdfBytes(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) async {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    final layout = _computePageLayout(text, type: type);
    return _buildPdfBytesFromLayout(layout);
  }

  @visibleForTesting
  static PdfPageFormat pageFormatForBill(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    return _computePageLayout(text, type: type).pageFormat;
  }

  static _ReceiptPdfLayout _computePageLayout(
    String text, {
    required PrinterType type,
  }) {
    final lines = text.split('\n');
    final fontSize =
        type == PrinterType.thermal ? thermalFontSizePt : 7.0;
    final lineHeightMm =
        type == PrinterType.thermal ? thermalLineSpacingMm : 4.25;
    const lineHeightFactor = 1.0;
    const verticalMarginMm = 2.0;
    const bottomBufferMm = 4.0;

    final pageWidthMm = thermalPageWidthMm;
    final marginLeftMm = _thermalMarginMm;
    final marginRightMm = _thermalMarginMm;
    final printableWidthMm = thermalPrintableWidthMm;

    final contentHeightMm = lines.isEmpty
        ? verticalMarginMm * 2 + bottomBufferMm
        : lines.length * lineHeightMm +
            verticalMarginMm * 2 +
            bottomBufferMm;

    final pageFormat = PdfPageFormat(
      pageWidthMm * PdfPageFormat.mm,
      contentHeightMm * PdfPageFormat.mm,
      marginLeft: marginLeftMm * PdfPageFormat.mm,
      marginRight: marginRightMm * PdfPageFormat.mm,
      marginTop: verticalMarginMm * PdfPageFormat.mm,
      marginBottom: verticalMarginMm * PdfPageFormat.mm,
    );

    return _ReceiptPdfLayout(
      lines: lines,
      pageFormat: pageFormat,
      printableWidthMm: printableWidthMm,
      fontSize: fontSize,
      lineHeightMm: lineHeightMm,
      lineHeightFactor: lineHeightFactor,
    );
  }

  static Future<Uint8List> _buildPdfBytesFromLayout(
    _ReceiptPdfLayout layout,
  ) async {
    final doc = pw.Document();
    final style = pw.TextStyle(
      font: pw.Font.courierBold(),
      fontSize: layout.fontSize,
      lineSpacing: 0,
      height: layout.lineHeightFactor,
      color: PdfColors.black,
    );

    doc.addPage(
      pw.Page(
        pageFormat: layout.pageFormat,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            for (final line in layout.lines)
              _thermalLineWidget(
                line: line,
                style: style,
                printableWidthMm: layout.printableWidthMm,
                lineHeightMm: layout.lineHeightMm,
              ),
          ],
        ),
      ),
    );

    return await doc.save();
  }

  static pw.Widget _thermalLineWidget({
    required String line,
    required pw.TextStyle style,
    required double printableWidthMm,
    required double lineHeightMm,
  }) {
    final text = line.isEmpty ? ' ' : line;
    pw.Widget receiptText() => pw.Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
        );

    return pw.SizedBox(
      width: printableWidthMm * PdfPageFormat.mm,
      height: lineHeightMm * PdfPageFormat.mm,
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: pw.Alignment.centerLeft,
        child: pw.Stack(
          children: [
            receiptText(),
            pw.Transform.translate(
              offset: const PdfPoint(0.4, 0),
              child: receiptText(),
            ),
          ],
        ),
      ),
    );
  }

  static Future<Uint8List> _buildPdfBytes(
    SaleBill bill, {
    required PrinterType type,
  }) async {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    final layout = _computePageLayout(text, type: type);
    return _buildPdfBytesFromLayout(layout);
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

class _ReceiptPdfLayout {
  final List<String> lines;
  final PdfPageFormat pageFormat;
  final double printableWidthMm;
  final double fontSize;
  final double lineHeightMm;
  final double lineHeightFactor;

  const _ReceiptPdfLayout({
    required this.lines,
    required this.pageFormat,
    required this.printableWidthMm,
    required this.fontSize,
    required this.lineHeightMm,
    required this.lineHeightFactor,
  });
}
