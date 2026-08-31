import 'package:flutter_test/flutter_test.dart';
import 'package:sales/services/sync_service.dart';

void main() {
  group('ManualPushResult', () {
    test('summaryMessage for successful sync', () {
      const result = ManualPushResult(ok: true, syncedCount: 12, failedCount: 0);
      expect(result.summaryMessage, '12 bills synced');
    });

    test('summaryMessage for single bill', () {
      const result = ManualPushResult(ok: true, syncedCount: 1, failedCount: 0);
      expect(result.summaryMessage, '1 bill synced');
    });

    test('summaryMessage when nothing pending', () {
      const result = ManualPushResult(ok: true, syncedCount: 0, failedCount: 0);
      expect(result.summaryMessage, 'No pending bills to sync');
    });

    test('summaryMessage for partial failure', () {
      const result = ManualPushResult(
        ok: false,
        syncedCount: 3,
        failedCount: 2,
        error: 'Some bills could not be synced',
      );
      expect(result.summaryMessage, '3 synced, 2 failed');
    });

    test('summaryMessage for offline', () {
      const result = ManualPushResult(
        ok: false,
        syncedCount: 0,
        failedCount: 0,
        error: 'No internet connection',
      );
      expect(result.summaryMessage, 'No internet connection');
    });
  });
}
