import 'package:flutter_test/flutter_test.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';

void main() {
  test('default build uses location1 database file and GST name', () {
    expect(AppConfig.locationCode, 'location1');
    expect(AppConfig.expectedGstDbName, 'location1_gst');
  });

  test('rejects GST sync when server returns another location db_name', () {
    // Simulates a location1 build hitting a location2 GST endpoint:
    // server returns "location2_gst" but this build expects "location1_gst".
    expect(SalesApi.isGstDbNameValid('location2_gst'), isFalse);
    expect(SalesApi.isGstDbNameValid('location1_gst'), isTrue);
  });
}
