import 'package:intl/intl.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRIISES';
  static const String businessAddress =
      '47/3/4, 2nd Cross KUDULU MAIN ROAD, Bangalore-68';
  static const String gstin = '29FNIPS8082N1ZS';

  static String buildReceiptText(SaleBill bill) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final line = '-' * 47;

    buffer.writeln(_center(businessName));
    buffer.writeln(_center(businessAddress));
    buffer.writeln(_center('GSTIN: $gstin'));
    buffer.writeln();
    buffer.writeln('Bill No: ${bill.billNo}${' ' * 30}Date: $dateText');
    buffer.writeln();
    buffer.writeln(
      'Customer Name: ${bill.customerName}${' ' * (20 - bill.customerName.length.clamp(0, 20))}Mobile: ${bill.mobile}',
    );
    buffer.writeln();
    buffer.writeln('SNO   RATE        QTY        AMOUNT');
    buffer.writeln(line);

    for (var i = 0; i < bill.items.length; i++) {
      final BillItem item = bill.items[i];
      buffer.writeln(
        '${(i + 1).toString().padRight(5)}'
        '${_money(item.rate).padRight(12)}'
        '${_money(item.qty).padRight(11)}'
        '${_money(item.grossAmt)}',
      );
      buffer.writeln(
        '      CGST% ${_formatPct(item.cgstPct)}  SGST% ${_formatPct(item.sgstPct)}',
      );
    }

    buffer.writeln();
    buffer.writeln(
      'Total Qty: ${_money(bill.totalQty)}${' ' * 30}${_money(bill.grandTotal)}',
    );
    buffer.writeln('CGST: ${_money(bill.totalCgst)}');
    buffer.writeln('SGST: ${_money(bill.totalSgst)}');
    buffer.writeln('Grand Total: ${_money(bill.grandTotal)}');
    buffer.writeln();
    buffer.writeln('Terms and Conditions: EXCHANGE ONLY 3 DAYS');
    buffer.writeln('AMOUNT NOT REFUND');
    buffer.writeln();
    buffer.writeln(_center('THANK YOU VISIT AGAIN'));
    buffer.writeln('VB');

    return buffer.toString();
  }

  static String _center(String text, [int width = 47]) {
    if (text.length >= width) return text;
    final pad = ((width - text.length) / 2).floor();
    return '${' ' * pad}$text';
  }

  static String _money(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(2);
    }
    return value.toStringAsFixed(2);
  }

  static String _formatPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
