import 'package:intl/intl.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRISES';
  static const String businessAddressLine1 =
      '47/3/4, 2nd Cross KUDULU MAIN ROAD';
  static const String businessAddressLine2 = 'Bangalore-68';
  static const String gstin = '29FNIPS8082N1ZS';

  /// Thermal width in characters — keep lines within this to avoid PDF clipping.
  static const int _width = 48;
  static const int _snoWidth = 4;
  static const int _rateWidth = 10;
  static const int _qtyWidth = 10;
  static const int _valueWidth =
      _width - _snoWidth - _rateWidth - _qtyWidth;

  static String buildReceiptText(SaleBill bill) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final line = '-' * _width;

    buffer.writeln(_center(businessName));
    buffer.writeln(_center(businessAddressLine1));
    buffer.writeln(_center(businessAddressLine2));
    buffer.writeln(_center('GSTIN:$gstin'));
    buffer.writeln(_billDateLine(bill.billNo, dateText));
    buffer.writeln(_fieldLine('NAME', bill.customerName));
    buffer.writeln(_fieldLine('MOBILE', bill.mobile));
    buffer.writeln(_itemHeader());
    buffer.writeln(line);

    for (var i = 0; i < bill.items.length; i++) {
      final BillItem item = bill.items[i];
      buffer.writeln(_itemLine(i + 1, item));
      buffer.writeln(
        '     CGST% ${_formatPct(item.cgstPct)}'
        '  SGST% ${_formatPct(item.sgstPct)}',
      );
    }

    buffer.writeln(line);
    buffer.writeln(_summaryLine('TOTAL QTY', bill.totalQty));
    buffer.writeln(_summaryLine('SUBTOTAL', bill.totalAmount));
    buffer.writeln(_summaryLine('CGST', bill.totalCgst));
    buffer.writeln(_summaryLine('SGST', bill.totalSgst));
    buffer.writeln(_summaryLine('GRAND TOTAL', bill.grandTotal));
    buffer.writeln(line);
    buffer.writeln(_center('TERMS AND CONDITION'));
    buffer.writeln(_center('EXCHANGE ONLY 3 DAYS'));
    buffer.writeln(_center('AMOUNT NOT REFUND'));
    buffer.writeln(_center('THANK YOU VISIT AGAIN'));

    return buffer.toString();
  }

  static String _itemHeader() {
    return '${_padRight('SNO', _snoWidth)}'
        '${_padRight('RATE', _rateWidth)}'
        '${_padRight('QTY', _qtyWidth)}'
        '${_padLeft('VALUE', _valueWidth)}';
  }

  static String _itemLine(int sno, BillItem item) {
    return '${_padRight('$sno', _snoWidth)}'
        '${_padRight(_money(item.rate), _rateWidth)}'
        '${_padRight(_money(item.qty), _qtyWidth)}'
        '${_padLeft(_money(item.grossAmt), _valueWidth)}';
  }

  static String _summaryLine(String label, double amount) {
    return _summaryLineText(label, _money(amount));
  }

  static String _summaryLineText(String label, String amountText) {
    final labelPart = _padRight(label, _width - amountText.length);
    return '$labelPart$amountText';
  }

  static String _fieldLine(String label, String value) {
    final text = value.trim().isEmpty ? '—' : value.trim();
    return '$label: $text';
  }

  static String _billDateLine(int billNo, String dateText) {
    final left = 'BILL NO: $billNo';
    final right = 'DATE: $dateText';
    if (left.length + right.length + 1 > _width) {
      return '$left\n${_padLeft(right, _width)}';
    }
    final gap = _width - left.length - right.length;
    return '$left${' ' * gap}$right';
  }

  static String _center(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length >= _width) {
      return trimmed.substring(0, _width);
    }
    final pad = ((_width - trimmed.length) / 2).floor();
    return '${' ' * pad}$trimmed';
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
