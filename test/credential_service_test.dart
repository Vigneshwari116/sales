import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/credential_service.dart';
import 'package:sales/services/credential_storage.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CredentialService.useStorage(InMemoryCredentialStorage());
  });

  tearDown(() async {
    await CredentialService.resetForTesting();
  });

  test('saveInitialSetup stores hashed credentials', () async {
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    expect(await CredentialService.isConfigured(), isTrue);
    expect(await CredentialService.verifyStaff('counter', 'staffpass1'), isTrue);
    expect(await CredentialService.verifyStaff('counter', 'wrong'), isFalse);
    expect(await CredentialService.verifyAdmin('owner', 'adminpass1'), isTrue);
    expect(await CredentialService.verifyOwnerDeletePin('delete99'), isTrue);
  });

  test('verifyOwnerDeletePin rejects admin password for delete unlock', () async {
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    expect(await CredentialService.verifyAdmin('owner', 'adminpass1'), isTrue);
    expect(await CredentialService.verifyOwnerDeletePin('adminpass1'), isFalse);
    expect(await CredentialService.verifyOwnerDeletePin('delete99'), isTrue);
  });

  test('admin password cannot equal owner-delete PIN at setup', () async {
    expect(
      () => CredentialService.saveInitialSetup(
        staffUsername: 's',
        staffPassword: 'staffpass1',
        adminUsername: 'a',
        adminPassword: 'samepin99',
        ownerDeletePin: 'samepin99',
      ),
      throwsA(isA<CredentialValidationException>()),
    );
  });

  test('rotateStaffPassword requires admin password', () async {
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    final ok = await CredentialService.rotateStaffPassword(
      currentAdminPassword: 'adminpass1',
      newPassword: 'newstaff1',
    );
    expect(ok, isTrue);
    expect(await CredentialService.verifyStaff('counter', 'newstaff1'), isTrue);
    expect(await CredentialService.verifyStaff('counter', 'staffpass1'), isFalse);
  });

  test('rotateAdminPassword invalidates old admin password immediately',
      () async {
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    expect(await CredentialService.verifyAdmin('owner', 'adminpass1'), isTrue);

    final ok = await CredentialService.rotateAdminPassword(
      currentAdminPassword: 'adminpass1',
      newUsername: 'owner',
      newPassword: 'newadmin88',
    );
    expect(ok, isTrue);

    expect(await CredentialService.verifyAdmin('owner', 'adminpass1'), isFalse);
    expect(await CredentialService.verifyAdmin('owner', 'newadmin88'), isTrue);
  });

  test('rotateOwnerDeletePin requires current PIN only', () async {
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    final wrongAdmin = await CredentialService.rotateOwnerDeletePin(
      currentDeletePin: 'adminpass1',
      newPin: 'newpin88',
    );
    expect(wrongAdmin, isFalse);

    final ok = await CredentialService.rotateOwnerDeletePin(
      currentDeletePin: 'delete99',
      newPin: 'newpin88',
    );
    expect(ok, isTrue);
    expect(await CredentialService.verifyOwnerDeletePin('newpin88'), isTrue);
    expect(await CredentialService.verifyOwnerDeletePin('delete99'), isFalse);
  });

  test('admin and delete PIN hashes use bcrypt; staff hash uses SHA-256',
      () async {
    final mem = InMemoryCredentialStorage();
    CredentialService.useStorage(mem);
    await CredentialService.saveInitialSetup(
      staffUsername: 'counter',
      staffPassword: 'staffpass1',
      adminUsername: 'owner',
      adminPassword: 'adminpass1',
      ownerDeletePin: 'delete99',
    );

    final staffHash = await mem.read(key: 'cred_staff_hash');
    final adminHash = await mem.read(key: 'cred_admin_hash');
    final pinHash = await mem.read(key: 'cred_delete_pin_hash');

    expect(staffHash, isNot(startsWith('\$2')));
    expect(adminHash, startsWith('\$2'));
    expect(pinHash, startsWith('\$2'));
  });
}
