import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/services/sync_service.dart';

class AutoSyncService with WidgetsBindingObserver {
  static AutoSyncService? _instance;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _gstPeriodicTimer;
  bool _started = false;
  bool _inForeground = true;

  AutoSyncService._();

  static AutoSyncService get instance {
    _instance ??= AutoSyncService._();
    return _instance!;
  }

  void start() {
    if (_started) {
      return;
    }

    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _runAutoSync();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasConnection(results)) {
        _runAutoSync();
      }
    });

    _startGstPeriodicTimer();
  }

  void stop() {
    if (!_started) {
      return;
    }

    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _gstPeriodicTimer?.cancel();
    _gstPeriodicTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;

    if (_inForeground) {
      _startGstPeriodicTimer();
      _runAutoSync();
    } else {
      _gstPeriodicTimer?.cancel();
      _gstPeriodicTimer = null;
    }
  }

  void _startGstPeriodicTimer() {
    _gstPeriodicTimer?.cancel();

    if (!_inForeground) {
      return;
    }

    _gstPeriodicTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _runAutoSync(),
    );
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) {
      return result != ConnectivityResult.none;
    });
  }

  Future<void> _runAutoSync() async {
    await SyncService.instance.pushPendingBills();
    await SalesApi.pullGstMasterData(AppConfig.locationCode);
  }
}
