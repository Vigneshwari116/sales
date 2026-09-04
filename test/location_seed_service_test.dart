import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/location_database.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/services/location_seed_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _sampleCsv = '''
BILLNO,DATE,NAME,MOBILE,CASH,CARD/UPI,TOTAL,CGST,SGST,IGST,GRAND TOTAL
1,2026-01-01,CARD,,0,350,333,8.5,8.5,0,350
2,2026-01-01,,,1550,0,1475,37.5,37.5,0,1550
3,2026-01-02,PPP,,0,250,238,6.0,6.0,0,250
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('location_seed_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == 'assets/seed/win2_sales.csv') {
        return const StringCodec().encodeMessage(_sampleCsv);
      }
      return null;
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.clearLocation();
    for (final code in allLocationCodes) {
      final file = File('${tempDir.path}/${code}_sales.db');
      if (await file.exists()) {
        await file.delete();
      }
    }
  });

  test('seeds bundled CSV into a location database once', () async {
    await LocationSeedService.ensureLocationSeeded('win2');
    await LocationSeedService.ensureLocationSeeded('win2');

    final ledger = await LedgerRepository.getLedger(
      location: displayNameForLocationCode('win2'),
      from: '2026-01-01',
      to: '2026-01-02',
    );

    expect(ledger.entries.length, 3);
    expect(ledger.summary.grandTotal, 2150);
  });

  test('seeded data appears in abstract date range summary', () async {
    await LocationSeedService.ensureLocationSeeded('win2');

    final summary = await AbstractRepository.getSummaryForLocationCode(
      locationCode: 'win2',
      fromDate: DateTime(2026, 1, 1),
      toDate: DateTime(2026, 1, 1),
    );

    expect(summary.totalSaleAmount, 1808);
    expect(summary.totalGst, 92);
  });

  test('ledger reads seeded rows for non-active admin location file', () async {
    await AppConfig.setLocation('win1');
    await LocationSeedService.ensureLocationSeeded('win2');

    final ledger = await LocationDatabase.getLedgerEntries(
      location: displayNameForLocationCode('win2'),
      from: '2026-01-02',
      to: '2026-01-02',
    );

    expect(ledger.length, 1);
    expect(ledger.first.billNo, 3);
    expect(ledger.first.paymentMode, 'UPI');
  });
}
