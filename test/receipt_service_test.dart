import 'package:flutter_test/flutter_test.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/receipt_service.dart';

SaleBill _sampleBill({required String location}) {
  return SaleBill(
    billNo: 23258,
    location: location,
    billDate: DateTime(2026, 9, 4),
    paymentMode: 'CASH',
    customerName: 'CASH',
    mobile: '',
    items: [
      BillItem(qty: 1, rate: 1000),
    ],
    totalQty: 1,
    totalAmount: 952.38,
    totalCgst: 24,
    totalSgst: 24,
    totalIgst: 0,
    grandTotal: 1000,
  );
}

void main() {
  test('bommasandra receipt uses dashed format and kudulu address', () {
    final text = ReceiptService.buildReceiptText(_sampleBill(location: 'Win1'));

    expect(text, contains('R K S ENTERPRIISES'));
    expect(text, contains('KUDULU MAIN ROAD'));
    expect(text, contains('BILL NO:23258'));
    expect(text, contains('DATE:04-09-2026'));
    expect(text, contains('CGST%  2.5SGST%  2.5'));
    expect(text, contains('GRAND TOTAL'));
    expect(text.split('-----').length, greaterThan(4));
    _expectLinesWithinThermalWidth(text);
  });

  test('tippasandra receipt uses tippasandra address', () {
    final text = ReceiptService.buildReceiptText(_sampleBill(location: 'Win2'));

    expect(text, contains('TIPPSANDRA MAIN ROAD'));
    expect(text, contains('Bangalore-560075'));
    expect(text, contains('AMOUNT'));
    expect(text, contains('GRAND TOTAL'));
    _expectLinesWithinThermalWidth(text);
  });

  test('grabhiv receipt shows per-item gst lines', () {
    final bill = SaleBill(
      billNo: 23255,
      location: 'Win3',
      billDate: DateTime(2026, 8, 25),
      paymentMode: 'CASH',
      customerName: 'CASH',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 100),
        BillItem(qty: 1, rate: 1000),
      ],
      totalQty: 2,
      totalAmount: 1047.62,
      totalCgst: 26.5,
      totalSgst: 26.5,
      totalIgst: 0,
      grandTotal: 1100,
    );

    final text = ReceiptService.buildReceiptText(bill);
    final lines = text.split('\n');

    expect(text, contains('KUDULU MAIN ROAD'));
    expect(lines.where((line) => line.contains('CGST% 2.5')).length, 2);
    expect(text, contains('TOTAL'));
    expect(text, contains('1100.00'));
    _expectLinesWithinThermalWidth(text);
  });

  test('bommasandra receipt aligns amount column for multi-item bill', () {
    final bill = SaleBill(
      billNo: 17345,
      location: 'Win1',
      billDate: DateTime(2024, 9, 4),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 1200),
        BillItem(qty: 1, rate: 210),
      ],
      totalQty: 2,
      totalAmount: 1343,
      totalCgst: 33.5,
      totalSgst: 33.5,
      totalIgst: 0,
      grandTotal: 1410,
    );

    final lines = ReceiptService.buildReceiptText(bill).split('\n');
    final itemLines = lines.where((line) => line.contains('1200.00')).toList();

    expect(itemLines, hasLength(1));
    expect(itemLines.first.endsWith('1200.00'), isTrue);
    expect(itemLines.first.length, lessThanOrEqualTo(32));
    _expectLinesWithinThermalWidth(lines.join('\n'));
  });
}

void _expectLinesWithinThermalWidth(String text) {
  for (final line in text.split('\n')) {
    expect(
      line.length,
      lessThanOrEqualTo(32),
      reason: 'Line exceeds 58mm thermal width: "$line"',
    );
  }
}
