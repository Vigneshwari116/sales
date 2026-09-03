// ignore_for_file: avoid_print
/// Screenshot harness for location branding and reset flow.
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
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/admin_location_grid_screen.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/staff_sales_dashboard_screen.dart';
import 'package:sales/services/bill_print_service.dart';
import 'package:sales/services/receipt_service.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/documents';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  const shotDir = '/opt/cursor/artifacts/screenshots';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('branding_reset_shots_');
    await Directory('${tempDir.path}/documents').create(recursive: true);
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

  testWidgets('screenshot staff dashboard branding', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      const StaffSalesDashboardScreen(location: 'Win1'),
    );
    await _waitForLoadingToFinish(tester);

    expect(find.text('R K S ENTERPRISES'), findsOneWidget);
    expect(find.text('Win1 - Bommasandra'), findsOneWidget);

    await _savePng(tester, '$shotDir/branding_staff_dashboard_win1.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot admin location grid branding', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(tester, const AdminLocationGridScreen());
    await _waitForLoadingToFinish(tester);

    expect(find.text('R K S ENTERPRISES'), findsWidgets);
    expect(find.text('Win1 - Bommasandra'), findsOneWidget);

    await _savePng(tester, '$shotDir/branding_admin_location_grid.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot staff sync panel with reset button', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('SYNC')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('staff_sync_now_button'),
                        onPressed: () {},
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('SYNC NOW'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('staff_reset_button'),
                        onPressed: () {},
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('RESET'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('staff_reset_button')), findsOneWidget);

    await _savePng(tester, '$shotDir/branding_staff_sync_reset_button.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot reset password and confirmation dialogs',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await SyncGateService.confirmReset(context);
                },
                child: const Text('Open reset flow'),
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Open reset flow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _savePng(tester, '$shotDir/reset_flow_password_dialog.png');

    await tester.enterText(find.byType(TextField), 'RKS');
    await tester.tap(find.text('CONTINUE'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await _savePng(tester, '$shotDir/reset_flow_confirmation_dialog.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('screenshot offline queued reset success message', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpThemed(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text('SYNC')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Local sales data cleared. Server reset queued for next sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _savePng(tester, '$shotDir/reset_offline_queued_message.png');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('receipt shows branch name and full totals', () async {
    final item = BillItem(qty: 45, rate: 23);
    final bill = SaleBill(
      billNo: 1,
      location: 'Win1',
      billDate: DateTime(2026, 9, 3),
      paymentMode: 'CASH',
      customerName: 'CASH',
      mobile: '',
      items: [item],
      totalQty: 45,
      totalAmount: item.amount,
      totalCgst: item.cgst,
      totalSgst: item.sgst,
      totalIgst: 0,
      grandTotal: item.netAmt,
    );

    final text = ReceiptService.buildReceiptText(bill);
    final textPath = '$shotDir/receipt_full_text_sample.txt';
    await File(textPath).writeAsString(text);

    final pdfPath = await BillPrintService.saveReceiptPdfToDesktop(bill);
    final pdfFile = File(pdfPath);
    expect(pdfFile.existsSync(), isTrue);
    await pdfFile.copy('$shotDir/receipt_full_bill_sample.pdf');

    expect(text, contains('R K S ENTERPRISES'));
    expect(text, contains('Win1 - Bommasandra'));
    expect(text, contains('SUBTOTAL'));
    expect(text, contains('GRAND TOTAL'));
    expect(text, contains('THANK YOU VISIT AGAIN'));
    print('Wrote $textPath and $pdfPath');
  });
}
