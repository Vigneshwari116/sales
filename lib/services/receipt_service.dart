import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/gst_config_service.dart';
import 'package:sales/services/receipt_layout.dart';

class ReceiptService {
  static const String businessName = 'R K S ENTERPRISES';
  static const String gstin = '29FNIPS8082N1ZS';

  /// Monospace columns for bill text (~66 mm PDF printable area).
  static const int thermalContentColumns = ReceiptLayout.columnCount;
  static const int _contentWidth = thermalContentColumns;

  /// Bill no + payment + date line (footer-style width).
  static const int _billDateLineMaxChars = 29;
  static const int _addressLineMaxChars = 29;
  static const int _snoW = ReceiptLayout.snoWidth;
  static const String _gap = ' ';
  static const int _groupW = ReceiptLayout.groupWidth;
  static const int _rateW = ReceiptLayout.rateWidth;
  static const int _qtyW = ReceiptLayout.qtyWidth;
  static const int _amountW = ReceiptLayout.amountWidth;
  static const int _footerLineWidth = 29;
  static const int _footerAmountW = 10;
  static const int _footerLabelW = _footerLineWidth - _footerAmountW;
  static String buildReceiptText(SaleBill bill) {
    return buildReceiptLines(bill).join('\n');
  }

  static List<String> buildReceiptLines(SaleBill bill) {
    final code = locationCodeFromDisplayName(bill.location);
    return _buildOriginalFormat(bill, code);
  }

