import 'package:flutter/foundation.dart';

/// Owner-only gate for soft-deleting saved bills from the ledger.
class OwnerDeleteService extends ChangeNotifier {
  OwnerDeleteService._();

  static final OwnerDeleteService instance = OwnerDeleteService._();

  bool _deleteEnabled = false;

  bool get isDeleteEnabled => _deleteEnabled;

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
