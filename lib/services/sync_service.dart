import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:meta/meta.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class ManualPushResult {
  final bool ok;
  final int syncedCount;
  final int failedCount;
  final String? error;

  const ManualPushResult({
    required this.ok,
    required this.syncedCount,
    required this.failedCount,
    this.error,
  });

  String get summaryMessage {
    if (error != null && syncedCount == 0) {
      return error!;
    }

    if (syncedCount == 0 && failedCount == 0) {
      return 'No pending bills to sync';
    }

    if (failedCount == 0) {
      return syncedCount == 1
          ? '1 bill synced'
          : '$syncedCount bills synced';
    }

    return '$syncedCount synced, $failedCount failed';
  }
}

class SyncService with WidgetsBindingObserver {
  static SyncService? _instance;

  Timer? _periodicTimer;
  bool _inForeground = true;
  bool _started = false;
  bool _autoPullInProgress = false;
  String? _location;

  final ValueNotifier<bool> manualPushInProgress = ValueNotifier(false);

  /// When set, replaces [SalesApi.saveBill] (for tests only).
  @visibleForTesting
  Future<SalesApiResult<int>> Function(SaleBill bill)? saveBillOverride;

  /// When set, replaces connectivity check (for tests only).
  @visibleForTesting
  Future<bool> Function()? isOnlineOverride;

  SyncService._();

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  @visibleForTesting
  static Future<void> resetForTesting() async {
    final current = _instance;
    if (current != null) {
      current.stop();
      current.saveBillOverride = null;
      current.isOnlineOverride = null;
      current.manualPushInProgress.value = false;
    }
    _instance = null;
  }

  void start({required String location}) {
    if (_started) {
      return;
    }

    _started = true;
    _location = location;
    WidgetsBinding.instance.addObserver(this);

    autoPull(location);

    _startPeriodicTimer();
  }

  void stop() {
    if (!_started) {
      return;
    }

    _started = false;
    _location = null;
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;

    if (_inForeground) {
      _startPeriodicTimer();
      final location = _location;
      if (location != null) {
        autoPull(location);
      }
    } else {
      _periodicTimer?.cancel();
      _periodicTimer = null;
    }
  }

  void _startPeriodicTimer() {
    _periodicTimer?.cancel();

    if (!_inForeground || _location == null) {
      return;
    }

    final location = _location!;
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => autoPull(location),
    );
  }

  /// Silent, non-locking pull of admin edits from the server.
  Future<void> autoPull(String location) async {
    if (_autoPullInProgress) {
      return;
    }

    if (!await _isOnline()) {
      return;
    }

    _autoPullInProgress = true;
    try {
      final lastPull = await LocalDb.instance.getLastPullAt(location);
      final since = lastPull ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final result = await SalesApi.getBillUpdatesSince(
        location: location,
        since: since,
      );

      if (!result.ok || result.data == null) {
        return;
      }

      final bills = result.data!.bills;
      if (bills.isNotEmpty) {
        await LocalDb.instance.applyPulledBills(bills);
      }

      await LocalDb.instance.setLastPullAt(location, result.data!.serverTime);
    } catch (_) {
      // Auto-pull is best-effort and must not interrupt bill entry.
    } finally {
      _autoPullInProgress = false;
    }
  }

  /// Button-triggered push of pending local bills. Locks the UI while running.
  Future<ManualPushResult> manualPush(String location) async {
    if (manualPushInProgress.value) {
      return const ManualPushResult(
        ok: false,
        syncedCount: 0,
        failedCount: 0,
        error: 'Sync already in progress',
      );
    }

    if (!await (isOnlineOverride?.call() ?? _isOnline())) {
      return const ManualPushResult(
        ok: false,
        syncedCount: 0,
        failedCount: 0,
        error: 'No internet connection',
      );
    }

    manualPushInProgress.value = true;
    var syncedCount = 0;
    var failedCount = 0;

    try {
      final pending = await LocalDb.instance.getBillsBySyncStatus(
        'pending',
        location: location,
      );

      final saveBill = saveBillOverride ?? SalesApi.saveBill;

      for (final stored in pending) {
        final result = await saveBill(stored.bill);

        if (result.ok) {
          await LocalDb.instance.markSynced(stored.localId);
          syncedCount++;
        } else {
          failedCount++;
        }
      }

      return ManualPushResult(
        ok: failedCount == 0,
        syncedCount: syncedCount,
        failedCount: failedCount,
        error: failedCount > 0 ? 'Some bills could not be synced' : null,
      );
    } catch (_) {
      return ManualPushResult(
        ok: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        error: 'Could not sync bills',
      );
    } finally {
      manualPushInProgress.value = false;
    }
  }

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
