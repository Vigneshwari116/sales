import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/local_credentials.dart';
import 'package:sales/db/summary_db.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('summary_db_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await SummaryDb.resetForTesting();
  });

  tearDown(() async {
    await SummaryDb.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('applyBillDelta increments day and month totals', () async {
    final db = SummaryDb.instance;
    await db.initialize();

    await db.applyBillDelta(
      location: 'Win1',
      billDate: DateTime(2026, 9, 5),
      delta: 1000,
    );
    await db.applyBillDelta(
      location: 'Win1',
      billDate: DateTime(2026, 9, 5),
      delta: 500,
    );

    expect(
      await db.getTotalForDay(day: '2026-09-05', location: 'Win1'),
      1500,
    );

    final months = await db.getMonthTotalsForYear(year: 2026, location: 'Win1');
    expect(months.single.month, 9);
    expect(months.single.totalAmount, 1500);
  });

  test('applyBillDelta can subtract on edit/delete', () async {
    final db = SummaryDb.instance;
    await db.initialize();

    await db.applyBillDelta(
      location: 'Win2',
      billDate: DateTime(2026, 8, 1),
      delta: 800,
    );
    await db.applyBillDelta(
      location: 'Win2',
      billDate: DateTime(2026, 8, 1),
      delta: -300,
    );

    expect(
      await db.getTotalForDay(day: '2026-08-01', location: 'Win2'),
      500,
    );
  });

  test('summary viewer credentials are accepted', () {
    expect(verifySummaryViewerLogin('RKSM', 'rksm'), isTrue);
    expect(verifySummaryViewerLogin('rksm', 'rksm'), isTrue);
    expect(verifySummaryViewerLogin('RKSM', 'wrong'), isFalse);
    expect(verifySummaryViewerLogin('admin', 'admin123'), isFalse);
  });
}
