/// Converts a whole rupee amount into Indian-style words, e.g.
/// 770 -> "SEVEN HUNDRED AND SEVENTY ONLY"
/// 1100 -> "ONE THOUSAND ONE HUNDRED ONLY"
/// Mirrors the amount-in-words strip printed on the legacy Sales Bill form.
String amountInWords(num amount) {
  final int whole = amount.round();
  if (whole == 0) return 'ZERO ONLY';
  final String words = _convert(whole).trim();
  return '$words ONLY';
}

const List<String> _ones = [
  '', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE',
  'TEN', 'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN',
  'SEVENTEEN', 'EIGHTEEN', 'NINETEEN',
];

const List<String> _tens = [
  '', '', 'TWENTY', 'THIRTY', 'FORTY', 'FIFTY', 'SIXTY', 'SEVENTY', 'EIGHTY', 'NINETY',
];

String _twoDigits(int n) {
  if (n < 20) return _ones[n];
  final int t = n ~/ 10;
  final int o = n % 10;
  return o == 0 ? _tens[t] : '${_tens[t]} ${_ones[o]}';
}

String _threeDigits(int n) {
  final int h = n ~/ 100;
  final int rest = n % 100;
  if (h == 0) return _twoDigits(rest);
  if (rest == 0) return '${_ones[h]} HUNDRED';
  return '${_ones[h]} HUNDRED AND ${_twoDigits(rest)}';
}

/// Indian numbering: ...crore, lakh, thousand, hundred.
String _convert(int n) {
  if (n == 0) return '';
  if (n < 1000) return _threeDigits(n);

  final int crore = n ~/ 10000000;
  n %= 10000000;
  final int lakh = n ~/ 100000;
  n %= 100000;
  final int thousand = n ~/ 1000;
  n %= 1000;
  final int hundred = n;

  final List<String> parts = [];
  if (crore > 0) parts.add('${_convert(crore)} CRORE');
  if (lakh > 0) parts.add('${_twoDigits(lakh)} LAKH');
  if (thousand > 0) parts.add('${_twoDigits(thousand)} THOUSAND');
  if (hundred > 0) parts.add(_threeDigits(hundred));

  return parts.join(' ');
}