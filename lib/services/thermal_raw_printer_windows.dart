import 'dart:typed_data';

import 'package:windows_printer/windows_printer.dart';

Future<bool> printRawEscPos({
  required String printerName,
  required List<int> data,
}) async {
  await WindowsPrinter.printRawData(
    printerName: printerName,
    data: Uint8List.fromList(data),
    useRawDatatype: true,
  );
  return true;
}
