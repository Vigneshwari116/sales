import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/bill_print_service.dart';
import 'package:sales/services/receipt_service.dart';

SaleBill _sampleBill() {
  return SaleBill(
    billNo: 16133,
    location: 'Win2',
    billDate: DateTime(2026, 9, 5),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [BillItem(qty: 1, rate: 1000)],
    totalQty: 1,
    totalAmount: 952.38,
    totalCgst: 24,
    totalSgst: 24,
    totalIgst: 0,
    grandTotal: 1000,
  );
}

Printer _printer({
  required String name,
  String url = '',
  bool isDefault = false,
  bool isAvailable = true,
}) {
  return Printer(
    name: name,
    url: url,
    isDefault: isDefault,
    isAvailable: isAvailable,
  );
}

void main() {
  test('thermal pdf uses 78mm page width and dynamic height', () async {
    final bill = _sampleBill();
    final lineCount = ReceiptService.buildReceiptLines(bill).length;
    final bytes = await BillPrintService.buildPdfBytes(bill);
    final pageFormat = BillPrintService.pageFormatForBill(bill);
    final pdfText = String.fromCharCodes(bytes);

    expect(bytes, isNotEmpty);
    expect(pdfText, contains('/MediaBox'));
    final mediaBoxMatch =
        RegExp(r'/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(pdfText);
    expect(mediaBoxMatch, isNotNull);
    final pageWidthPt = double.parse(mediaBoxMatch!.group(1)!);
    final pageHeightPt = double.parse(mediaBoxMatch.group(2)!);

    final expectedWidthPt =
        BillPrintService.thermalPdfPageWidthMm * PdfPageFormat.mm;
    expect(pageWidthPt, closeTo(pageFormat.width, 1.0));
    expect(pageWidthPt, closeTo(expectedWidthPt, 1.5));

    final expectedHeightMm = lineCount * BillPrintService.thermalLineSpacingMm +
        BillPrintService.thermalPdfMarginTopMm +
        BillPrintService.thermalPdfMarginBottomMm;
    final actualHeightMm = pageHeightPt / PdfPageFormat.mm;
    expect(actualHeightMm, closeTo(expectedHeightMm, 1.0));
  });

  group('resolveTargetPrinter', () {
    test('exact name match', () {
      final printers = [
        _printer(name: 'Kitchen'),
        _printer(name: 'RP3200', url: 'winspool'),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: 'RP3200',
      );

      expect(resolved?.name, 'RP3200');
    });

    test('fuzzy name match when exact name missing', () {
      final printers = [
        _printer(name: 'TVS RP3200 Series'),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: 'rp3200',
      );

      expect(resolved?.name, 'TVS RP3200 Series');
    });

    test('falls back to default printer', () {
      final printers = [
        _printer(name: 'Other'),
        _printer(name: 'Windows Default', isDefault: true),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: 'Missing Printer',
      );

      expect(resolved?.name, 'Windows Default');
    });

    test('returns null when no printers exist', () {
      expect(
        BillPrintService.resolveTargetPrinter(
          printers: [],
          savedPrinterName: 'Anything',
        ),
        isNull,
      );
    });

    test('uses default when saved name is empty', () {
      final printers = [
        _printer(name: 'Counter', isDefault: true),
        _printer(name: 'Backup'),
      ];

      final resolved = BillPrintService.resolveTargetPrinter(
        printers: printers,
        savedPrinterName: '',
      );

      expect(resolved?.name, 'Counter');
    });
  });
}
