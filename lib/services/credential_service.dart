import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/services/credential_storage.dart';

/// Offline credential management — hashed secrets in secure storage.
///
/// One credential set per **app install** (each location device runs setup
/// independently; secrets are not synced across devices).
class CredentialService {
  CredentialService._();

  static const int minPasswordLength = 8;
  static const int minPinLength = 4;

  static const String _configuredPrefsKey = 'credentials_configured';

  static const String _saltKey = 'cred_install_salt';
  static const String _staffUsernameKey = 'cred_staff_username';
  static const String _staffHashKey = 'cred_staff_hash';
  static const String _adminUsernameKey = 'cred_admin_username';
  static const String _adminHashKey = 'cred_admin_hash';
  static const String _deletePinHashKey = 'cred_delete_pin_hash';

  static CredentialStorage _storage = SecureCredentialStorage();

  @visibleForTesting
  static void useStorage(CredentialStorage storage) {
    _storage = storage;
  }

  @visibleForTesting
  static void useProductionStorage() {
    _storage = SecureCredentialStorage();
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configuredPrefsKey);
    await _storage.deleteAll();
  }

  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_configuredPrefsKey) ?? false;
  }

  static Future<String?> staffUsername() => _storage.read(key: _staffUsernameKey);

  static Future<String?> adminUsername() => _storage.read(key: _adminUsernameKey);

  static Future<void> saveInitialSetup({
    required String staffUsername,
    required String staffPassword,
    required String adminUsername,
    required String adminPassword,
    required String ownerDeletePin,
  }) async {
    _validateUsername(staffUsername);
    _validateUsername(adminUsername);
    _validatePassword(staffPassword);
    _validatePassword(adminPassword);
    _validatePin(ownerDeletePin);

    if (adminPassword == ownerDeletePin) {
      throw CredentialValidationException(
        'Admin password and owner-delete PIN must be different.',
      );
    }

    if (await isConfigured()) {
      throw StateError('Credentials are already configured.');
    }

    final salt = _generateSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _staffUsernameKey, value: staffUsername.trim());
    await _storage.write(
      key: _staffHashKey,
      value: _hashSecret(staffPassword, salt),
    );
    await _storage.write(key: _adminUsernameKey, value: adminUsername.trim());
    await _storage.write(
      key: _adminHashKey,
      value: _hashSecret(adminPassword, salt),
    );
    await _storage.write(
      key: _deletePinHashKey,
      value: _hashSecret(ownerDeletePin, salt),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_configuredPrefsKey, true);
  }

  static Future<bool> verifyStaff(String username, String password) async {
    if (!await isConfigured()) {
      return false;
    }

    final storedUser = await _storage.read(key: _staffUsernameKey);
    if (storedUser == null || storedUser != username.trim()) {
      return false;
    }

    return _verifySecret(password, _staffHashKey);
  }

  static Future<bool> verifyAdmin(String username, String password) async {
    if (!await isConfigured()) {
      return false;
    }

    final storedUser = await _storage.read(key: _adminUsernameKey);
    if (storedUser == null || storedUser != username.trim()) {
      return false;
    }

    return _verifySecret(password, _adminHashKey);
  }

  static Future<bool> verifyOwnerDeletePin(String pin) async {
    if (!await isConfigured()) {
      return false;
    }

    return _verifySecret(pin, _deletePinHashKey);
  }

  static Future<bool> rotateStaffPassword({
    required String currentAdminPassword,
    required String newPassword,
  }) async {
    if (!await verifyAdmin(
      (await adminUsername()) ?? '',
      currentAdminPassword,
    )) {
      return false;
    }

    _validatePassword(newPassword);
    final salt = await _requireSalt();
    await _storage.write(
      key: _staffHashKey,
      value: _hashSecret(newPassword, salt),
    );
    return true;
  }

  static Future<bool> rotateAdminPassword({
    required String currentAdminPassword,
    required String newUsername,
    required String newPassword,
  }) async {
    final currentAdminUser = await adminUsername();
    if (currentAdminUser == null) {
      return false;
    }

    if (!await verifyAdmin(currentAdminUser, currentAdminPassword)) {
      return false;
    }

    _validateUsername(newUsername);
    _validatePassword(newPassword);

    final deletePinMatches = await verifyOwnerDeletePin(newPassword);
    if (deletePinMatches) {
      throw CredentialValidationException(
        'Admin password must be different from the owner-delete PIN.',
      );
    }

    final salt = await _requireSalt();
    await _storage.write(key: _adminUsernameKey, value: newUsername.trim());
    await _storage.write(
      key: _adminHashKey,
      value: _hashSecret(newPassword, salt),
    );
    return true;
  }

  /// Requires the current delete PIN only — no admin password override.
  static Future<bool> rotateOwnerDeletePin({
    required String currentDeletePin,
    required String newPin,
  }) async {
    if (!await verifyOwnerDeletePin(currentDeletePin)) {
      return false;
    }

    _validatePin(newPin);

    final adminUser = await adminUsername();
    if (adminUser != null) {
      // Prevent setting delete PIN equal to admin password text.
      final adminHash = await _storage.read(key: _adminHashKey);
      final salt = await _requireSalt();
      if (adminHash != null && _hashSecret(newPin, salt) == adminHash) {
        throw CredentialValidationException(
          'Owner-delete PIN must be different from the admin password.',
        );
      }
    }

    final salt = await _requireSalt();
    await _storage.write(
      key: _deletePinHashKey,
      value: _hashSecret(newPin, salt),
    );
    return true;
  }

  static void _validateUsername(String username) {
    if (username.trim().isEmpty) {
      throw CredentialValidationException('Username is required.');
    }
  }

  static void _validatePassword(String password) {
    if (password.length < minPasswordLength) {
      throw CredentialValidationException(
        'Password must be at least $minPasswordLength characters.',
      );
    }
  }

  static void _validatePin(String pin) {
    if (pin.length < minPinLength) {
      throw CredentialValidationException(
        'Owner-delete PIN must be at least $minPinLength characters.',
      );
    }
  }

  static String _generateSalt() {
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hashSecret(String secret, String salt) {
    final digest = sha256.convert(utf8.encode('$salt::$secret'));
    return digest.toString();
  }

  static Future<bool> _verifySecret(String secret, String hashKey) async {
    final salt = await _storage.read(key: _saltKey);
    final storedHash = await _storage.read(key: hashKey);
    if (salt == null || storedHash == null) {
      return false;
    }

    return _hashSecret(secret, salt) == storedHash;
  }

  static Future<String> _requireSalt() async {
    final salt = await _storage.read(key: _saltKey);
    if (salt == null) {
      throw StateError('Credential salt is missing.');
    }
    return salt;
  }
}

class CredentialValidationException implements Exception {
  final String message;

  CredentialValidationException(this.message);

  @override
  String toString() => message;
}
