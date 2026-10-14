import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRIISES';
  static const String gstin = '29FNIPS8082N1ZS';

  /// Monospace columns for bill text (~66 mm PDF printable area).
  static const int thermalContentColumns = 32;

  static const int _contentWidth = thermalContentColumns;

  /// Bill no + date line uses 30 cols (2 spare vs printable width).
  static const int _billDateLineMaxChars = 30;

  static const int _snoW = 3;
  static const int _rateW = 6;
  static const int _qtyW = 5;
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
    final profile = _locationProfile(locationCode);
    final separator = _separatorLine();

    lines.add(_lineCentered(businessName));
    for (final addressLine in _wrapToWidth(profile.addressLine, _contentWidth)) {
      lines.add(_lineCentered(addressLine));
    }
    for (final gstinLine in _wrapToWidth('GSTIN:$gstin', _contentWidth)) {
      lines.add(_lineCentered(gstinLine));
    }
    lines.add(_line(_billDateLine(bill.billNo, bill.billDate)));
    lines.add(_line(_fieldLine('NAME', bill.customerName)));
    lines.add(_line(_fieldLine('MOBILE', bill.mobile)));
    lines.add(separator);
    lines.add(_line(_itemHeader()));
    lines.add(separator);

    for (var index = 0; index < bill.items.length; index++) {
      final item = bill.items[index];
      lines.add(_line(_itemLine(item, index + 1)));
      lines.add(separator);
      lines.addAll(_itemGstLines(item));
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

  static String _separatorLine() => '-' * _contentWidth;

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

  static String _itemLine(BillItem item, int serialNo) {
    return '${_padRight('$serialNo', _snoW)}'
        '${_padRight(_rate(item.rate), _rateW)}'
        '${_padRight(_qty(item.qty), _qtyW)}'
        '${_padLeft(_amount(item.grossAmt), _amountW)}';
  }

  static List<String> _itemGstLines(BillItem item) {
    final cgstPart = 'CGST% ${_formatPct(item.cgstPct)}';
    final sgstPart = 'SGST% ${_formatPct(item.sgstPct)}';
    final combined = '$cgstPart  $sgstPart';
    if (combined.length <= _contentWidth) {
      return [_line(combined)];
    }
    return [_line(cgstPart), _line(sgstPart)];
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

  static String _billDateLine(int billNo, DateTime billDate) {
    final left = 'BILL NO:$billNo';
    final dateFormats = [
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd/MM/yy'),
    ];

    for (final format in dateFormats) {
      final dateText = format.format(billDate);
      final gap = _billDateLineMaxChars - left.length - dateText.length;
      if (gap >= 1) {
        return '$left${' ' * gap}$dateText';
      }
    }

    final dateText = DateFormat('dd/MM/yy').format(billDate);
    final maxLeft = _billDateLineMaxChars - dateText.length - 1;
    final trimmedLeft =
        left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final gap = _billDateLineMaxChars - trimmedLeft.length - dateText.length;
    return '$trimmedLeft${' ' * gap}$dateText';
  }

  static String _line(String content) {
    final trimmed = content.trimRight();
    if (trimmed.length <= _contentWidth) {
      return trimmed;
    }
    return trimmed.substring(0, _contentWidth);
  }

  static String _lineCentered(String content) {
    final clipped = _line(content);
    if (clipped.isEmpty) {
      return ' ' * _contentWidth;
    }
    if (clipped.length >= _contentWidth) {
      return clipped.substring(0, _contentWidth);
    }
    final pad = _contentWidth - clipped.length;
    final left = pad ~/ 2;
    final right = pad - left;
    return '${' ' * left}$clipped${' ' * right}';
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