  /// True for shop header/footer lines that should be centered on thermal
  /// (ESC/POS align center).
  static bool isThermalCenteredLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.startsWith('-')) {
      return false;
    }
    if (trimmed.contains(businessName)) {
      return true;
    }
    if (trimmed.startsWith('GSTIN:')) {
      return true;
    }
    if (trimmed.contains('THANK YOU VISIT AGAIN')) {
      return true;
    }
    if (rawLine.isNotEmpty && rawLine[0] == ' ') {
      final start = rawLine.indexOf(trimmed);
      final end = start + trimmed.length;
      final leftPad = start;
      final rightPad = rawLine.length - end;
      return rawLine.length == _contentWidth && (leftPad - rightPad).abs() <= 1;
    }
    return false;
  }

  static List<String> _buildOriginalFormat(SaleBill bill, String locationCode) {
    final lines = <String>[];
    final profile = _locationProfile(locationCode);
    final separator = _separatorLine();
    lines.add(_lineCentered(businessName));
    for (final addressPart in profile.addressLines) {
      for (final addressLine in _wrapToWidth(
        addressPart,
        _addressLineMaxChars,
      )) {
        lines.add(_lineCentered(addressLine));
      }
    }
    for (final gstinLine in _wrapToWidth('GSTIN:$gstin', _contentWidth)) {
      lines.add(_lineCentered(gstinLine));
    }
    lines.add(
      _line(_billDateLine(bill.billNo, bill.billDate, bill.paymentMode)),
    );

    lines.add(_line(_fieldLine('NAME', bill.customerName)));
    lines.add(_line(_fieldLine('MOBILE', bill.mobile)));
    lines.add(separator);
    lines.add(_line(_itemHeader()));
    lines.add(separator);
    for (var index = 0; index < bill.items.length; index++) {
      final item = bill.items[index];
      lines.add(_line(_itemLine(item, index + 1)));
    }
    if (bill.items.isNotEmpty) {
      lines.add(separator);
    }
    if (bill.totalCgst > 0 || bill.items.any((i) => i.cgstPct > 0)) {
      lines.add(
        _line(_taxAmountLine('CGST', bill.totalCgst, _effectiveCgstPct(bill))),
      );
    }
    if (bill.totalSgst > 0 || bill.items.any((i) => i.sgstPct > 0)) {
      lines.add(
        _line(_taxAmountLine('SGST', bill.totalSgst, _effectiveSgstPct(bill))),
      );
    }
    if (bill.totalIgst > 0) {
      lines.add(
        _line(_taxAmountLine('IGST', bill.totalIgst, _billIgstPct(bill))),
      );
    }
    lines.add(_line('-' * _footerLineWidth));
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
          addressLines: ['NO175,NEW TIPPSANDRA MAIN ROAD,Bangalore-560075'],
        );
      case 'win3':
      case 'win1':
      default:
        return const _LocationReceiptProfile(
          addressLines: ['47/3/4,2nd Cross KUDULU MAIN ROAD,Bangalore-68'],
        );
    }
  }

  static double _effectiveCgstPct(SaleBill bill) {
    final fromItems = _billCgstPct(bill);
    if (fromItems > 0) {
      return fromItems;
    }
    if (bill.totalCgst > 0) {
      return GstConfigService.defaultCgstPct;
    }
    return 0;
  }

  static double _effectiveSgstPct(SaleBill bill) {
    final fromItems = _billSgstPct(bill);
    if (fromItems > 0) {
      return fromItems;
    }
    if (bill.totalSgst > 0) {
      return GstConfigService.defaultSgstPct;
    }
    return 0;
  }

  static double _billCgstPct(SaleBill bill) => _uniformPct(
    bill.items.map((item) => item.cgstPct),
    fallback: bill.items.isNotEmpty ? bill.items.first.cgstPct : 0,
  );
  static double _billSgstPct(SaleBill bill) => _uniformPct(
    bill.items.map((item) => item.sgstPct),
    fallback: bill.items.isNotEmpty ? bill.items.first.sgstPct : 0,
  );
  static double _billIgstPct(SaleBill bill) => _uniformPct(
    bill.items.map((item) => item.igstPct),
    fallback: bill.items.isNotEmpty ? bill.items.first.igstPct : 0,
  );
  static double _uniformPct(
    Iterable<double> values, {
    required double fallback,
  }) {
    final set = values.toSet();
    if (set.length == 1) {
      return set.first;
    }
    return fallback;
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
    final group = ReceiptLayout.showGroupColumn
        ? '${_padRight('GROUP', _groupW)}$_gap'
        : '';
    return '${_padRight('SNO', _snoW)}'
        '$_gap'
        '$group'
        '${_padLeft('RATE', _rateW)}'
        '$_gap'
        '${_padLeft('QTY', _qtyW)}'
        '$_gap'
        '${_padLeft('AMOUNT', _amountW)}';
  }

  /// AMOUNT column = taxable amount (item.amount), whole number, as on Surabhi.
  static String _itemLine(BillItem item, int serialNo) {
    final group = ReceiptLayout.showGroupColumn
        ? '${_padRight(_groupLabel(''), _groupW)}$_gap'
        : '';
    return '${_padRight('$serialNo', _snoW)}'
        '$_gap'
        '$group'
        '${_padLeft(_wholeNumber(item.rate), _rateW)}'
        '$_gap'
        '${_padLeft(_wholeNumber(item.qty), _qtyW)}'
        '$_gap'
        '${_padLeft(_wholeNumber(item.amount), _amountW)}';
  }

  static String _groupLabel(String particular) {
    final trimmed = particular.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final upper = trimmed.toUpperCase();
    if (upper.length <= _groupW) {
      return upper;
    }
    return upper.substring(0, _groupW);
  }

  static String _rightAmountLine(String label, double amount) {
    return _footerAmountLine(label, amount);
  }

  static String _taxAmountLine(String kind, double amount, double pct) {
    final label = pct > 0 ? '$kind ${_formatPct(pct)}%' : kind;
    return _footerAmountLine(label, amount);
  }

  /// Footer row: up to 29 chars, amount never truncated (10-char field when it fits).
  static String _footerAmountLine(String label, double amount) {
    final amountText = _twoDecimals(amount);
    if (amountText.length <= _footerAmountW) {
      final labelPart = _padRight(
        _shortenFooterLabel(label, _footerLabelW),
        _footerLabelW,
      );
      return '$labelPart${amountText.padLeft(_footerAmountW)}';
    }
    final maxLabelLen = _footerLineWidth - amountText.length;
    final labelPart = _shortenFooterLabel(label, maxLabelLen);
    return '$labelPart$amountText';
  }

  static String _shortenFooterLabel(String label, int maxLen) {
    if (maxLen <= 0) {
      return '';
    }
    if (label.length <= maxLen) {
      return label;
    }
    if (label.length > maxLen) {
      return label.substring(0, maxLen);
    }
    return label;
  }

  /// Amount text after a footer label on a receipt line (for PDF emphasis rows).
  static String? footerAmountAfterLabel(String line, String label) {
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith(label)) {
      return null;
    }
    final rest = trimmed.substring(label.length).trimLeft();
    if (rest.isEmpty) {
      return null;
    }
    return rest.trim();
  }

  static String _fieldLine(String label, String value) {
    final text = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return text.isEmpty ? '$label:' : '$label:$text';
  }

  static String _billDateLine(
    int billNo,
    DateTime billDate,
    String paymentMode,
  ) {
    final mode = paymentMode.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final left = mode.isEmpty ? 'BILL NO:$billNo' : 'BILL NO:$billNo $mode';
    final dateFormats = [DateFormat('dd/MM/yyyy'), DateFormat('dd/MM/yy')];
    for (final format in dateFormats) {
      final dateText = format.format(billDate);
      final gap = _billDateLineMaxChars - left.length - dateText.length;
      if (gap >= 1) {
        return '$left${' ' * gap}$dateText';
      }
    }
    final dateText = DateFormat('dd/MM/yy').format(billDate);
    var trimmedLeft = left;
    if (trimmedLeft.length + dateText.length + 1 > _billDateLineMaxChars) {
      final maxLeft = _billDateLineMaxChars - dateText.length - 1;
      trimmedLeft = left.length > maxLeft ? left.substring(0, maxLeft) : left;
    }
    final gap = _billDateLineMaxChars - trimmedLeft.length - dateText.length;
    if (gap >= 1) {
      return '$trimmedLeft${' ' * gap}$dateText';
    }
    return '$trimmedLeft $dateText'.substring(0, _billDateLineMaxChars);
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

  /// Display-only whole numbers on the printed receipt (round half up).
  static String _wholeNumber(double value) {
    return '${_roundHalfUp(value)}';
  }

  static String _twoDecimals(double value) {
    return NumberFormat('0.00').format(value);
  }

  static int _roundHalfUp(double value) {
    if (value >= 0) {
      return (value + 0.5).floor();
    }
    return (value - 0.5).ceil();
  }

  static String _formatPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _LocationReceiptProfile {
  final List<String> addressLines;
  const _LocationReceiptProfile({required this.addressLines});
}
