import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRIISES';
  static const String gstin = '29FNIPS8082N1ZS';

  /// 58mm thermal paper — ~32 monospace chars fit without clipping.
  static const int _width = 32;
  static const int _snoW = 4;
  static const int _rateW = 8;
  static const int _qtyW = 6;
  static const int _amountW = _width - _snoW - _rateW - _qtyW;
  static const int _labelW = _width - _amountW;

  static String buildReceiptText(SaleBill bill) {
    final code = locationCodeFromDisplayName(bill.location);
    switch (code) {
      case 'win3':
        return _buildGrabhivFormat(bill);
      case 'win2':
        return _buildTippasandraFormat(bill);
      case 'win1':
      default:
        return _buildBommasandraFormat(bill);
    }
  }

  /// Grabhivapalya — per-item GST% lines, AMOUNT column, compact totals.
  static String _buildGrabhivFormat(SaleBill bill) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final profile = _locationProfile('win3');

    buffer.writeln(_center(businessName));
    _writeCenteredLines(buffer, profile.addressLine);
    buffer.writeln(_center('GSTIN:$gstin'));
    buffer.writeln(_billDateLine(bill.billNo, dateText));
    buffer.writeln(_fieldLine('NAME', bill.customerName));
    buffer.writeln(_fieldLine('MOBILE', bill.mobile));
    buffer.writeln(_grabhivItemHeader());

    for (final item in bill.items) {
      buffer.writeln(_grabhivItemLine(item));
      buffer.writeln(
        '${_padRight('', _snoW)}'
        'CGST% ${_formatPct(item.cgstPct)}'
        ' SGST% ${_formatPct(item.sgstPct)}',
      );
    }

    buffer.writeln(_grabhivTotalLine(bill.totalQty, bill.grandTotal));
    buffer.writeln(_rightAmountLine('CGST', bill.totalCgst));
    buffer.writeln(_rightAmountLine('SGST', bill.totalSgst));
    buffer.writeln(_grabhivGrandTotalLine(bill.grandTotal));
    _writeFooter(buffer);
    return buffer.toString();
  }

  /// Bommasandra — dashed separators, combined GST% block after items.
  static String _buildBommasandraFormat(SaleBill bill) {
    return _buildDashedBranchFormat(bill, 'win1');
  }

  /// Tippasandra — dashed separators, combined GST% block after items.
  static String _buildTippasandraFormat(SaleBill bill) {
    return _buildDashedBranchFormat(bill, 'win2');
  }

  static String _buildDashedBranchFormat(SaleBill bill, String locationCode) {
    final buffer = StringBuffer();
    final dateText = DateFormat('dd-MM-yyyy').format(bill.billDate);
    final profile = _locationProfile(locationCode);
    final line = '-' * _width;

    buffer.writeln(_center(businessName));
    _writeCenteredLines(buffer, profile.addressLine);
    buffer.writeln(_center('GSTIN:$gstin'));
    buffer.writeln(_billDateLine(bill.billNo, dateText));
    buffer.writeln(_fieldLine('NAME', bill.customerName));
    buffer.writeln(_fieldLine('MOBILE', bill.mobile));
    buffer.writeln(line);
    buffer.writeln(_dashedItemHeader());
    buffer.writeln(line);

    for (final item in bill.items) {
      buffer.writeln(_dashedItemLine(item));
    }

    buffer.writeln(line);
    final cgstPct = bill.items.isNotEmpty ? bill.items.first.cgstPct : 2.5;
    final sgstPct = bill.items.isNotEmpty ? bill.items.first.sgstPct : 2.5;
    buffer.writeln(
      'CGST%  ${_formatPct(cgstPct)}'
      'SGST%  ${_formatPct(sgstPct)}',
    );
    buffer.writeln(line);
    buffer.writeln(line);
    buffer.writeln(_dashedTotalLine(bill.totalQty, bill.grandTotal));
    buffer.writeln();
    buffer.writeln(_rightAmountLine('CGST', bill.totalCgst));
    buffer.writeln(_rightAmountLine('SGST', bill.totalSgst));
    buffer.writeln(line);
    buffer.writeln(_rightAmountLine('GRAND TOTAL', bill.grandTotal));
    buffer.writeln(line);
    _writeFooter(buffer);
    return buffer.toString();
  }

  static void _writeFooter(StringBuffer buffer) {
    buffer.writeln();
    buffer.writeln(_center('TERMS AND CONDITION'));
    buffer.writeln(_center('EXCHANGE ONLY 3 DAYS'));
    buffer.writeln(_center('AMOUNT NOT REFUND'));
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

  static String _grabhivItemHeader() {
    return '${_padRight('SNO', _snoW)}'
        '${_padRight('RATE', _rateW)}'
        '${_padRight('QTY', _qtyW)}'
        '${_padLeft('AMOUNT', _amountW)}';
  }

  static String _grabhivItemLine(BillItem item) {
    return '${_padRight('', _snoW)}'
        '${_padRight(_money(item.rate), _rateW)}'
        '${_padRight(_money(item.qty), _qtyW)}'
        '${_padLeft(_money(item.grossAmt), _amountW)}';
  }

  static String _grabhivTotalLine(double qty, double grandTotal) {
    final left = _padRight('TOTAL', _snoW + _rateW);
    final qtyPart = _padRight(_money(qty), _qtyW);
    final amountPart = _padLeft(_money(grandTotal), _amountW);
    return '$left$qtyPart$amountPart';
  }

  static String _grabhivGrandTotalLine(double grandTotal) {
    final label = _padRight('GRAND TOTAL', _labelW);
    return '$label${_padLeft(_money(grandTotal), _amountW)}';
  }

  static String _dashedItemHeader() {
    return '${_padRight('SNO', _snoW)}'
        '${_padRight('RATE', _rateW)}'
        '${_padRight('QTY', _qtyW)}'
        '${_padLeft('AMOUNT', _amountW)}';
  }

  static String _dashedItemLine(BillItem item) {
    return '${_padRight('', _snoW)}'
        '${_padRight(_money(item.rate), _rateW)}'
        '${_padRight(_money(item.qty), _qtyW)}'
        '${_padLeft(_money(item.grossAmt), _amountW)}';
  }

  static String _dashedTotalLine(double qty, double grandTotal) {
    final left = _padRight('TOTAL', _snoW + _rateW);
    final qtyPart = _padRight(_money(qty), _qtyW);
    final amountPart = _padLeft(_money(grandTotal), _amountW);
    return '$left$qtyPart$amountPart';
  }

  static String _rightAmountLine(String label, double amount) {
    final labelPart = _padRight(label, _labelW);
    return '$labelPart${_padLeft(_money(amount), _amountW)}';
  }

  static String _fieldLine(String label, String value) {
    final text = value.trim().isEmpty ? '' : value.trim();
    return '$label:$text';
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

  static void _writeCenteredLines(StringBuffer buffer, String text) {
    for (final line in _wrapToWidth(text)) {
      buffer.writeln(_center(line));
    }
  }

  static List<String> _wrapToWidth(String text) {
    if (text.length <= _width) {
      return [text];
    }
    final lines = <String>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      if (remaining.length <= _width) {
        lines.add(remaining);
        break;
      }
      var breakAt = remaining.lastIndexOf(',', _width);
      if (breakAt <= 0) {
        breakAt = _width;
      }
      lines.add(remaining.substring(0, breakAt).trim());
      remaining = remaining.substring(breakAt).trimLeft();
      if (remaining.startsWith(',')) {
        remaining = remaining.substring(1).trimLeft();
      }
    }
    return lines;
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

class _LocationReceiptProfile {
  final String addressLine;

  const _LocationReceiptProfile({required this.addressLine});
}
