import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:meta/meta.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
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

  bool _started = false;
  bool _autoPullInProgress = false;
  String? _location;

  final ValueNotifier<bool> manualPushInProgress = ValueNotifier(false);

  @visibleForTesting
  Future<SalesApiResult<int>> Function(SaleBill bill)? saveBillOverride;

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

  /// Registers the active staff location — no periodic sync (event-driven only).
  void start({required String location}) {
    if (_started) {
      return;
    }

    _started = true;
    _location = location;
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    if (!_started) {
      return;
    }

    _started = false;
    _location = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Event-driven sync only — no background pulls.
  }

  /// Pull admin edits from the server (admin always wins on conflict).
  Future<void> pullAdminUpdates(String location) async {
    if (_autoPullInProgress) {
      return;
    }

    if (!await _isOnline()) {
      return;
    }

    _autoPullInProgress = true;
    try {
      final lastPull = await LocalDb.instance.getLastPullAt(location);
      final since =
          lastPull ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

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
      // Best-effort pull.
    } finally {
      _autoPullInProgress = false;
    }
  }

  /// Password-gated manual sync: push pending bills, pull admin bill edits + GST.
  Future<ManualPushResult> manualSync(String location) async {
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
      final pushResult = await manualPush(location);
      syncedCount = pushResult.syncedCount;
      failedCount = pushResult.failedCount;

      await pullAdminUpdates(location);

      final locationCode = _locationCodeFromDisplayName(location);
      await SalesApi.pullGstMasterData(locationCode);

      if (failedCount > 0) {
        return ManualPushResult(
          ok: false,
          syncedCount: syncedCount,
          failedCount: failedCount,
          error: pushResult.error,
        );
      }

      return ManualPushResult(
        ok: true,
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    } catch (_) {
      return ManualPushResult(
        ok: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        error: 'Could not sync',
      );
    } finally {
      manualPushInProgress.value = false;
    }
  }

  /// Push pending local bills only.
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

  String _locationCodeFromDisplayName(String location) {
    switch (location) {
      case 'Win1':
        return 'win1';
      case 'Win2':
        return 'win2';
      case 'Win3':
        return 'win3';
      case 'Win4':
        return 'win4';
      default:
        return AppConfig.locationCode;
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
