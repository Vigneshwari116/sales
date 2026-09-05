Future<bool> printRawEscPos({
  required String printerName,
  required List<int> data,
}) {
  throw UnsupportedError(
    'Direct ESC/POS printing is only available on Windows.',
  );
}
