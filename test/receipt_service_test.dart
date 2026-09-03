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
}
