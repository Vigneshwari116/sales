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

/// Clears all sales data for the current location locally and on the server.
class LocationResetService {
  static const String _pendingKey = 'pending_server_reset_locations';

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
        final apiResult = await SalesApi.resetLocationSales(
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

  static Future<void> flushPendingServerResets() async {
    if (!await _isDeviceOnline()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final pending = List<String>.from(
      prefs.getStringList(_pendingKey) ?? const [],
    );

    if (pending.isEmpty) {
      return;
    }

    final remaining = <String>[];
    for (final code in pending) {
      final displayName = displayNameForLocationCode(code);
      final result = await SalesApi.resetLocationSales(
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

  @visibleForTesting
  static Future<void> clearPendingForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  static Future<bool> _isDeviceOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
