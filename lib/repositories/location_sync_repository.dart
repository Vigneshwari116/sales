import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart';

/// Reads per-location last successful pull/sync timestamps for admin dashboard.
class LocationSyncRepository {
  static Future<DateTime?> getLastSyncedAtForLocationCode(
    String locationCode,
  ) async {
    final locationName = displayNameForLocationCode(locationCode);

    if (AppConfig.isLocationSet) {
      try {
        await LocalDb.instance.initialize();
        final fromActiveDb =
            await LocalDb.instance.getLastPullAt(locationName);
        if (fromActiveDb != null) {
          return fromActiveDb;
        }
      } catch (_) {
        // Fall through to per-location file read.
      }
    }

    return _readLastPullFromLocationFile(
      locationCode: locationCode,
      locationName: locationName,
    );
  }

  static Future<DateTime?> _readLastPullFromLocationFile({
    required String locationCode,
    required String locationName,
  }) async {
    final supportDir = await getApplicationSupportDirectory();
    final path = join(supportDir.path, '${locationCode}_sales.db');
    if (!await File(path).exists()) {
      return null;
    }

    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );

    try {
      final rows = await db.query(
        'location_meta',
        columns: ['last_pull_at'],
        where: 'location = ?',
        whereArgs: [locationName],
        limit: 1,
      );

      if (rows.isEmpty) {
        return null;
      }

      final raw = rows.first['last_pull_at'] as String?;
      if (raw == null || raw.isEmpty) {
        return null;
      }

      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    } finally {
      await db.close();
    }
  }
}
