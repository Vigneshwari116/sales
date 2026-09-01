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
import 'package:sales/screen/login_screen.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

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

Future<void> _awaitLoginWork(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
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
    LoginScreen.resetTestHooks();
    await SessionService.clearLogin();
    await AppConfig.clearLocation();
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await _deleteTestDb();
    SyncService.instance.isOnlineOverride = () async => false;
  });

  tearDown(() async {
    LoginScreen.resetTestHooks();
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await SessionService.clearLogin();
    await AppConfig.clearLocation();
  });

  testWidgets('single login screen hides staff/admin path labels', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Admin login'), findsNothing);
    expect(find.text('Staff login'), findsNothing);
    expect(find.text('LEDGER'), findsNothing);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
    expect(find.byIcon(Icons.admin_panel_settings), findsNothing);
  });

  testWidgets('wrong credentials show generic error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'nobody');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('LOGIN'));
    await tester.pump();

    expect(find.text('Incorrect username or password.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('admin credentials route to admin home', (tester) async {
    LoginScreen.adminHomeBuilder = (_) => const Scaffold(
          key: Key('routed_admin_home'),
          body: Text('admin-home'),
        );

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'admin');
    await tester.enterText(find.byType(TextFormField).at(1), 'admin123');
    await tester.tap(find.text('LOGIN'));
    await _awaitLoginWork(tester);

    expect(find.byKey(const Key('routed_admin_home')), findsOneWidget);
    expect(await SessionService.getRole(), SessionRole.admin);
  });

  testWidgets('staff credentials route to staff home', (tester) async {
    LoginScreen.staffHomeBuilder = (_) => const Scaffold(
          key: Key('routed_staff_home'),
          body: Text('staff-home'),
        );

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'win1');
    await tester.enterText(find.byType(TextFormField).at(1), 'staff123');
    await tester.tap(find.text('LOGIN'));
    await _awaitLoginWork(tester);

    expect(find.byKey(const Key('routed_staff_home')), findsOneWidget);
    expect(await SessionService.getRole(), SessionRole.staff);
    expect(AppConfig.locationCode, 'win1');
  });

  test('admin session role is persisted separately from staff', () async {
    await SessionService.saveLogin('admin', role: SessionRole.admin);
    expect(await SessionService.getRole(), SessionRole.admin);

    await SessionService.clearLogin();
    await SessionService.saveLogin('win1', role: SessionRole.staff);
    expect(await SessionService.getRole(), SessionRole.staff);
  });
}
