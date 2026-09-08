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
import 'package:sales/services/location_bill_detail_seed_service.dart';
import 'package:sales/services/location_seed_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _salesCsv = '''
BILLNO,DATE,NAME,MOBILE,CASH,CARD/UPI,TOTAL,CGST,SGST,IGST,GRAND TOTAL
1096,2026-01-17,CASH,,120,0,114,3.0,3.0,0,120
''';

const _detailCsv = '''
BillNo,Date,Time,LineNo,Qty,Rate,Amount,Discount%,DiscountAmt,CGSTAmt,SGSTAmt,IGST%,IGSTAmt,TotalAmt,PaymentMode
1096,17-Jan-26,17:49:51,1,1,120,114,0,0,3,3,5,0,120,CASH
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bill_detail_seed_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == 'assets/seed/win1_sales.csv') {
        return const StringCodec().encodeMessage(_salesCsv);
      }
      if (key == 'assets/seed/win1_bill_detail.csv') {
        return const StringCodec().encodeMessage(_detailCsv);
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

  test('imports line items linked by bill number', () async {
    await LocationSeedService.ensureLocationSeeded('win1');
    await LocationBillDetailSeedService.ensureLocationSeeded('win1');

    final bill = await LocationDatabase.getBillByLocalId(
      locationCode: 'win1',
      localId: (await LocationDatabase.getLedgerEntries(
        location: displayNameForLocationCode('win1'),
        from: '2026-01-17',
        to: '2026-01-17',
      ))
          .single
          .localId,
    );

    expect(bill, isNotNull);
    expect(bill!.items.length, 1);
    expect(bill.items.first.qty, 1);
    expect(bill.items.first.rate, 120);
    expect(bill.grandTotal, 120);

    final hasDetail = await LocationDatabase.dayHasLineItemDetail(
      location: displayNameForLocationCode('win1'),
      day: '2026-01-17',
    );
    expect(hasDetail, isTrue);
  });
}
