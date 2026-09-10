import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/receipt_service.dart';

/// Builds native ESC/POS bytes for TVS RP3200 (Font A, 80mm, 48 columns).
class EscPosReceiptService {
  static const int columnsPerLine = 48;

  /// ESC @ — reset printer.
  static const List<int> _init = [0x1B, 0x40];

  /// ESC M 0 — Font A (12×24 dots, 48 cols on 80mm).
  static const List<int> _fontA = [0x1B, 0x4D, 0x00];

  /// ESC 2 — default line spacing (1/6 inch ≈ 4.25mm).
  static const List<int> _defaultLineSpacing = [0x1B, 0x32];

  /// ESC a 0 — left align (receipt text is pre-formatted).
  static const List<int> _alignLeft = [0x1B, 0x61, 0x00];

  /// ESC d n — feed n lines before cut.
  static const List<int> _feedBeforeCut = [0x1B, 0x64, 0x03];

  /// GS V 1 — partial paper cut.
  static const List<int> _partialCut = [0x1D, 0x56, 0x01];

  static List<int> buildReceiptBytes(SaleBill bill) {
    final text = _normalizedReceiptText(ReceiptService.buildReceiptText(bill));
    return buildReceiptBytesFromText(text);
  }

  static List<int> buildReceiptBytesFromText(String text) {
    final bytes = <int>[
      ..._init,
      ..._fontA,
      ..._defaultLineSpacing,
      ..._alignLeft,
    ];

    for (final line in text.split('\n')) {
      bytes.addAll(_encodeLine(line));
      bytes.add(0x0A);
    }

    bytes
      ..addAll(_feedBeforeCut)
      ..addAll(_partialCut);

    return bytes;
  }

  static List<int> _encodeLine(String line) {
    final trimmed = line.length > columnsPerLine
        ? line.substring(0, columnsPerLine)
        : line;

    final encoded = <int>[];
    for (final unit in trimmed.codeUnits) {
      if (unit >= 0x20 && unit <= 0x7E) {
        encoded.add(unit);
      } else if (unit == 0x09) {
        encoded.add(0x09);
      }
    }
    return encoded;
  }

  static String _normalizedReceiptText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.replaceAll('\r', ''))
        .join('\n')
        .trimRight();
  }
}
