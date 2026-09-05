import 'dart:async';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/db/summary_db.dart';
import 'package:sales/services/location_seed_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    final role = await SessionService.getRole();

    if (role == SessionRole.summaryViewer) {
      try {
        await SummaryDb.instance.initialize();
      } catch (_) {
        // Summary-only login should still open the lightweight screens.
      }
      return;
    }

    if (role == SessionRole.admin) {
      unawaited(_initializeSummaryInBackground());
      return;
    }

    try {
      await LocalDb.instance.initialize();
      await LocationSeedService.ensureLocationSeeded(AppConfig.locationCode);
      await SummaryDb.instance.initialize();
      await SummaryDb.instance.ensureBootstrapped();
    } catch (_) {
      // Login must succeed even if the local database is temporarily unavailable.
    }

    SyncService.instance.start(location: AppConfig.displayLocationName);
  }

  static Future<void> _initializeSummaryInBackground() async {
    try {
      await SummaryDb.instance.initialize();
      await SummaryDb.instance.ensureBootstrapped();
    } catch (_) {
      // Summary totals are best-effort until bootstrap completes.
    }
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    try {
      await LocalDb.instance.close();
    } catch (_) {
      // Ignore close errors during logout.
    }
  }
}
