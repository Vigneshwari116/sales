import 'package:flutter/foundation.dart';

/// Notifies dashboard shells to reload ledger, abstract, and related views.
class UiRefreshService {
  UiRefreshService._();

  static final UiRefreshService instance = UiRefreshService._();

  final ValueNotifier<int> billDataGeneration = ValueNotifier<int>(0);

  void notifyBillSaved() {
    billDataGeneration.value++;
  }
}
