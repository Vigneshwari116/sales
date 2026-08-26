/// One line of the Sales Bill item grid.
///
/// Matches the columns seen in the legacy grid (scroll right to see all of
/// them): S.no, Qty, RATE, AMOUNT, t amt, CGST %, CGST, SGST %, SGST,
/// IGST %, IGST.
class BillItem {
  final double qty;
  final double rate;
  final double cgstPct;
  final double sgstPct;
  final double igstPct;

  BillItem({
    required this.qty,
    required this.rate,
    this.cgstPct = 2.5,
    this.sgstPct = 2.5,
    this.igstPct = 0,
  });

  double get amount => qty * rate;

  double get taxableAmt => amount;

  double get cgst => taxableAmt * cgstPct / 100;

  double get sgst => taxableAmt * sgstPct / 100;

  double get igst => taxableAmt * igstPct / 100;

  double get netAmt => taxableAmt + cgst + sgst + igst;

  BillItem copyWith({
    double? qty,
    double? rate,
  }) {
    return BillItem(
      qty: qty ?? this.qty,
      rate: rate ?? this.rate,
      cgstPct: cgstPct,
      sgstPct: sgstPct,
      igstPct: igstPct,
    );
  }
}