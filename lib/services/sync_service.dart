import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class SyncService with WidgetsBindingObserver {
  static SyncService? _instance;

  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _inForeground = true;
  bool _started = false;

  SyncService._();

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  void start() {
    if (_started) {
      return;
    }

    _started = true;
    WidgetsBinding.instance.addObserver(this);

    pushPendingBills();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasConnection(results)) {
        pushPendingBills();
      }
    });

    _startPeriodicTimer();
  }

  void stop() {
    if (!_started) {
      return;
    }

    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;

    if (_inForeground) {
      _startPeriodicTimer();
      pushPendingBills();
    } else {
      _periodicTimer?.cancel();
      _periodicTimer = null;
    }
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();

    if (!_inForeground) {
      return;
    }

    _periodicTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => pushPendingBills(),
    );
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((result) {
      return result != ConnectivityResult.none;
    });
  }

  Future<void> pushPendingBills() async {
    try {
      var rows = await LocalDb.instance.getPendingBills();

      for (var row in rows) {
        var localId = row['local_id'] as String;
        var payload = row['payload'] as String;

        try {
          var billJson = jsonDecode(payload) as Map<String, dynamic>;
          var bill = SaleBill.fromJson(billJson);
          var result = await SalesApi.saveBill(bill);

          if (result.ok) {
            await LocalDb.instance.markBillSynced(localId);
          }
        } catch (_) {
          // Leave as pending for the next cycle.
        }
      }
    } catch (_) {
      // Don't throw — sync runs in the background.
    }
  }
}
