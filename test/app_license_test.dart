import 'package:flutter_test/flutter_test.dart';
import 'package:sales/config/app_license.dart';

void main() {
  test('app license is valid through April 2027', () {
    expect(AppLicense.validUntil, DateTime(2027, 4, 30, 23, 59, 59));
    expect(AppLicense.isValid, isTrue);
  });
}
