import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/credential_service.dart';
import 'package:sales/services/credential_storage.dart';
import 'package:sales/services/owner_delete_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CredentialService.useStorage(InMemoryCredentialStorage());
    await CredentialService.resetForTesting();
    await CredentialService.saveInitialSetup(
      staffUsername: 'staff',
      staffPassword: 'staffpass1',
      adminUsername: 'admin',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );
    OwnerDeleteService.instance.disable();
  });

  tearDown(() async {
    OwnerDeleteService.instance.disable();
    await CredentialService.resetForTesting();
  });

  test('incorrect PIN does not enable delete mode', () async {
    final unlocked =
        await OwnerDeleteService.instance.tryUnlockWithPin('wrong-pin');

    expect(unlocked, isFalse);
    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });

  test('correct delete PIN enables delete mode', () async {
    final unlocked =
        await OwnerDeleteService.instance.tryUnlockWithPin('delete99');

    expect(unlocked, isTrue);
    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);
  });

  test('admin password does not unlock delete mode', () async {
    final unlocked =
        await OwnerDeleteService.instance.tryUnlockWithPin('adminpass1');

    expect(unlocked, isFalse);
    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });
}
