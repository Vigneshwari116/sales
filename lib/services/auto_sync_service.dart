import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:sales/services/sync_service.dart';

/// Fully automatic sync (no button needed):
///  1. pushes pending (offline) bills to the server, then
///  2. pulls admin edits (and GST config) from the server.
///
/// Triggers: app start / login, internet coming back, app resumed,
/// right after a bill save, and a periodic timer (every 30 s).
class AutoSyncService with WidgetsBindingObserver {
  static AutoSyncService? _instance;
  static const Duration _retryInterval = Duration(seconds: 30);
  AutoSyncService._();
  static AutoSyncService get instance {
    _instance ??= AutoSyncService._();
    return _instance!;
  }

  String? _location;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _timer;
  void start({required String location}) {
    if (_location != null) {
      return;
    }
    _location = location;
    WidgetsBinding.instance.addObserver(this);
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) {
          trigger();
        }
      });
    } catch (_) {
      // Periodic retry below still covers reconnects.
    }
    _timer = Timer.periodic(_retryInterval, (_) => trigger());
    trigger();
  }

  void stop() {
    if (_location == null) {
      return;
    }
    _location = null;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _timer?.cancel();
    _timer = null;
  }

  @visibleForTesting
  static void resetForTesting() {
    instance.stop();
    _instance = null;
  }

  /// Safe to call from anywhere; does nothing when not started.
  void trigger() {
    final location = _location;
    if (location == null) {
      return;
    }
    unawaited(_run(location));
  }

  bool _running = false;
  Future<void> _run(String location) async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      // Push first so local bills are on the server before admin edits are
      // pulled (admin wins on conflict).
      await SyncService.instance.autoPush(location);
      await SyncService.instance.autoPull(location);
    } finally {
      _running = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      trigger();
    }
  }
}
