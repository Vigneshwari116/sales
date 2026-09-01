// ignore_for_file: avoid_print
/// Screenshot harness for PR #20 UI refinements.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/screen/sales_abstract_screen.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_date_range_picker.dart';
import 'package:sales/widgets/compact_layout.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

Future<void> _savePng(WidgetTester tester, String path) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('shot_root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.25);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    print('Wrote $path (${file.lengthSync()} bytes)');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pr20_shots_');
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
    await AppConfig.setLocation('win1');
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    await LocalDb.instance.initialize();
    SyncService.instance.isOnlineOverride = () async => false;
  });

  tearDown(() async {
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  testWidgets('screenshot sales abstract header and compact cards', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot_root'),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: SalesAbstractScreen(
            location: 'Win1',
            refreshGeneration: 0,
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      if (find.text('TOTAL SALES').evaluate().isNotEmpty) {
        break;
      }
    }
    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_sales_abstract.png',
    );
  });

  testWidgets('screenshot compact date range popup', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot_root'),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showCompactDateRangePicker(
                        context,
                        fromDate: DateTime(2026, 9, 1),
                        toDate: DateTime(2026, 9, 1),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_date_range_popup.png',
    );
  });

  testWidgets('screenshot bill layout compact table and save bar', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot_root'),
        child: MaterialApp(
          theme: AppTheme.theme,
          home: SalesBillScreen(
            embeddedInDashboard: true,
            initialBillNo: 3,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_bill_layout.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
