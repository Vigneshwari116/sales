import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/credential_service.dart';
import 'package:sales/services/credential_storage.dart';

/// Seeds in-memory credentials for widget/integration tests.
Future<void> seedTestCredentials({
  String staffUsername = 'staffuser',
  String staffPassword = 'staffpass1',
  String adminUsername = 'adminuser',
  String adminPassword = 'adminpass1',
  String ownerDeletePin = 'pin9999',
}) async {
  CredentialService.useStorage(InMemoryCredentialStorage());
  await CredentialService.resetForTesting();
  SharedPreferences.setMockInitialValues({});
  await CredentialService.saveInitialSetup(
    staffUsername: staffUsername,
    staffPassword: staffPassword,
    adminUsername: adminUsername,
    adminPassword: adminPassword,
    ownerDeletePin: ownerDeletePin,
  );
}

Future<void> resetTestCredentials() async {
  await CredentialService.resetForTesting();
  CredentialService.useProductionStorage();
}
