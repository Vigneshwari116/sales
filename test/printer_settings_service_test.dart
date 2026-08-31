import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/printer_settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores thermal, a4, and fast printers independently', () async {
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.thermal,
      'thermal-printer-url',
    );
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.a4,
      'a4-printer-url',
    );
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.fast,
      'fast-printer-url',
    );

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      'thermal-printer-url',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.a4),
      'a4-printer-url',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.fast),
      'fast-printer-url',
    );
  });

  test('uses separate SharedPreferences keys per printer type', () async {
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.fast,
      'device-fast',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('default_printer_fast'), 'device-fast');
    expect(prefs.containsKey('default_printer_thermal'), isFalse);
    expect(prefs.containsKey('default_printer_a4'), isFalse);
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
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.fast),
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
    await PrinterSettingsService.setDefaultPrinter(
      PrinterType.fast,
      'fast-printer',
    );

    await PrinterSettingsService.clearDefaultPrinter(PrinterType.fast);

    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal),
      'thermal-printer',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.a4),
      'a4-printer',
    );
    expect(
      await PrinterSettingsService.getDefaultPrinter(PrinterType.fast),
      isNull,
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
