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

  // ============================================================
  // TOTAL GST %
  // ============================================================

  double get totalTaxPct {
    return cgstPct + sgstPct + igstPct;
  }

  // ============================================================
  // GST-INCLUSIVE TOTAL
  // ============================================================

  double get grossAmt {
    return qty * rate;
  }

  // ============================================================
  // TAXABLE AMOUNT
  // ============================================================

  double get amount {
    if (totalTaxPct == 0) {
      return grossAmt;
    }

    return (grossAmt / (1 + totalTaxPct / 100)).roundToDouble();
  }

  double get taxableAmt => amount;

  // ============================================================
  // TOTAL TAX
  // ============================================================

  double get totalTax {
    return grossAmt - amount;
  }

  // ============================================================
  // CGST
  // ============================================================

  double get cgst {
    if (totalTaxPct == 0) {
      return 0;
    }

    return totalTax * (cgstPct / totalTaxPct);
  }

  // ============================================================
  // SGST
  // ============================================================

  double get sgst {
    if (totalTaxPct == 0) {
      return 0;
    }

    return totalTax * (sgstPct / totalTaxPct);
  }

  // ============================================================
  // IGST
  // ============================================================

  double get igst {
    if (totalTaxPct == 0) {
      return 0;
    }

    return totalTax * (igstPct / totalTaxPct);
  }

  // ============================================================
  // FINAL TOTAL
  // ============================================================

  double get netAmt {
    return grossAmt;
  }

  // ============================================================
  // COPY WITH
  // ============================================================

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