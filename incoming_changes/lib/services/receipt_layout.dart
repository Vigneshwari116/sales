/// Thermal receipt / PDF layout constants in one place.
class ReceiptLayout {
  /// Printable roll width (mm).
  static const double pageWidthMm = 66.0;

  static const double marginLeftMm = 2.0;
  static const double marginRightMm = 6.0;

  static const double contentWidthMm =
      pageWidthMm - marginLeftMm - marginRightMm;

  /// Monospace text receipt (ESC/POS) — 48 columns with 8-char side margins.
  static const int paperColumns = 48;
  static const int textContentColumns = 32;
  static const int textMarginColumns =
      (paperColumns - textContentColumns) ~/ 2;

  /// Sales bills have no GROUP / particular on items, so the GROUP column is
  /// off. Set to true to get the exact Surabhi table (needs item.particular).
  static const bool showGroupColumn = false;

  /// Surabhi item table: SNO 2 | GROUP 10 | RATE 5 | QTY 3 | AMOUNT 6, 1-col gaps (= 30).
  /// Without GROUP: SNO 3 | RATE 8 | QTY 6 | AMOUNT 10, 1-col gaps (= 30).
  static const int columnCount = 30;
  static const int columnGap = 1;
  static const int snoWidth = showGroupColumn ? 2 : 3;
  static const int groupWidth = 10;
  static const int rateWidth = showGroupColumn ? 5 : 8;
  static const int qtyWidth = showGroupColumn ? 3 : 6;
  static const int amountWidth = showGroupColumn ? 6 : 10;

  static const double shopNameTargetFontSizePt = 14.0;
  static const double grandTotalAmountTargetFontSizePt = 13.0;
  static const double grandTotalLabelAmountGapMm = 1.0;

  /// Courier Bold character width ≈ 0.6 × font size (pt).
  static const double courierBoldCharWidthFactor = 0.6;

  static const double _mmPerPoint = 25.4 / 72.0;

  /// Body font size (pt) so [columnCount] monospace columns fit [contentWidthMm].
  static double bodyFontSizePt({double safetyMarginPt = 0.1}) {
    final maxSize = contentWidthMm /
        (columnCount * courierBoldCharWidthFactor * _mmPerPoint);
    final rounded = (maxSize - safetyMarginPt).floorToDouble();
    if (rounded < 6) {
      return 6;
    }
    return rounded;
  }

  static double textWidthMm(String text, double fontSizePt) {
    if (text.isEmpty) {
      return 0;
    }
    return text.length *
        courierBoldCharWidthFactor *
        fontSizePt *
        _mmPerPoint;
  }

  /// Largest font size (down to 6 pt) so [text] fits in [contentWidthMm].
  static double fontSizeToFitWidth(
      String text,
      double maxWidthMm, {
        double startPt = shopNameTargetFontSizePt,
      }) {
    var size = startPt;
    while (size > 6 && textWidthMm(text, size) > maxWidthMm) {
      size -= 0.25;
    }
    return size < 6 ? 6 : size;
  }

  static double shopNameFontSizePt(String shopName) {
    return fontSizeToFitWidth(
      shopName,
      contentWidthMm,
      startPt: shopNameTargetFontSizePt,
    );
  }

  static ({double labelPt, double amountPt}) grandTotalFontSizes(
      String amountText,
      ) {
    final body = bodyFontSizePt();
    var labelPt = body + 1.0;
    var amountPt = grandTotalAmountTargetFontSizePt;
    const labelText = 'GRAND TOTAL';

    while (labelPt >= 6 && amountPt >= 6) {
      final totalWidth = textWidthMm(labelText, labelPt) +
          grandTotalLabelAmountGapMm +
          textWidthMm(amountText, amountPt);
      if (totalWidth <= contentWidthMm) {
        break;
      }
      if (amountPt > body) {
        amountPt -= 0.25;
      } else {
        labelPt -= 0.25;
      }
    }

    return (labelPt: labelPt, amountPt: amountPt);
  }
}
