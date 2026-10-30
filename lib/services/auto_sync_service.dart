import 'package:flutter/widgets.dart';

import 'package:sales/services/sync_service.dart';

/// Event-driven sync only — no periodic background pulls.
class AutoSyncService with WidgetsBindingObserver {
  static AutoSyncService? _instance;

  AutoSyncService._();

  static AutoSyncService get instance {
    _instance ??= AutoSyncService._();
    return _instance!;
  }

  void start() {}

  void stop() {}

  /// After a local delete-all, refresh sync counters so nothing stale is pushed.
  void handleLocalBillsDeleted(String locationDisplayName) {
    SyncService.instance.refreshPendingBillCount(locationDisplayName);
  }
}
