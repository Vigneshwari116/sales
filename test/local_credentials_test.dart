import 'package:flutter_test/flutter_test.dart';
import 'package:sales/config/local_credentials.dart';

void main() {
  test('bommasandra staff login', () {
    expect(verifyStaffLogin('RKSB', 'rksb'), isTrue);
    expect(verifyStaffLogin('rksb', 'wrong'), isFalse);
    expect(staffLocationCodeForUsername('RKSB'), 'win1');
  });

  test('tippasandra staff login', () {
    expect(verifyStaffLogin('RKST', 'rkst'), isTrue);
    expect(staffLocationCodeForUsername('rkst'), 'win2');
  });

  test('grabhivapalya staff login', () {
    expect(verifyStaffLogin('RKSG', 'rksg'), isTrue);
    expect(staffLocationCodeForUsername('RKSG'), 'win3');
  });

  test('admin login', () {
    expect(verifyAdminLogin('admin', 'admin123'), isTrue);
    expect(verifyAdminLogin('admin', 'wrong'), isFalse);
  });
}
