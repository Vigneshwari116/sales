import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/printer_settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores thermal and a4 printers independently', () async {
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.thermal,
      'thermal-printer-url',
    );
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.a4,
      'a4-printer-url',
    );

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      'thermal-printer-url',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.a4),
      'a4-printer-url',
    );
  });

  test('migrates legacy default_printer to thermal', () async {
    SharedPreferences.setMockInitialValues({
      PrinterSettingsService.legacyDefaultPrinterKey: 'legacy-printer',
    });

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      'legacy-printer',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.a4),
      isNull,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(PrinterSettingsService.legacyDefaultPrinterKey), isFalse);
  });

  test('clearDefaultPrinter removes only the requested type', () async {
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.thermal,
      'thermal-printer',
    );
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.a4,
      'a4-printer',
    );

    await PrinterSettingsService.clearDefaultPrinter(PrinterType.thermal);

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      isNull,
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.a4),
      'a4-printer',
    );
  });

  test('migration does not overwrite existing thermal default', () async {
    SharedPreferences.setMockInitialValues({
      PrinterSettingsService.legacyDefaultPrinterKey: 'legacy-printer',
      'default_printer_thermal': 'already-migrated',
    });

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      'already-migrated',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(PrinterSettingsService.legacyDefaultPrinterKey), isFalse);
  });
}
