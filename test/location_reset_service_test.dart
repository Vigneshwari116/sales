import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/services/location_reset_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocationResetService.clearPendingForTesting();
  });

  test('win4 is not an active location code', () {
    expect(isActiveLocationCode('win4'), isFalse);
    expect(allLocationCodes, ['win1', 'win2', 'win3']);
  });

  test('branch labels map to the three active locations', () {
    expect(branchLabelForLocationCode('win1'), 'Win1 - Bommasandra');
    expect(branchLabelForLocationCode('win2'), 'Win2 - Tippasandra');
    expect(branchLabelForLocationCode('win3'), 'Win3 - Grabhivapalya');
  });

  test('hasPendingServerReset tracks queued location codes', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_server_reset_locations', ['win2']);

    expect(await LocationResetService.hasPendingServerReset('win2'), isTrue);
    expect(await LocationResetService.hasPendingServerReset('win1'), isFalse);
  });
}
