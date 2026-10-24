import 'package:flutter/foundation.dart';

/// Notifies dashboard/abstract shells to reload after a bill is saved locally.
class UiRefreshService {
  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static void notifyBillSaved() {
    generation.value++;
  }
}
