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
import 'package:sales/screen/admin_cross_abstract_screen.dart';
import 'package:sales/screen/admin_location_grid_screen.dart';
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

Future<void> _waitForLoadingToFinish(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
}

Future<void> _pumpThemed(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('shot_root'),
      child: MaterialApp(
        theme: AppTheme.theme,
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pumpBillScreen(WidgetTester tester) async {
  await _pumpThemed(
    tester,
    SalesBillScreen(
      embeddedInDashboard: true,
      initialBillNo: 3,
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    if (find.text('BILL NO:').evaluate().isNotEmpty) {
      break;
    }
  }
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

  testWidgets('screenshot staff sales abstract', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      const SalesAbstractScreen(location: 'Win1'),
    );
    await _waitForLoadingToFinish(tester);

    expect(find.text('SALES ABSTRACT'), findsOneWidget);
    expect(find.text('SHOW ALL HISTORY'), findsNothing);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_staff_sales_abstract.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot admin cross abstract', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(tester, const AdminCrossAbstractScreen());
    await _waitForLoadingToFinish(tester);

    expect(find.text('SALES ABSTRACT'), findsOneWidget);
    expect(find.text('SHOW ALL HISTORY'), findsNothing);
    expect(find.byKey(const Key('admin_abstract_location')), findsOneWidget);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_admin_cross_abstract.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot admin dashboard location grid', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(tester, const AdminLocationGridScreen());
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      if (find.text('Win1').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('DASHBOARD'), findsOneWidget);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_admin_dashboard_grid.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot staff sync panel header', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      Scaffold(
        appBar: sectionHeaderAppBar('SYNC'),
        body: const Center(child: Text('Sync panel body')),
      ),
    );

    expect(find.text('SYNC'), findsOneWidget);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_staff_sync_header.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot admin sync header', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      Scaffold(
        appBar: sectionHeaderAppBar('SYNC'),
        body: const Center(child: Text('Sync panel body')),
      ),
    );

    expect(find.text('SYNC'), findsOneWidget);
    expect(find.text('SAVE GST CONFIG'), findsNothing);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_admin_sync_header.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot bill empty compact layout', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBillScreen(tester);

    expect(find.text('S.no'), findsNothing);
    expect(find.text('Grand Total'), findsNothing);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_bill_empty_compact.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot bill with line item and tax headers', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpBillScreen(tester);

    final rateField = find.byKey(const Key('bill_rate_field'));
    final qtyField = find.byKey(const Key('bill_qty_field'));

    await tester.tap(rateField);
    await tester.enterText(rateField, '16000');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    await tester.enterText(qtyField, '2.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('CGST %'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Grand Total'), findsOneWidget);

    await _savePng(
      tester,
      '/opt/cursor/artifacts/screenshots/pr20_bill_with_item_compact.png',
    );
    await tester.pumpWidget(const SizedBox.shrink());
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
                appBar: sectionHeaderAppBar('SALES ABSTRACT'),
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
}
