import 'package:flutter_test/flutter_test.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/esc_pos_receipt_service.dart';
import 'package:sales/services/receipt_service.dart';

SaleBill _sampleBill() {
  return SaleBill(
    billNo: 17367,
    location: 'Win3',
    billDate: DateTime(2026, 9, 4),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: [
      BillItem(qty: 1, rate: 30),
      BillItem(qty: 1, rate: 100),
    ],
    totalQty: 2,
    totalAmount: 123.81,
    totalCgst: 3.25,
    totalSgst: 3.25,
    totalIgst: 0,
    grandTotal: 130,
  );
}

void main() {
  test('esc pos bytes start with init, font A, and bold commands', () {
    final bytes = EscPosReceiptService.buildReceiptBytes(_sampleBill());

    expect(bytes.length, greaterThan(20));
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);
    expect(bytes, contains(0x4D)); // Font select
    expect(bytes, contains(0x32)); // Default line spacing
    expect(bytes, containsAll([0x1B, 0x45, 0x01])); // bold on
    expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x01]); // partial cut
  });

  test('esc pos payload includes receipt text lines', () {
    final text = ReceiptService.buildReceiptText(_sampleBill());
    final bytes = EscPosReceiptService.buildReceiptBytesFromText(text);
    final payload = String.fromCharCodes(bytes);

    expect(payload, contains('R K S ENTERPRIISES'));
    expect(payload, contains('KUDULU MAIN ROAD'));
    expect(payload, contains('BILL NO:17367'));
    expect(payload, contains('GRAND TOTAL'));
    expect(payload, contains('THANK YOU VISIT AGAIN'));
  });

  test('esc pos does not set GS L/GS W print area that wraps columns early', () {
    final bytes = EscPosReceiptService.buildReceiptBytes(_sampleBill());

    expect(_containsEscPosCommand(bytes, 0x4C), isFalse); // GS L left margin
    expect(_containsEscPosCommand(bytes, 0x57), isFalse); // GS W print width
  });

  test('esc pos lines are padded to exactly 48 characters', () {
    final bytes = EscPosReceiptService.buildReceiptBytesFromText('HELLO');
    final helloIndex = bytes.indexOf('H'.codeUnitAt(0));
    final lineEnd = bytes.indexOf(0x0A, helloIndex);

    expect(lineEnd, helloIndex + 48);
    expect(
      String.fromCharCodes(bytes.sublist(helloIndex, helloIndex + 5)),
      'HELLO',
    );

    final longLine = 'X' * 60;
    final longBytes = EscPosReceiptService.buildReceiptBytesFromText(longLine);
    final xStart = longBytes.indexOf('X'.codeUnitAt(0));
    var xRun = 0;
    for (var i = xStart; i < longBytes.length && longBytes[i] == 'X'.codeUnitAt(0); i++) {
      xRun++;
    }

    expect(xRun, 48);
  });
}

bool _containsEscPosCommand(List<int> bytes, int commandByte) {
  for (var index = 0; index < bytes.length - 1; index++) {
    if (bytes[index] == 0x1D && bytes[index + 1] == commandByte) {
      return true;
    }
  }
  return false;
}
