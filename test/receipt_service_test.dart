import 'package:flutter_test/flutter_test.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/receipt_service.dart';

void main() {
  test('receipt keeps bill no and date on one line', () {
    final bill = SaleBill(
      billNo: 23255,
      location: 'Win1',
      billDate: DateTime(2026, 8, 25),
      paymentMode: 'CASH',
      customerName: 'CASH',
      mobile: '',
      items: [
        BillItem(qty: 1, rate: 100),
      ],
      totalQty: 1,
      totalAmount: 100,
      totalCgst: 2.5,
      totalSgst: 2.5,
      totalIgst: 0,
      grandTotal: 105,
    );

    final text = ReceiptService.buildReceiptText(bill);
    final lines = text.split('\n');

    expect(lines.any((line) => line.contains('BILL NO: 23255')), isTrue);
    expect(lines.any((line) => line.contains('DATE: 25-08-2026')), isTrue);
    expect(
      lines.any(
        (line) =>
            line.contains('BILL NO: 23255') && line.contains('DATE: 25-08-2026'),
      ),
      isTrue,
    );
    expect(lines.any((line) => line.startsWith('SNO')), isTrue);
    expect(lines.any((line) => line.contains('GRAND TOTAL')), isTrue);
  });

  test('receipt shows taxable amount and 5% gst split on inclusive bill', () {
    final item = BillItem(qty: 12, rate: 12);
    final bill = SaleBill(
      billNo: 8,
      location: 'Win1',
      billDate: DateTime(2026, 9, 3),
      paymentMode: 'CASH',
      customerName: '',
      mobile: '',
      items: [item],
      totalQty: 12,
      totalAmount: item.amount,
      totalCgst: item.cgst,
      totalSgst: item.sgst,
      totalIgst: 0,
      grandTotal: item.netAmt,
    );

    final text = ReceiptService.buildReceiptText(bill);

    expect(item.amount, 137);
    expect(item.cgst, 3.5);
    expect(item.sgst, 3.5);
    expect(item.netAmt, 144);
    expect(text, contains('137.00'));
    expect(text, contains('CGST'));
    expect(text, contains('3.50'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('144.00'));
  });
}
