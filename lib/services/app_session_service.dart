import 'package:sales/db/local_db.dart';
import 'package:sales/services/auto_sync_service.dart';
import 'package:sales/services/sync_service.dart';

class AppSessionService {
  static Future<void> onLoginComplete() async {
    await LocalDb.instance.initialize();
    SyncService.instance.start();
    AutoSyncService.instance.start();
  }

  static Future<void> onLogout() async {
    SyncService.instance.stop();
    AutoSyncService.instance.stop();
    await LocalDb.instance.close();
  }
}
