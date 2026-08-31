import 'package:flutter/widgets.dart';

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
}
