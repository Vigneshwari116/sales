import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/screen/admin_login_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

import 'credential_test_helpers.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _testLocationCode = 'win1';

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${_testLocationCode}_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('admin_login_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await SessionService.clearLogin();
    await AppConfig.clearLocation();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
    await seedTestCredentials();
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await SessionService.clearLogin();
    await AppConfig.clearLocation();
    await resetTestCredentials();
  });

  testWidgets('staff login screen has no ledger menu link', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Admin login'), findsOneWidget);
    expect(find.text('LEDGER'), findsNothing);
  });

  testWidgets('staff login rejects admin credentials', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'adminuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'adminpass1');
    await tester.tap(find.text('LOGIN'));
    await tester.pump();

    expect(find.text('Incorrect username or password.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('admin login rejects staff credentials', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'staffuser');
    await tester.enterText(find.byType(TextFormField).at(1), 'staffpass1');
    await tester.tap(find.text('ADMIN LOGIN'));
    await tester.pump();

    expect(find.text('Incorrect admin username or password.'), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  test('admin session role is persisted separately from staff', () async {
    await SessionService.saveLogin('admin', role: SessionRole.admin);
    expect(await SessionService.getRole(), SessionRole.admin);

    await SessionService.clearLogin();
    await SessionService.saveLogin('staff', role: SessionRole.staff);
    expect(await SessionService.getRole(), SessionRole.staff);
  });
}
