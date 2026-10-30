import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/summary_db.dart';
import 'package:sales/services/auto_sync_service.dart';
import 'package:sales/services/daily_total_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/services/ui_refresh_service.dart';

class DeleteAllBillsResult {
  final bool ok;
  final String? error;

  const DeleteAllBillsResult({required this.ok, this.error});
}

/// Wipes all saved bills for the active location locally (no server delete).
class DeleteAllBillsService {
  DeleteAllBillsService._();

  static const String _pullAnchorKeyPrefix = 'local_bills_wipe_pull_anchor_';

  static Future<DeleteAllBillsResult> deleteAllForLocation(
    String locationDisplayName,
  ) async {
    try {
      await LocalDb.instance.initialize();
      final pullAnchor = DateTime.now().toUtc();

      await LocalDb.instance.resetLocationSalesData(
        locationDisplayName,
        pullAnchorUtc: pullAnchor,
      );

      await SummaryDb.instance.initialize();
      await SummaryDb.instance.clearSummariesForLocation(locationDisplayName);

      final locationCode = locationCodeFromDisplayName(locationDisplayName);
      await DailyTotalService.clearPendingForLocationCode(locationCode);
      await _persistPullAnchor(locationCode, pullAnchor);

      await SessionService.clearBillSession();

      await SyncService.instance.refreshPendingBillCount(locationDisplayName);
      AutoSyncService.instance.handleLocalBillsDeleted(locationDisplayName);

      UiRefreshService.instance.notifyBillSaved();

      return const DeleteAllBillsResult(ok: true);
    } catch (e) {
      return DeleteAllBillsResult(ok: false, error: 'Delete all bills failed: $e');
    }
  }

  /// Earliest server pull time after a local wipe (prevents re-importing history).
  static Future<DateTime?> pullAnchorForLocationCode(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pullAnchorKeyPrefix + locationCode);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  @visibleForTesting
  static Future<void> clearPullAnchorForTesting(String locationCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pullAnchorKeyPrefix + locationCode);
  }

  static Future<void> _persistPullAnchor(
    String locationCode,
    DateTime anchorUtc,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pullAnchorKeyPrefix + locationCode,
      anchorUtc.toIso8601String(),
    );
  }
}
