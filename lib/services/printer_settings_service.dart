import 'package:shared_preferences/shared_preferences.dart';

enum PrinterType {
  thermal,
  a4;

  String get label {
    switch (this) {
      case PrinterType.thermal:
        return 'Thermal Receipt';
      case PrinterType.a4:
        return 'A4 / Office';
    }
  }

  String get settingsTitle {
    switch (this) {
      case PrinterType.thermal:
        return 'THERMAL RECEIPT PRINTER';
      case PrinterType.a4:
        return 'A4 / OFFICE PRINTER';
    }
  }
}

class PrinterSettingsService {
  static const String legacyDefaultPrinterKey = 'default_printer';

  static String _key(PrinterType type) => 'default_printer_${type.name}';

  static Future<void> migrateLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyDefaultPrinterKey);

    if (legacy == null || legacy.isEmpty) {
      return;
    }

    if (!prefs.containsKey(_key(PrinterType.thermal))) {
      await prefs.setString(_key(PrinterType.thermal), legacy);
    }

    await prefs.remove(legacyDefaultPrinterKey);
  }

  static Future<String?> getDefaultPrinter(PrinterType type) async {
    await migrateLegacyIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(type));
  }

  static Future<void> setDefaultPrinter(
    PrinterType type,
    String printerName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(type), printerName);
  }

  static Future<void> clearDefaultPrinter(PrinterType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(type));
  }
}
