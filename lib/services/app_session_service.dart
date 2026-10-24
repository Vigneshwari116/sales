import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    final role = await SessionService.getRole();

    if (role == SessionRole.admin) {
      return;
    }

    await LocalDb.instance.initialize();
    SyncService.instance.start(location: AppConfig.displayLocationName);
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    await LocalDb.instance.close();
  }
}
