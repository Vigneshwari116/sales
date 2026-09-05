import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('name and mobile lines are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill()).split('\n');
    final nameIndex = lines.indexWhere((line) => line.startsWith('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.startsWith('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);
    expect(lines[mobileIndex + 1], startsWith('----'));
  });

  test('receipt footer lines are present after grand total', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());

    expect(text, contains('TERMS AND CONDITION'));
    expect(text, contains('EXCHANGE ONLY 3 DAYS'));
    expect(text, contains('AMOUNT NOT REFUND'));
    expect(text, contains('THANK YOU VISIT AGAIN'));

    final grandTotalIndex = text.lastIndexOf('GRAND TOTAL');
    final footerIndex = text.indexOf('TERMS AND CONDITION');
    expect(footerIndex, greaterThan(grandTotalIndex));
  });

  test('thermal pdf uses 80mm page width and RP3200 Font A line spacing', () async {
    final bill = _sampleBill();
    final text = ReceiptService.buildReceiptText(bill);
    final lineCount = text.split('\n').length;
    final bytes = await BillPrintService.buildPdfBytes(bill);
    final pageFormat = BillPrintService.pageFormatForBill(bill);
    final pdfText = String.fromCharCodes(bytes);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(500));
    expect(pdfText, contains('/MediaBox'));
    final mediaBoxMatch =
        RegExp(r'/MediaBox\[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(pdfText);
    expect(mediaBoxMatch, isNotNull);
    final pageWidthPt = double.parse(mediaBoxMatch!.group(1)!);
    final pageHeightPt = double.parse(mediaBoxMatch.group(2)!);

    // 80mm ≈ 226.77pt; allow small float tolerance from PDF generation.
    expect(pageWidthPt, closeTo(pageFormat.width, 1.0));
    expect(pageWidthPt, closeTo(226.77, 2.0));
    expect(pageHeightPt, closeTo(pageFormat.height, 2.0));

    // Height grows with 4.25mm per line (RP3200 default line spacing).
    final expectedHeightMm =
        lineCount * BillPrintService.thermalLineSpacingMm + 8.0;
    final actualHeightMm = pageHeightPt / 72 * 25.4;
    expect(actualHeightMm, closeTo(expectedHeightMm, 2.0));
  });
}
