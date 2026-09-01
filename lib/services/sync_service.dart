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

class PullResult {
  final bool ok;
  final int pulledCount;
  final String? error;

  const PullResult({
    required this.ok,
    required this.pulledCount,
    this.error,
  });
}

class ManualSyncResult {
  final bool ok;
  final int pushedCount;
  final int pushFailedCount;
  final int pulledCount;
  final String? error;
  final String? pullError;
  final String? gstError;

  const ManualSyncResult({
    required this.ok,
    required this.pushedCount,
    required this.pushFailedCount,
    required this.pulledCount,
    this.error,
    this.pullError,
    this.gstError,
  });

  String get summaryMessage {
    if (error != null &&
        pushedCount == 0 &&
        pushFailedCount == 0 &&
        pulledCount == 0 &&
        pullError == null) {
      return 'Sync failed: $error';
    }

    final pushText = pushFailedCount > 0
        ? '$pushedCount bills pushed, $pushFailedCount failed'
        : '$pushedCount bills pushed';

    if (pullError != null) {
      if (pushedCount > 0 || pushFailedCount > 0) {
        return 'Partial sync: $pushText; pull failed: $pullError';
      }
      return 'Sync failed: $pullError';
    }

    if (gstError != null && pushedCount == 0 && pulledCount == 0) {
      return 'Sync failed: $gstError';
    }

    if (!ok) {
      return 'Sync failed: $pushText — ${error ?? "unknown error"}';
    }

    var message = 'Synced: $pushText, $pulledCount updates pulled';
    if (gstError != null) {
      message = '$message (GST pull warning: $gstError)';
    }
    return message;
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

  @visibleForTesting
  Future<
      SalesApiResult<({List<SaleBill> bills, DateTime serverTime})>> Function({
    required String location,
    required DateTime since,
  })? getBillUpdatesSinceOverride;

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
      current.getBillUpdatesSinceOverride = null;
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
  Future<PullResult> pullAdminUpdates(String location) async {
    if (_autoPullInProgress) {
      return const PullResult(
        ok: false,
        pulledCount: 0,
        error: 'Pull already in progress',
      );
    }

    if (!await (isOnlineOverride?.call() ?? _isOnline())) {
      return const PullResult(
        ok: false,
        pulledCount: 0,
        error: 'No internet connection',
      );
    }

    _autoPullInProgress = true;
    try {
      final lastPull = await LocalDb.instance.getLastPullAt(location);
      final since =
          lastPull ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

      final fetch = getBillUpdatesSinceOverride ?? SalesApi.getBillUpdatesSince;
      final result = await fetch(location: location, since: since);

      if (!result.ok || result.data == null) {
        return PullResult(
          ok: false,
          pulledCount: 0,
          error: result.error ?? 'Could not pull bill updates from server',
        );
      }

      final bills = result.data!.bills;
      var pulledCount = 0;
      if (bills.isNotEmpty) {
        pulledCount = await LocalDb.instance.applyPulledBills(bills);
      }

      await LocalDb.instance.setLastPullAt(location, result.data!.serverTime);

      return PullResult(ok: true, pulledCount: pulledCount);
    } catch (e) {
      return PullResult(
        ok: false,
        pulledCount: 0,
        error: 'Pull failed: $e',
      );
    } finally {
      _autoPullInProgress = false;
    }
  }

  /// Password-gated manual sync: push pending bills, pull admin bill edits + GST.
  Future<ManualSyncResult> manualSync(String location) async {
    if (manualPushInProgress.value) {
      return ManualSyncResult(
        ok: false,
        pushedCount: 0,
        pushFailedCount: 0,
        pulledCount: 0,
        error: 'Sync already in progress',
      );
    }

    if (!await (isOnlineOverride?.call() ?? _isOnline())) {
      return const ManualSyncResult(
        ok: false,
        pushedCount: 0,
        pushFailedCount: 0,
        pulledCount: 0,
        error: 'No internet connection',
      );
    }

    manualPushInProgress.value = true;

    try {
      final pushResult = await _executePush(location);
      final pullResult = await pullAdminUpdates(location);

      String? gstError;
      try {
        final locationCode = _locationCodeFromDisplayName(location);
        final gstResult = await SalesApi.pullGstMasterData(locationCode);
        if (!gstResult.ok) {
          gstError = gstResult.error ?? 'Could not pull GST config';
        }
      } catch (e) {
        gstError = 'GST pull failed: $e';
      }

      final ok = pushResult.failedCount == 0 && pullResult.ok;

      return ManualSyncResult(
        ok: ok,
        pushedCount: pushResult.syncedCount,
        pushFailedCount: pushResult.failedCount,
        pulledCount: pullResult.pulledCount,
        error: pushResult.error,
        pullError: pullResult.ok ? null : pullResult.error,
        gstError: gstError,
      );
    } catch (e) {
      return ManualSyncResult(
        ok: false,
        pushedCount: 0,
        pushFailedCount: 0,
        pulledCount: 0,
        error: 'Sync failed: $e',
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

    try {
      return await _executePush(location);
    } finally {
      manualPushInProgress.value = false;
    }
  }

  Future<ManualPushResult> _executePush(String location) async {
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
    } catch (e) {
      return ManualPushResult(
        ok: false,
        syncedCount: syncedCount,
        failedCount: failedCount,
        error: 'Could not sync bills: $e',
      );
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
