import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRIISES';
  static const String gstin = '29FNIPS8082N1ZS';

  /// Monospace line width for bill text (fits 78 mm PDF printable area).
  static const int thermalContentColumns = 42;

  static const int _contentWidth = thermalContentColumns;

  static const int _snoW = 4;
  static const int _rateW = 8;
  static const int _qtyW = 6;
  static const int _amountW = _contentWidth - _snoW - _rateW - _qtyW;
  static const int _labelW = _contentWidth - _amountW;

  static String buildReceiptText(SaleBill bill) {
    return buildReceiptLines(bill).join('\n');
  }

  static List<String> buildReceiptLines(SaleBill bill) {
    final code = locationCodeFromDisplayName(bill.location);
    return _buildOriginalFormat(bill, code);
  }

  /// Original thermal layout — dashed separators, per-item CGST/SGST lines.
  static List<String> _buildOriginalFormat(
    SaleBill bill,
    String locationCode,
  ) {
    final lines = <String>[];
    final dateText = DateFormat('dd/MM/yyyy').format(bill.billDate);
    final profile = _locationProfile(locationCode);
    final separator = '-' * _contentWidth;

    lines.add(_lineCentered(businessName));
    for (final addressLine in _wrapToWidth(profile.addressLine, _contentWidth)) {
      lines.add(_line(addressLine));
    }
    for (final gstinLine in _wrapToWidth('GSTIN:$gstin', _contentWidth)) {
      lines.add(_lineCentered(gstinLine));
    }
    lines.add(_line(_billDateLine(bill.billNo, dateText)));
    lines.add(_line(_fieldLine('NAME', bill.customerName)));
    lines.add(_line(_fieldLine('MOBILE', bill.mobile)));
    lines.add(separator);
    lines.add(_line(_itemHeader()));
    lines.add(separator);

    for (final item in bill.items) {
      lines.add(_line(_itemLine(item)));
      lines.add(separator);
      lines.add(_line(_itemGstLine(item)));
      lines.add(separator);
    }

    lines.add(_line(_totalLine(bill.totalQty, bill.grandTotal)));
    lines.add(_line(_rightAmountLine('CGST', bill.totalCgst)));
    lines.add(_line(_rightAmountLine('SGST', bill.totalSgst)));
    lines.add(separator);
    lines.add(_line(_rightAmountLine('GRAND TOTAL', bill.grandTotal)));
    lines.add(separator);
    lines.add(_line('TERMS AND CONDITION'));
    lines.add(_line('EXCHANGE ONLY 3 DAYS'));
    lines.add(_line('AMOUNT NOT REFUND'));
    lines.add(_lineCentered('THANK YOU VISIT AGAIN'));
    return lines;
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

  static List<String> _wrapToWidth(String text, int width) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    if (trimmed.length <= width) {
      return [trimmed];
    }

    final normalized = trimmed.replaceAll(',', ', ');
    final tokens = normalized.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';

    for (final token in tokens) {
      if (token.isEmpty) {
        continue;
      }
      final candidate = current.isEmpty ? token : '$current $token';
      if (candidate.length <= width) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      if (token.length <= width) {
        current = token;
      } else {
        var remaining = token;
        while (remaining.length > width) {
          lines.add(remaining.substring(0, width));
          remaining = remaining.substring(width);
        }
        current = remaining;
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines;
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
    final line = text.isEmpty ? '$label:' : '$label:$text';
    return _line(line);
  }

  static String _billDateLine(int billNo, String dateText) {
    final left = 'BILL NO:$billNo';
    final right = 'DATE:$dateText';
    final gap = _contentWidth - left.length - right.length;
    if (gap < 1) {
      final maxLeft = _contentWidth - right.length - 1;
      final trimmedLeft =
          left.length > maxLeft ? left.substring(0, maxLeft) : left;
      final adjustedGap = _contentWidth - trimmedLeft.length - right.length;
      return '$trimmedLeft${' ' * adjustedGap}$right';
    }
    return '$left${' ' * gap}$right';
  }

  static String _line(String content) {
    final trimmed = content.trimRight();
    if (trimmed.length <= _contentWidth) {
      return trimmed;
    }
    return trimmed.substring(0, _contentWidth);
  }

  static String _lineCentered(String content) {
    return _center(_line(content));
  }

  static String _center(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.length >= _contentWidth) {
      return trimmed.substring(0, _contentWidth);
    }
    final pad = ((_contentWidth - trimmed.length) / 2).floor();
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
