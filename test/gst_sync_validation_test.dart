import 'package:flutter_test/flutter_test.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';

void main() {
  setUp(() async {
    await AppConfig.setLocation('location1');
  });

  tearDown(() async {
    await AppConfig.clearLocation();
  });

  test('location1 session uses location1_gst database name', () {
    expect(AppConfig.locationCode, 'location1');
    expect(AppConfig.expectedGstDbName, 'location1_gst');
  });

  test('rejects GST sync when server returns another location db_name', () {
    // Simulates logging in as location1 but server returns location2_gst.
    expect(SalesApi.isGstDbNameValid('location2_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('location1_gst'), isTrue);
  });

  test('location2 session expects location2_gst after switch', () async {
    await AppConfig.setLocation('location2');
    expect(AppConfig.expectedGstDbName, 'location2_gst');
    expect(SalesApi.isGstDbNameValid('location1_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('location2_gst'), isTrue);
  });
}
