import 'package:flutter_test/flutter_test.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/services/owner_delete_service.dart';

void main() {
  tearDown(() {
    OwnerDeleteService.instance.disable();
  });

  test('starts disabled and enables owner delete mode', () {
    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);

    OwnerDeleteService.instance.enable();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);
  });

  test('disable resets owner delete mode', () {
    OwnerDeleteService.instance.enable();
    OwnerDeleteService.instance.disable();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });

  test('incorrect password does not enable delete mode', () {
    final unlocked =
        OwnerDeleteService.instance.tryUnlockWithPassword('wrong-password');

    expect(unlocked, isFalse);
    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });

  test('correct password enables delete mode', () {
    final unlocked =
        OwnerDeleteService.instance.tryUnlockWithPassword(appPassword);

    expect(unlocked, isTrue);
    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);
  });
}
