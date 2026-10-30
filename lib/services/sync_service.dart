import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:meta/meta.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/auto_sync_service.dart';
import 'package:sales/services/location_reset_service.dart';
import 'package:sales/services/ui_refresh_service.dart';

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
      return syncedCount == 1 ? '1 bill synced' : '$syncedCount bills synced';
    }

    return '$syncedCount synced, $failedCount failed';
  }
}

class PullResult {
  final bool ok;
  final int pulledCount;
  final String? error;

  const PullResult({required this.ok, required this.pulledCount, this.error});
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
  bool _autoPushInProgress = false;
  DateTime? _lastGstPullAt;
  static const Duration _gstPullInterval = Duration(minutes: 5);
  int _localSavesInFlight = 0;
  String? _location;

  final ValueNotifier<bool> manualPushInProgress = ValueNotifier(false);

  /// Number of bills saved on this device but not yet confirmed by the server.
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  /// Last known connectivity (updated by every auto-sync check).
  final ValueNotifier<bool> online = ValueNotifier(true);

  @visibleForTesting
  Future<SalesApiResult<int>> Function(SaleBill bill)? saveBillOverride;

  @visibleForTesting
  Future<bool> Function()? isOnlineOverride;

  @visibleForTesting
  Future<SalesApiResult<({List<SaleBill> bills, DateTime serverTime})>>
  Function({required String location, required DateTime since})?
  getBillUpdatesSinceOverride;

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
      current.pendingCount.value = 0;
      current.online.value = true;
    }
    AutoSyncService.resetForTesting();
    _instance = null;
  }

  /// Registers the active staff location and starts [AutoSyncService]
  /// (automatic push of pending bills + automatic pull of admin edits).
  void start({required String location}) {
    if (_started) {
      return;
    }

    _started = true;
    _location = location;
    WidgetsBinding.instance.addObserver(this);
    AutoSyncService.instance.start(location: location);
  }

  void stop() {
    if (!_started) {
      return;
    }

    _started = false;
    _location = null;
    WidgetsBinding.instance.removeObserver(this);
    AutoSyncService.instance.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume-triggered sync is handled by AutoSyncService.
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

    final resetBlock = await LocationResetService.ensureServerResetBeforeSync(
      location,
    );
    if (resetBlock != null) {
      return PullResult(ok: false, pulledCount: 0, error: resetBlock);
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
      return PullResult(ok: false, pulledCount: 0, error: 'Pull failed: $e');
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
      final resetBlock = await LocationResetService.ensureServerResetBeforeSync(
        location,
      );
      if (resetBlock != null) {
        return ManualSyncResult(
          ok: false,
          pushedCount: 0,
          pushFailedCount: 0,
          pulledCount: 0,
          error: resetBlock,
        );
      }

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

  /// Called by BillRepository around a local save so a background push never
  /// overwrites a bill that is being saved at that moment.
  void beginLocalSave() => _localSavesInFlight++;

  void endLocalSave() {
    if (_localSavesInFlight > 0) {
      _localSavesInFlight--;
    }
  }

  Future<void> refreshPendingCount(String location) async {
    try {
      final pending = await LocalDb.instance.getBillsBySyncStatus(
        'pending',
        location: location,
      );
      pendingCount.value = pending.length;
    } catch (_) {
      // Keep the previous count if the local database is unavailable.
    }
  }

  /// Silent background push of pending bills (no password, no UI lock).
  /// Returns null when there was nothing to do or the push was skipped.
  Future<ManualPushResult?> autoPush(String location) async {
    if (_autoPushInProgress ||
        manualPushInProgress.value ||
        _localSavesInFlight > 0) {
      return null;
    }
    _autoPushInProgress = true;

    try {
      final isOnline = await (isOnlineOverride?.call() ?? _isOnline());
      online.value = isOnline;

      final pending = await LocalDb.instance.getBillsBySyncStatus(
        'pending',
        location: location,
      );
      pendingCount.value = pending.length;

      if (pending.isEmpty || !isOnline) {
        return null;
      }

      final resetBlock = await LocationResetService.ensureServerResetBeforeSync(
        location,
      );
      if (resetBlock != null) {
        return null;
      }

      final result = await _executePush(location, stopOnFirstFailure: true);
      await refreshPendingCount(location);
      return result;
    } catch (_) {
      return null;
    } finally {
      _autoPushInProgress = false;
    }
  }

  /// Silent background pull of admin edits (+ GST config, throttled).
  /// Never runs while local bills are unsent, so admin data can't overwrite
  /// an offline bill before it reaches the server.
  Future<void> autoPull(String location) async {
    if (_autoPullInProgress ||
        _autoPushInProgress ||
        manualPushInProgress.value ||
        _localSavesInFlight > 0) {
      return;
    }

    try {
      final isOnline = await (isOnlineOverride?.call() ?? _isOnline());
      online.value = isOnline;
      if (!isOnline) {
        return;
      }

      final pending = await LocalDb.instance.getBillsBySyncStatus(
        'pending',
        location: location,
      );
      pendingCount.value = pending.length;
      if (pending.isNotEmpty) {
        return;
      }

      final result = await pullAdminUpdates(location);
      if (result.ok && result.pulledCount > 0) {
        UiRefreshService.notifyBillSaved();
      }

      final now = DateTime.now();
      final lastGst = _lastGstPullAt;
      if (lastGst == null || now.difference(lastGst) >= _gstPullInterval) {
        _lastGstPullAt = now;
        try {
          await SalesApi.pullGstMasterData(
            _locationCodeFromDisplayName(location),
          );
        } catch (_) {
          // Retried on the next interval.
        }
      }
    } catch (_) {
      // Silent: the next trigger retries.
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
      final resetBlock = await LocationResetService.ensureServerResetBeforeSync(
        location,
      );
      if (resetBlock != null) {
        return ManualPushResult(
          ok: false,
          syncedCount: 0,
          failedCount: 0,
          error: resetBlock,
        );
      }

      return await _executePush(location);
    } finally {
      manualPushInProgress.value = false;
    }
  }

  Future<ManualPushResult> _executePush(
    String location, {
    bool stopOnFirstFailure = false,
  }) async {
    var syncedCount = 0;
    var failedCount = 0;

    try {
      final pending = await LocalDb.instance.getBillsBySyncStatus(
        'pending',
        location: location,
      );

      final saveBill = saveBillOverride ?? SalesApi.saveBill;

      for (final stored in pending) {
        if (stopOnFirstFailure && _localSavesInFlight > 0) {
          break;
        }

        final result = await saveBill(stored.bill);

        if (result.ok) {
          await LocalDb.instance.markSynced(stored.localId);
          syncedCount++;
        } else {
          failedCount++;
          if (stopOnFirstFailure) {
            // Server unreachable: stop, keep bill order, retry on next trigger.
            break;
          }
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
      default:
        return AppConfig.locationCode;
    }
  }

  Future<bool> isDeviceOnline() async {
    return isOnlineOverride?.call() ?? _isOnline();
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
