import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over credential secret storage (secure storage in production).
abstract class CredentialStorage {
  Future<void> write({required String key, required String value});

  Future<String?> read({required String key});

  Future<void> delete({required String key});

  Future<void> deleteAll();
}

/// DPAPI-backed storage on Windows; Keychain/Keystore on mobile — production path.
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              wOptions: WindowsOptions(useBackwardCompatibility: false),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }

  @override
  Future<void> deleteAll() {
    return _storage.deleteAll();
  }
}

/// In-memory storage for widget/unit tests only.
class InMemoryCredentialStorage implements CredentialStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}
