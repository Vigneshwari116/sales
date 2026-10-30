import 'package:flutter/foundation.dart';

/// Notifies staff dashboard sections to reload local summaries after sync/save.
class UiRefreshService {
  UiRefreshService._();

  static final ValueNotifier<int> generation = ValueNotifier(0);

  static void notifyBillSaved() {
    generation.value++;
  }
}
