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
  /// Thermal PDF tuning (3-inch / RP3200 roll) — adjust here only.
  static const double thermalPdfPageWidthMm = 66.0;
  static const double thermalPdfMarginRightMm = 6.0;

  static const double thermalPdfMarginLeftMm = 2.0;
  static const double thermalPdfMarginTopMm = 2.5;
  static const double thermalPdfMarginBottomMm = 4.0;
  static const double thermalPrintableWidthMm = thermalPdfPageWidthMm -
      thermalPdfMarginLeftMm -
      thermalPdfMarginRightMm;

  static const double thermalFontSizePt = 9.0;
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

  /// Resolves a physical printer: exact name, fuzzy match, then OS default.
  @visibleForTesting
  static Printer? resolveTargetPrinter({
    required List<Printer> printers,
    String savedPrinterName = '',
  }) {
    if (printers.isEmpty) {
      return null;
    }

    String clean(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    var available =
        printers.where((printer) => printer.isAvailable != false).toList();
    if (available.isEmpty) {
      available = printers;
    }

    final saved = savedPrinterName.trim();
    if (saved.isNotEmpty) {
      for (final printer in available) {
        if (printer.name == saved || printer.url == saved) {
          return printer;
        }
      }

      final savedClean = clean(saved);
      if (savedClean.isNotEmpty) {
        for (final printer in available) {
          final nameClean = clean(printer.name);
          final urlClean = clean(printer.url);
          if (nameClean == savedClean ||
              urlClean == savedClean ||
              nameClean.contains(savedClean) ||
              savedClean.contains(nameClean) ||
              (urlClean.isNotEmpty &&
                  (urlClean.contains(savedClean) ||
                      savedClean.contains(urlClean)))) {
            return printer;
          }
        }
      }
    }

    for (final printer in available) {
      if (printer.isDefault) {
        return printer;
      }
    }

    return available.first;
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
    final printer = resolveTargetPrinter(
      printers: printers,
      savedPrinterName: printerName,
    );

    if (printer == null) {
      throw Exception('No printers available on this system');
    }

    final layout = _computePageLayout(
      ReceiptService.buildReceiptLines(bill),
      type: type,
    );
    final bytes = await _buildPdfBytesFromLayout(layout);

    try {
      final printed = await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        name: 'Bill_${bill.billNo}',
        format: layout.pageFormat,
        dynamicLayout: false,
        usePrinterSettings: false,
      );
      if (printed) {
        return true;
      }
    } catch (e, stack) {
      debugPrint('Bill direct PDF print failed: $e\n$stack');
    }

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Bill_${bill.billNo}',
    );
    return true;
  }

  @visibleForTesting
  static Future<Uint8List> buildPdfBytes(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) async {
    final layout = _computePageLayout(
      ReceiptService.buildReceiptLines(bill),
      type: type,
    );
    return _buildPdfBytesFromLayout(layout);
  }

  @visibleForTesting
  static PdfPageFormat pageFormatForBill(
    SaleBill bill, {
    PrinterType type = PrinterType.thermal,
  }) {
    return _computePageLayout(
      ReceiptService.buildReceiptLines(bill),
      type: type,
    ).pageFormat;
  }

  static _ReceiptPdfLayout _computePageLayout(
    List<String> lines, {
    required PrinterType type,
  }) {
    final fontSize = type == PrinterType.thermal ? thermalFontSizePt : 7.0;
    final lineHeightMm =
        type == PrinterType.thermal ? thermalLineSpacingMm : 4.25;
    const lineHeightFactor = 1.0;

    if (type == PrinterType.thermal) {
      final contentHeightMm = lines.isEmpty
          ? thermalPdfMarginTopMm + thermalPdfMarginBottomMm
          : lines.length * lineHeightMm +
              thermalPdfMarginTopMm +
              thermalPdfMarginBottomMm;

      final pageFormat = PdfPageFormat(
        thermalPdfPageWidthMm * PdfPageFormat.mm,
        contentHeightMm * PdfPageFormat.mm,
        marginLeft: thermalPdfMarginLeftMm * PdfPageFormat.mm,
        marginRight: thermalPdfMarginRightMm * PdfPageFormat.mm,
        marginTop: thermalPdfMarginTopMm * PdfPageFormat.mm,
        marginBottom: thermalPdfMarginBottomMm * PdfPageFormat.mm,
      );

      return _ReceiptPdfLayout(
        lines: lines,
        pageFormat: pageFormat,
        printableWidthMm: thermalPrintableWidthMm,
        fontSize: fontSize,
        lineHeightMm: lineHeightMm,
        lineHeightFactor: lineHeightFactor,
      );
    }

    const legacyPageWidthMm = 80.0;
    const legacyPrintableMm = 70.0;
    const legacyMarginMm = (legacyPageWidthMm - legacyPrintableMm) / 2;
    const legacyVerticalMarginMm = 2.0;
    const legacyBottomBufferMm = 4.0;

    final contentHeightMm = lines.isEmpty
        ? legacyVerticalMarginMm * 2 + legacyBottomBufferMm
        : lines.length * lineHeightMm +
            legacyVerticalMarginMm * 2 +
            legacyBottomBufferMm;

    final pageFormat = PdfPageFormat(
      legacyPageWidthMm * PdfPageFormat.mm,
      contentHeightMm * PdfPageFormat.mm,
      marginLeft: legacyMarginMm * PdfPageFormat.mm,
      marginRight: legacyMarginMm * PdfPageFormat.mm,
      marginTop: legacyVerticalMarginMm * PdfPageFormat.mm,
      marginBottom: legacyVerticalMarginMm * PdfPageFormat.mm,
    );

    return _ReceiptPdfLayout(
      lines: lines,
      pageFormat: pageFormat,
      printableWidthMm: legacyPrintableMm,
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

    return pw.SizedBox(
      width: printableWidthMm * PdfPageFormat.mm,
      height: lineHeightMm * PdfPageFormat.mm,
      child: pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: pw.TextOverflow.clip,
        ),
      ),
    );
  }

  static Future<Uint8List> _buildPdfBytes(
    SaleBill bill, {
    required PrinterType type,
  }) async {
    final layout = _computePageLayout(
      ReceiptService.buildReceiptLines(bill),
      type: type,
    );
    return _buildPdfBytesFromLayout(layout);
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
