import 'package:intl/intl.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRISES';
  static const String businessAddress =
      '47/3/4, 2nd Cross KUDULU MAIN ROAD, Bangalore-68';
  static const String gstin = '29FNIPS8082N1ZS';

  static const int _width = 42;
  static const int _snoWidth = 4;
  static const int _rateWidth = 9;
  static const int _qtyWidth = 9;
  static const int _amountWidth =
      _width - _snoWidth - _rateWidth - _qtyWidth;

  static String buildReceiptText(SaleBill bill) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final line = '-' * _width;

    buffer.writeln(_center(businessName));
    buffer.writeln(_center(businessAddress));
    buffer.writeln(_center('GSTIN:$gstin'));
    buffer.writeln(_billDateLine(bill.billNo, dateText));
    buffer.writeln('NAME: ${bill.customerName}');
    buffer.writeln('MOBILE: ${bill.mobile}');
    buffer.writeln(_itemHeader());
    buffer.writeln(line);

    for (var i = 0; i < bill.items.length; i++) {
      final BillItem item = bill.items[i];
      buffer.writeln(_itemLine(i + 1, item));
      buffer.writeln(
        '     CGST% ${_formatPct(item.cgstPct)} SGST% ${_formatPct(item.sgstPct)}',
      );
    }

    buffer.writeln(line);
    final totalGross =
        bill.items.fold(0.0, (sum, item) => sum + item.grossAmt);
    buffer.writeln(_totalLine(bill.totalQty, totalGross));
    buffer.writeln(_taxTotalLine('CGST', bill.totalCgst));
    buffer.writeln(_taxTotalLine('SGST', bill.totalSgst));
    buffer.writeln(_grandTotalLine(bill.grandTotal));
    buffer.writeln(line);
    buffer.writeln('TERMS AND CONDITION');
    buffer.writeln('EXCHANGE ONLY 3 DAYS');
    buffer.writeln('AMOUNT NOT REFUND');
    buffer.writeln(_center('THANK YOU VISIT AGAIN'));

    return buffer.toString();
  }

  static String _itemHeader() {
    return '${_padRight('SNO', _snoWidth)}'
        '${_padRight('RATE', _rateWidth)}'
        '${_padRight('QTY', _qtyWidth)}'
        '${_padLeft('AMOUNT', _amountWidth)}';
  }

  static String _itemLine(int sno, BillItem item) {
    return '${_padRight('$sno', _snoWidth)}'
        '${_padRight(_money(item.rate), _rateWidth)}'
        '${_padRight(_money(item.qty), _qtyWidth)}'
        '${_padLeft(_money(item.grossAmt), _amountWidth)}';
  }

  static String _totalLine(double totalQty, double totalAmount) {
    const label = 'TOTAL';
    final qtyText = _money(totalQty);
    final amountText = _money(totalAmount);
    final qtyStart = _snoWidth + _rateWidth;
    final buffer = StringBuffer(_padRight(label, qtyStart));
    while (buffer.length < qtyStart + _qtyWidth - qtyText.length) {
      buffer.write(' ');
    }
    buffer.write(_padRight(qtyText, _qtyWidth));
    buffer.write(_padLeft(amountText, _amountWidth));
    return buffer.toString();
  }

  static String _taxTotalLine(String label, double amount) {
    final amountText = _money(amount);
    final labelPart = '              $label';
    final spaces = _width - labelPart.length - amountText.length;
    return '$labelPart${' ' * spaces.clamp(1, _width)}$amountText';
  }

  static String _grandTotalLine(double grandTotal) {
    const label = 'GRAND TOTAL';
    final amountText = _money(grandTotal);
    final labelPart = '              $label';
    final spaces = _width - labelPart.length - amountText.length;
    return '$labelPart${' ' * spaces.clamp(1, _width)}$amountText';
  }

  static String _billDateLine(int billNo, String dateText) {
    final left = 'BILL NO: $billNo';
    final right = 'DATE: $dateText';
    final gap = _width - left.length - right.length;
    return '$left${' ' * gap.clamp(1, _width)}$right';
  }

  static String _center(String text) {
    if (text.length >= _width) {
      return text;
    }
    final pad = ((_width - text.length) / 2).floor();
    return '${' ' * pad}$text';
  }

  static String _padRight(String text, int width) {
    if (text.length >= width) {
      return text.substring(0, width);
    }
    return text.padRight(width);
  }

  static String _padLeft(String text, int width) {
    if (text.length >= width) {
      return text.substring(text.length - width);
    }
    return text.padLeft(width);
  }

  static String _money(double value) {
    return value.toStringAsFixed(2);
  }

  static String _formatPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
