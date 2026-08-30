import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettingsService {
  static const String defaultPrinterKey = 'default_printer';

  static Future<String?> getDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(defaultPrinterKey);
  }

  static Future<void> setDefaultPrinter(String printerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(defaultPrinterKey, printerName);
  }

  static Future<void> clearDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(defaultPrinterKey);
  }
}
