import 'dart:async';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/services/location_seed_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    await LocalDb.instance.initialize();

    final role = await SessionService.getRole();
    if (role == SessionRole.admin) {
      unawaited(_seedAdminLocationsInBackground());
      return;
    }

    unawaited(LocationSeedService.ensureLocationSeeded(AppConfig.locationCode));
    SyncService.instance.start(location: AppConfig.displayLocationName);
  }

  static Future<void> _seedAdminLocationsInBackground() async {
    try {
      await LocationSeedService.ensureAllLocationsSeeded();
    } catch (_) {
      // Seeding must not block or crash login — data loads on next session.
    }
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    await LocalDb.instance.close();
  }
}
