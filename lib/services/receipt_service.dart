import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRIISES';
  static const String gstin = '29FNIPS8082N1ZS';

  /// 4-inch (101.6mm) thermal paper — ~62 monospace chars.
  static const int _width = 62;
  static const int _snoW = 4;
  static const int _rateW = 12;
  static const int _qtyW = 10;
  static const int _amountW = _width - _snoW - _rateW - _qtyW;
  static const int _labelW = _width - _amountW;

  static String buildReceiptText(SaleBill bill) {
    final code = locationCodeFromDisplayName(bill.location);
    return _buildOriginalFormat(bill, code).trimRight();
  }

  /// Original thermal layout — dashed separators, per-item CGST/SGST lines.
  static String _buildOriginalFormat(SaleBill bill, String locationCode) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd/MM/yyyy').format(bill.billDate);
    final profile = _locationProfile(locationCode);
    final line = '-' * _width;

    buffer.writeln(_center(businessName));
    buffer.writeln(_singleLineAddress(profile.addressLine));
    buffer.writeln(_center('GSTIN:$gstin'));
    buffer.writeln(_billDateLine(bill.billNo, dateText));
    buffer.writeln(_fieldLine('NAME', bill.customerName));
    buffer.writeln(_fieldLine('MOBILE', bill.mobile));
    buffer.writeln(line);
    buffer.writeln(_itemHeader());
    buffer.writeln(line);

    for (final item in bill.items) {
      buffer.writeln(_itemLine(item));
      buffer.writeln(line);
      buffer.writeln(_itemGstLine(item));
      buffer.writeln(line);
    }

    buffer.writeln(_totalLine(bill.totalQty, bill.grandTotal));
    buffer.writeln(_rightAmountLine('CGST', bill.totalCgst));
    buffer.writeln(_rightAmountLine('SGST', bill.totalSgst));
    buffer.writeln(line);
    buffer.writeln(_rightAmountLine('GRAND TOTAL', bill.grandTotal));
    buffer.writeln(line);
    _writeFooter(buffer);
    return buffer.toString();
  }

  static void _writeFooter(StringBuffer buffer) {
    buffer.writeln('TERMS AND CONDITION');
    buffer.writeln('EXCHANGE ONLY 3 DAYS');
    buffer.writeln('AMOUNT NOT REFUND');
    buffer.writeln(_center('THANK YOU VISIT AGAIN'));
  }

  static _LocationReceiptProfile _locationProfile(String locationCode) {
    switch (locationCode) {
      case 'win2':
        return const _LocationReceiptProfile(
          addressLine: 'NO175,NEW TIPPSANDRA MAIN ROAD,Bangalore-560075',
        );
      case 'win3':
        return const _LocationReceiptProfile(
          addressLine: '47/3/4,2nd Cross KUDULU MAIN ROAD,Bangalore-68',
        );
      case 'win1':
      default:
        return const _LocationReceiptProfile(
          addressLine: '47/3/4,2nd Cross KUDULU MAIN ROAD,Bangalore-68',
        );
    }
  }

  static String _singleLineAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.length <= _width) {
      return trimmed;
    }
    return trimmed.substring(0, _width);
  }

  static String _itemHeader() {
    return '${_padRight('SNO', _snoW)}'
        '${_padRight('RATE', _rateW)}'
        '${_padRight('QTY', _qtyW)}'
        '${_padLeft('AMOUNT', _amountW)}';
  }

  static String _itemLine(BillItem item) {
    return '${_padRight('', _snoW)}'
        '${_padRight(_rate(item.rate), _rateW)}'
        '${_padRight(_qty(item.qty), _qtyW)}'
        '${_padLeft(_amount(item.grossAmt), _amountW)}';
  }

  static String _itemGstLine(BillItem item) {
    return 'CGST% ${_formatPct(item.cgstPct)}'
        'SGST% ${_formatPct(item.sgstPct)}';
  }

  static String _totalLine(double qty, double grandTotal) {
    final left = _padRight('TOTAL', _snoW + _rateW);
    final qtyPart = _padRight(_qty(qty), _qtyW);
    final amountPart = _padLeft(_amount(grandTotal), _amountW);
    return '$left$qtyPart$amountPart';
  }

  static String _rightAmountLine(String label, double amount) {
    final labelPart = _padRight(label, _labelW);
    return '$labelPart${_padLeft(_amount(amount), _amountW)}';
  }

  static String _fieldLine(String label, String value) {
    final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.isEmpty ? '$label:' : '$label:$text';
  }

  static String _billDateLine(int billNo, String dateText) {
    final left = 'BILL NO:$billNo';
    final right = 'DATE:$dateText';
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

  static String _amount(double value) {
    return value.toStringAsFixed(2);
  }

  static String _qty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  static String _rate(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
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

class _LocationReceiptProfile {
  final String addressLine;

  const _LocationReceiptProfile({required this.addressLine});
}
