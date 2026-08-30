import 'package:flutter_test/flutter_test.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';

void main() {
  setUp(() async {
    await AppConfig.setLocation('win1');
  });

  tearDown(() async {
    await AppConfig.clearLocation();
  });

  test('win1 session uses win1_gst database name', () {
    expect(AppConfig.locationCode, 'win1');
    expect(AppConfig.expectedGstDbName, 'win1_gst');
  });

  test('rejects GST sync when server returns another location db_name', () {
    // Simulates logging in as win1 but server returns win2_gst.
    expect(SalesApi.isGstDbNameValid('win2_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('win1_gst'), isTrue);
  });

  test('win2 session expects win2_gst after switch', () async {
    await AppConfig.setLocation('win2');
    expect(AppConfig.expectedGstDbName, 'win2_gst');
    expect(SalesApi.isGstDbNameValid('win1_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('win2_gst'), isTrue);
  });
}
