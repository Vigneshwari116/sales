import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/services/session_service.dart';

class LocationResetResult {
  final bool ok;
  final bool localCleared;
  final bool serverCleared;
  final bool serverResetQueued;
  final String? error;

  const LocationResetResult({
    required this.ok,
    required this.localCleared,
    required this.serverCleared,
    required this.serverResetQueued,
    this.error,
  });
}

class FlushPendingResetsResult {
  final bool ok;
  final List<String> remainingLocationCodes;

  const FlushPendingResetsResult({
    required this.ok,
    required this.remainingLocationCodes,
  });
}

/// Clears all sales data for the current location locally and on the server.
class LocationResetService {
  static const String _pendingKey = 'pending_server_reset_locations';

  static const String resetWipesLocalAndServerMessage =
      'RESET wipes local and server data for this location. '
      'Always finish with SYNC if you reset while offline.';

  static const String pendingResetOfflineMessage =
      'Server reset pending. Go online and use SYNC to wipe server data '
      'before uploading or downloading bills.';

  static const String pendingResetFailedMessage =
      'Server reset could not complete. Try SYNC again before uploading bills.';

  @visibleForTesting
  static Future<SalesApiResult<void>> Function({
    required String location,
    required String password,
  })? resetLocationSalesOverride;

  @visibleForTesting
  static Future<bool> Function()? isDeviceOnlineOverride;

  static Future<LocationResetResult> resetCurrentLocation({
    required String locationDisplayName,
    required String password,
  }) async {
    if (password != resetPassword) {
      return const LocationResetResult(
        ok: false,
        localCleared: false,
        serverCleared: false,
        serverResetQueued: false,
        error: 'Incorrect password',
      );
    }

    try {
      await LocalDb.instance.resetLocationSalesData(locationDisplayName);
      await SessionService.clearBillSession();

      final locationCode = locationCodeFromDisplayName(locationDisplayName);
      var serverCleared = false;
      var serverResetQueued = false;
      String? error;

      final online = await _isDeviceOnline();

      if (online) {
        final apiResult = await _resetLocationSales(
          location: locationDisplayName,
          password: resetPassword,
        );
        if (apiResult.ok) {
          serverCleared = true;
          await _removePendingServerReset(locationCode);
        } else {
          await _queueServerReset(locationCode);
          serverResetQueued = true;
          error = apiResult.error;
        }
      } else {
        await _queueServerReset(locationCode);
        serverResetQueued = true;
      }

      return LocationResetResult(
        ok: true,
        localCleared: true,
        serverCleared: serverCleared,
        serverResetQueued: serverResetQueued,
        error: error,
      );
    } catch (e) {
      return LocationResetResult(
        ok: false,
        localCleared: false,
        serverCleared: false,
        serverResetQueued: false,
        error: 'Reset failed: $e',
      );
    }
  }

  /// Runs any queued server wipe before sync/push/pull.
  /// Returns an error message when bills must not be uploaded or downloaded yet.
  static Future<String?> ensureServerResetBeforeSync(
    String locationDisplayName,
  ) async {
    final locationCode = locationCodeFromDisplayName(locationDisplayName);
    if (!await hasPendingServerReset(locationCode)) {
      return null;
    }

    if (!await _isDeviceOnline()) {
      return pendingResetOfflineMessage;
    }

    final flushResult = await flushPendingServerResets();
    if (!flushResult.ok && flushResult.remainingLocationCodes.contains(locationCode)) {
      return pendingResetFailedMessage;
    }

    if (await hasPendingServerReset(locationCode)) {
      return pendingResetFailedMessage;
    }

    return null;
  }

  static Future<FlushPendingResetsResult> flushPendingServerResets() async {
    if (!await _isDeviceOnline()) {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingKey) ?? const [];
      return FlushPendingResetsResult(
        ok: pending.isEmpty,
        remainingLocationCodes: pending,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_pendingKey) ?? const [],
    );

    if (pending.isEmpty) {
      return const FlushPendingResetsResult(ok: true, remainingLocationCodes: []);
    }

    final remaining = <String>[];
    for (final code in pending) {
      final displayName = displayNameForLocationCode(code);
      final result = await _resetLocationSales(
        location: displayName,
        password: resetPassword,
      );
      if (!result.ok) {
        remaining.add(code);
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setStringList(_pendingKey, remaining);
    }

    return FlushPendingResetsResult(
      ok: remaining.isEmpty,
      remainingLocationCodes: remaining,
    );
  }

  static Future<bool> hasPendingServerReset(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingKey) ?? const [];
    return pending.contains(locationCode);
  }

  static Future<void> _queueServerReset(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_pendingKey) ?? const [],
    );
    if (!pending.contains(locationCode)) {
      pending.add(locationCode);
      await prefs.setStringList(_pendingKey, pending);
    }
  }

  static Future<void> _removePendingServerReset(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_pendingKey) ?? const [],
    );
    pending.remove(locationCode);
    if (pending.isEmpty) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setStringList(_pendingKey, pending);
    }
  }

  static Future<SalesApiResult<void>> _resetLocationSales({
    required String location,
    required String password,
  }) {
    final override = resetLocationSalesOverride;
    if (override != null) {
      return override(location: location, password: password);
    }

    return SalesApi.resetLocationSales(
      location: location,
      password: password,
    );
  }

  @visibleForTesting
  static Future<void> clearPendingForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    resetLocationSalesOverride = null;
    isDeviceOnlineOverride = null;
  }

  static Future<bool> _isDeviceOnline() async {
    final override = isDeviceOnlineOverride;
    if (override != null) {
      return override();
    }

    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
