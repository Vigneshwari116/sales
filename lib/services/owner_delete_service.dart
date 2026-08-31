import 'package:flutter/foundation.dart';
import 'package:sales/services/credential_service.dart';

/// Owner-only gate for soft-deleting saved bills from the ledger.
class OwnerDeleteService extends ChangeNotifier {
  OwnerDeleteService._();

  static final OwnerDeleteService instance = OwnerDeleteService._();

  bool _deleteEnabled = false;

  bool get isDeleteEnabled => _deleteEnabled;

  /// Returns `true` only when [pin] matches the stored owner-delete PIN.
  Future<bool> tryUnlockWithPin(String pin) async {
    if (!await CredentialService.verifyOwnerDeletePin(pin)) {
      return false;
    }

    enable();
    return true;
  }

  void enable() {
    if (_deleteEnabled) {
      return;
    }
    _deleteEnabled = true;
    notifyListeners();
  }

  void disable() {
    if (!_deleteEnabled) {
      return;
    }
    _deleteEnabled = false;
    notifyListeners();
  }
}
