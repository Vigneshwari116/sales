import 'dart:io';

import 'thermal_raw_printer_windows.dart' as raw;

Future<bool> printRawEscPos({
  required String printerName,
  required List<int> data,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Direct ESC/POS printing is only available on Windows.',
    );
  }
  return raw.printRawEscPos(
    printerName: printerName,
    data: data,
  );
}
