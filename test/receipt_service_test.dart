import 'package:flutter_test/flutter_test.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/receipt_layout.dart';
import 'package:sales/services/receipt_service.dart';

const _cols = ReceiptService.thermalContentColumns;
const _amountStart = ReceiptLayout.snoWidth +
    ReceiptLayout.columnGap +
    ReceiptLayout.rateWidth +
    ReceiptLayout.columnGap +
    ReceiptLayout.qtyWidth +
    ReceiptLayout.columnGap;

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
  test('long address splits and each wrapped line is centered', () {
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
      expect(line.length, _cols);
      _expectCentered(line);
    }
  });

  test('second address line Bangalore-68 is centered under first', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill(location: 'Win1'));
    final bangaloreLine = lines.firstWhere((line) => line.contains('Bangalore-68'));

    expect(bangaloreLine.length, _cols);
    _expectCentered(bangaloreLine);
    _expectLinesWithinWidth(lines);
  });

  test('header block is centered within content width', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill(location: 'Win1'));
    final title = lines.first;
    final gstinLine = lines.firstWhere((line) => line.contains('GSTIN:'));

    expect(title.length, _cols);
    expect(gstinLine.length, _cols);
    _expectCentered(title);
    _expectCentered(gstinLine);
  });

  test('name and mobile are consecutive without blank lines', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill(location: 'Win1'));
    final nameIndex = lines.indexWhere((line) => line.contains('NAME:'));
    final mobileIndex = lines.indexWhere((line) => line.contains('MOBILE:'));

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(mobileIndex, nameIndex + 1);

    final text = lines.join('\n');

    expect(text, contains('R K S ENTERPRISES'));
    expect(text, contains('KUDULU MAIN'));
    expect(text, contains('Bangalore-68'));
    expect(text, contains('BILL NO:23258'));
    expect(text, contains('04/09/2026'));
    expect(text, isNot(contains('DATE:')));
    expect(text, contains('CGST 2.5%'));
    expect(text, contains('SGST 2.5%'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('1000.00'));
    _expectLinesWithinWidth(lines);
  });

  test('separator lines are exactly content width', () {
    final lines = ReceiptService.buildReceiptLines(_sampleBill(location: 'Win1'));
    final dashes = lines.where((line) => line == '-' * _cols).toList();
    expect(dashes, isNotEmpty);
    for (final line in dashes) {
      expect(line.length, _cols);
    }
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
    expect(lines.any((l) => l.startsWith('NAME:')), isTrue);
    expect(lines.any((l) => l.startsWith('MOBILE:')), isTrue);
    _expectLinesWithinWidth(lines);
  });

  test('item rows print serial number in SNO column', () {
    final bill = SaleBill(
      billNo: 100,
      location: 'Win1',
      billDate: DateTime(2026, 1, 1),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 100),
        BillItem(qty: 2, rate: 200),
        BillItem(qty: 1, rate: 300),
      ],
      totalQty: 4,
      totalAmount: 800,
      totalCgst: 20,
      totalSgst: 20,
      totalIgst: 0,
      grandTotal: 840,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final headerIndex = lines.indexWhere((line) => line.contains('SNO'));
    expect(headerIndex, greaterThanOrEqualTo(0));
    final itemRows = lines
        .skip(headerIndex + 2)
        .take(bill.items.length)
        .where((line) => !line.trimLeft().startsWith('-'))
        .toList();

    expect(itemRows.length, 3);
    expect(itemRows[0].substring(0, 3).trim(), '1');
    expect(itemRows[1].substring(0, 3).trim(), '2');
    expect(itemRows[2].substring(0, 3).trim(), '3');
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
    expect(itemLine.length, _cols);
    expect(itemLine.substring(_amountStart).trim(), '11757');
    expect(lines.join('\n'), contains('11757'));
    _expectLinesWithinWidth(lines);
  });

  test('amount column fits values like 1640.00 and 99999.00', () {
    final bill = SaleBill(
      billNo: 42,
      location: 'Win1',
      billDate: DateTime(2026, 6, 15),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 1640),
        BillItem(qty: 1, rate: 99999),
      ],
      totalQty: 2,
      totalAmount: 100000,
      totalCgst: 2500,
      totalSgst: 2500,
      totalIgst: 0,
      grandTotal: 101639,
    );

    final lines = ReceiptService.buildReceiptLines(bill);
    final text = lines.join('\n');
    expect(text, contains('1562'));
    expect(text, contains('95237'));
    expect(
      lines.firstWhere((l) => l.contains('1562')).substring(_amountStart).trim(),
      '1562',
    );
    expect(
      lines.firstWhere((l) => l.contains('95237')).substring(_amountStart).trim(),
      '95237',
    );
    _expectLinesWithinWidth(lines);
  });

  test('many items each produce spaced cgst/sgst line', () {
    final items = List.generate(
      12,
      (index) => BillItem(qty: 1, rate: 100.0 + index),
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
    expect(lines.where((line) => line.contains('CGST')).length, 1);
    expect(lines.where((line) => line.contains('SGST')).length, 1);
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
    final lineItem = bill.items.first;
    final itemLine = lines.firstWhere(
      (line) =>
          line.trimLeft().startsWith('1') &&
          line.contains(_whole(lineItem.amount)),
    );
    final cgst = lines.firstWhere(
      (line) => line.contains('CGST') && line.contains('67.00'),
    );
    final grand = lines.firstWhere((line) => line.contains('GRAND TOTAL'));

    expect(header.length, _cols);
    expect(header.substring(_amountStart).trim(), 'AMOUNT');
    expect(itemLine.substring(_amountStart).trim(), _whole(lineItem.amount));
    expect(cgst, contains('67.00'));
    expect(grand, contains('2800.00'));
    _expectLinesWithinWidth(lines);
  });

  test('bill no and full date stay on one line', () {
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

    expect(billDateLine, contains('10/06/2024'));
    expect(billDateLine, contains('BILL NO:18134'));
    expect(billDateLine.length, lessThanOrEqualTo(_cols));
    expect(billDateLine.trim().length, lessThanOrEqualTo(30));
    expect(
      lines.where((line) => line.contains('10/06/2024')).length,
      1,
    );
  });
}

String _whole(double value) {
  if (value >= 0) {
    return '${(value + 0.5).floor()}';
  }
  return '${(value - 0.5).ceil()}';
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

void _expectCentered(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final start = line.indexOf(trimmed);
  final end = start + trimmed.length;
  final leftPad = start;
  final rightPad = line.length - end;
  expect(
    (leftPad - rightPad).abs(),
    lessThanOrEqualTo(1),
    reason: 'Expected centered line: "$line"',
  );
}
