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
  test('address prints on one line like the original receipt', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill(location: 'Win1'))
        .split('\n');
    final addressLine = lines[1];

    expect(
      addressLine,
      '47/3/4,2nd Cross KUDULU MAIN ROAD,Bangalore-68',
    );
  });

  test('name and mobile are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptText(_sampleBill(location: 'Win1'))
        .split('\n');
    final nameIndex = lines.indexWhere((line) => line.startsWith('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.startsWith('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);

    final text = lines.join('\n');

    expect(text, contains('R K S ENTERPRIISES'));
    expect(text, contains('KUDULU MAIN ROAD'));
    expect(text, contains('BILL NO:23258'));
    expect(text, contains('DATE:04/09/2026'));
    expect(text, contains('CGST% 2.5 SGST% 2.5'));
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

  test('receipt shows per-item gst line for each item', () {
    final bill = SaleBill(
      billNo: 17367,
      location: 'Win3',
      billDate: DateTime(2026, 9, 4),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 30),
        BillItem(qty: 1, rate: 100),
        BillItem(qty: 1, rate: 350),
      ],
      totalQty: 3,
      totalAmount: 457.14,
      totalCgst: 11.5,
      totalSgst: 11.5,
      totalIgst: 0,
      grandTotal: 480,
    );

    final text = ReceiptService.buildReceiptText(bill);
    final lines = text.split('\n');

    expect(text, contains('KUDULU MAIN ROAD'));
    expect(lines.where((line) => line.contains('CGST% 2.5 SGST% 2.5')).length, 3);
    expect(text, contains('30.00'));
    expect(text, contains('100.00'));
    expect(text, contains('350.00'));
    expect(text, contains('480.00'));
    _expectLinesWithinThermalWidth(text);
  });

  test('receipt uses qty without decimals and amount with .00', () {
    final bill = SaleBill(
      billNo: 17347,
      location: 'Win1',
      billDate: DateTime(2026, 9, 5),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 2, rate: 1200),
        BillItem(qty: 2, rate: 250),
        BillItem(qty: 6, rate: 45),
        BillItem(qty: 6, rate: 45),
      ],
      totalQty: 16,
      totalAmount: 3276.19,
      totalCgst: 81.9,
      totalSgst: 81.9,
      totalIgst: 0,
      grandTotal: 3440,
    );

    final lines = ReceiptService.buildReceiptText(bill).split('\n');
    final itemLine = lines.firstWhere((line) => line.contains('1200'));

    expect(itemLine, contains('1200'));
    expect(itemLine, contains('2'));
    expect(itemLine, contains('2400.00'));
    expect(itemLine, isNot(contains('2.00')));
    expect(itemLine, isNot(contains('1200.00')));

    final totalLine = lines.firstWhere((line) => line.startsWith('TOTAL'));
    expect(totalLine, contains('16'));
    expect(totalLine, contains('3440.00'));
    expect(totalLine, isNot(contains('16.00')));

    _expectLinesWithinThermalWidth(lines.join('\n'));
  });

  test('item table uses four equal-width columns', () {
    final bill = SaleBill(
      billNo: 5167,
      location: 'Win1',
      billDate: DateTime(2026, 9, 10),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(qty: 5, rate: 560)],
      totalQty: 5,
      totalAmount: 2800,
      totalCgst: 67,
      totalSgst: 67,
      totalIgst: 0,
      grandTotal: 2800,
    );

    final lines = ReceiptService.buildReceiptText(bill).split('\n');
    final header = lines.firstWhere((line) => line.contains('SNO'));
    final item = lines.firstWhere(
      (line) => line.contains('560') && line.contains('2800.00'),
    );

    expect(header.length, 48);
    expect(item.length, 48);
    expect(header.substring(0, 12).trim(), 'SNO');
    expect(header.substring(12, 24).trim(), 'RATE');
    expect(header.substring(24, 36).trim(), 'QTY');
    expect(header.substring(36).trim(), 'AMOUNT');
    expect(item.substring(36).trim(), '2800.00');
    _expectLinesWithinThermalWidth(lines.join('\n'));
  });

  test('bill no and date stay on one line', () {
    final bill = SaleBill(
      billNo: 18134,
      location: 'Win2',
      billDate: DateTime(2024, 6, 10),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(qty: 2, rate: 200)],
      totalQty: 2,
      totalAmount: 400,
      totalCgst: 10,
      totalSgst: 10,
      totalIgst: 0,
      grandTotal: 400,
    );

    final lines = ReceiptService.buildReceiptText(bill).split('\n');
    final billDateLine = lines.firstWhere((line) => line.contains('BILL NO:'));

    expect(billDateLine, contains('DATE:10/06/2024'));
    expect(billDateLine, contains('BILL NO:18134'));
    expect(billDateLine.length, 48);
    expect(billDateLine.indexOf('DATE:'), greaterThan(20));
    expect(lines.where((line) => line.contains('DATE:')).length, 1);
  });

  test('item lines include serial number in SNO column', () {
    final bill = SaleBill(
      billNo: 18134,
      location: 'Win2',
      billDate: DateTime(2024, 6, 10),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 2, rate: 200),
        BillItem(qty: 1, rate: 100),
      ],
      totalQty: 3,
      totalAmount: 500,
      totalCgst: 12,
      totalSgst: 12,
      totalIgst: 0,
      grandTotal: 500,
    );

    final lines = ReceiptService.buildReceiptText(bill).split('\n');
    final firstItem = lines.firstWhere(
      (line) => line.contains('200') && line.contains('400.00'),
    );

    expect(firstItem.trimLeft(), startsWith('1'));
    expect(firstItem, contains('2'));
    _expectLinesWithinThermalWidth(lines.join('\n'));
  });

  test('receipt aligns amount column for multi-item bill', () {
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
    final itemLines = lines.where((line) => line.contains('1200')).toList();

    expect(itemLines, hasLength(1));
    expect(itemLines.first.endsWith('1200.00'), isTrue);
    expect(itemLines.first.length, lessThanOrEqualTo(48));
    _expectLinesWithinThermalWidth(lines.join('\n'));
  });
}

void _expectLinesWithinThermalWidth(String text) {
  for (final line in text.split('\n')) {
    expect(
      line.length,
      lessThanOrEqualTo(48),
      reason: 'Line exceeds 3-inch (80mm) thermal width: "$line"',
    );
  }
}
