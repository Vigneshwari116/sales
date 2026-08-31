import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/services/auto_sync_service.dart';
import 'package:sales/services/owner_delete_service.dart';
import 'package:sales/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    await LocalDb.instance.initialize();
    SyncService.instance.start(location: AppConfig.displayLocationName);
    AutoSyncService.instance.start();
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    AutoSyncService.instance.stop();
    OwnerDeleteService.instance.disable();
    await LocalDb.instance.close();
  }
}
