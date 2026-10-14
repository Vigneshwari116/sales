import 'package:flutter_test/flutter_test.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/receipt_service.dart';

const _cols = ReceiptService.thermalContentColumns;
const _amountStart = 4 + 8 + 6;

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
  test('long address splits onto deliberate extra lines', () {
    final lines = ReceiptService.buildReceiptLines(
      _sampleBill(location: 'Win2'),
    );
    final addressLines = lines
        .where(
          (line) =>
              line.contains('TIPPSANDRA') ||
              line.contains('Bangalore-560075'),
        )
        .toList();

    expect(addressLines.length, greaterThan(1));
    for (final line in addressLines) {
      expect(line.length, lessThanOrEqualTo(_cols));
    }
    expect(lines.join('\n'), contains('TIPPSANDRA MAIN ROAD'));
    expect(lines.join('\n'), contains('Bangalore-560075'));
  });

  test('name and mobile are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill(location: 'Win1'));
    final nameIndex = lines.indexWhere((line) => line.contains('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.contains('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);

    final text = lines.join('\n');

    expect(text, contains('R K S ENTERPRIISES'));
    expect(text, contains('KUDULU MAIN ROAD'));
    expect(text, contains('BILL NO:23258'));
    expect(text, contains('DATE:04/09/2026'));
    expect(text, contains('CGST% 2.5SGST% 2.5'));
    expect(text, contains('GRAND TOTAL'));
    _expectLinesWithinWidth(lines);
  });

  test('empty customer name and mobile still print labels', () {
    final bill = SaleBill(
      billNo: 100,
      location: 'Win1',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(qty: 1, rate: 100)],
      totalQty: 1,
      totalAmount: 95.24,
      totalCgst: 2.5,
      totalSgst: 2.5,
      totalIgst: 0,
      grandTotal: 100,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    expect(lines.any((l) => l == 'NAME:'), isTrue);
    expect(lines.any((l) => l == 'MOBILE:'), isTrue);
    _expectLinesWithinWidth(lines);
  });

  test('five-digit amounts stay on one line and right-aligned', () {
    final bill = SaleBill(
      billNo: 99999,
      location: 'Win1',
      billDate: DateTime(2026, 3, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [BillItem(qty: 1, rate: 12345)],
      totalQty: 1,
      totalAmount: 11757.14,
      totalCgst: 293.93,
      totalSgst: 293.93,
      totalIgst: 0,
      grandTotal: 12345,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final itemLine = lines.firstWhere((line) => line.contains('12345'));
    expect(itemLine.length, lessThanOrEqualTo(_cols));
    expect(itemLine.substring(_amountStart).trim(), '12345.00');
    _expectLinesWithinWidth(lines);
  });

  test('many items each produce gst lines without wrapping columns', () {
    final items = List.generate(
      12,
      (index) => BillItem(qty: 1, rate: 100 + index),
    );
    final bill = SaleBill(
      billNo: 5000,
      location: 'Win3',
      billDate: DateTime(2026, 5, 1),
      paymentMode: 'CASH',
      customerName: 'TEST',
      mobile: '9999999999',
      items: items,
      totalQty: 12,
      totalAmount: 1200,
      totalCgst: 30,
      totalSgst: 30,
      totalIgst: 0,
      grandTotal: 1260,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    expect(
      lines.where((line) => line.contains('CGST% 2.5SGST% 2.5')).length,
      12,
    );
    _expectLinesWithinWidth(lines);
  });

  test('item table columns align amount on the right edge', () {
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

    final lines = ReceiptService.buildReceiptLines(bill);
    final header = lines.firstWhere((line) => line.contains('SNO'));
    final item = lines.firstWhere(
      (line) => line.contains('560') && line.contains('2800.00'),
    );
    final total = lines.firstWhere(
      (line) => line.startsWith('TOTAL') && line.contains('2800.00'),
    );
    final cgst = lines.firstWhere((line) => line.startsWith('CGST'));
    final grand = lines.firstWhere((line) => line.startsWith('GRAND TOTAL'));

    expect(header.length, _cols);
    expect(header.substring(_amountStart).trim(), 'AMOUNT');
    expect(item.substring(_amountStart).trim(), '2800.00');
    expect(total.substring(_amountStart).trim(), '2800.00');
    expect(cgst.substring(_amountStart).trim(), '67.00');
    expect(grand.substring(_amountStart).trim(), '2800.00');
    _expectLinesWithinWidth(lines);
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

    final lines = ReceiptService.buildReceiptLines(bill);
    final billDateLine = lines.firstWhere((line) => line.contains('BILL NO:'));

    expect(billDateLine, contains('DATE:10/06/2024'));
    expect(billDateLine, contains('BILL NO:18134'));
    expect(billDateLine.length, lessThanOrEqualTo(_cols));
    expect(lines.where((line) => line.contains('DATE:')).length, 1);
  });
}

void _expectLinesWithinWidth(List<String> lines) {
  for (final line in lines) {
    expect(
      line.length,
      lessThanOrEqualTo(_cols),
      reason: 'Line exceeds $_cols columns: "$line"',
    );
  }
}
