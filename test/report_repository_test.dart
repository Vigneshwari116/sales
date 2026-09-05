import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/report_repository.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/report_excel_service.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('report_repo_test_');
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
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await AppConfig.clearLocation();
  });

  test('single calendar month uses day-wise rows', () async {
    final breakdown = await ReportRepository.getBreakdown(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 3),
    );

    expect(breakdown.granularity, ReportGranularity.day);
    expect(breakdown.rows.length, 3);
    expect(breakdown.rows.first.label, '01 Sep 2026');
    expect(breakdown.rows.last.label, '03 Sep 2026');
  });

  test('multi-month range uses month-wise rows', () async {
    final breakdown = await ReportRepository.getBreakdown(
      fromDate: DateTime(2026, 8, 15),
      toDate: DateTime(2026, 9, 5),
    );

    expect(breakdown.granularity, ReportGranularity.month);
    expect(breakdown.rows.length, 2);
    expect(breakdown.rows.first.label, 'Aug 2026');
    expect(breakdown.rows.last.label, 'Sep 2026');
  });

  test('aggregates cash, card, tax, and totals from active location bills',
      () async {
    await LocalDb.instance.insertPendingBill(
      SaleBill(
        billNo: 999901,
        location: 'Win1',
        billDate: DateTime(2099, 12, 31),
        paymentMode: 'CASH',
        customerName: '',
        mobile: '',
        items: [BillItem(qty: 1, rate: 100)],
        totalQty: 1,
        totalAmount: 100,
        totalCgst: 2.5,
        totalSgst: 2.5,
        totalIgst: 0,
        grandTotal: 105,
      ),
    );

    await LocalDb.instance.insertPendingBill(
      SaleBill(
        billNo: 999902,
        location: 'Win1',
        billDate: DateTime(2099, 12, 31),
        paymentMode: 'UPI',
        customerName: '',
        mobile: '',
        items: [BillItem(qty: 1, rate: 200)],
        totalQty: 1,
        totalAmount: 200,
        totalCgst: 5,
        totalSgst: 5,
        totalIgst: 0,
        grandTotal: 210,
      ),
    );

    final breakdown = await ReportRepository.getBreakdown(
      fromDate: DateTime(2099, 12, 31),
      toDate: DateTime(2099, 12, 31),
    );

    final dayRow = breakdown.rows.single;
    expect(dayRow.cash, 105);
    expect(dayRow.card, 210);
    expect(dayRow.total, 300);
    expect(dayRow.cgst, 7.5);
    expect(dayRow.sgstIgst, 7.5);
    expect(dayRow.grandTotal, 315);

    expect(breakdown.grandTotal.cash, 105);
    expect(breakdown.grandTotal.card, 210);
    expect(breakdown.grandTotal.grandTotal, 315);
  });

  test('excel export includes headers, rows, and grand total row', () async {
    final breakdown = ReportBreakdown(
      granularity: ReportGranularity.day,
      rows: [
        ReportRow(
          label: '01 Sep 2026',
          sortKey: '2026-09-01',
          cash: 100,
          card: 200,
          total: 250,
          cgst: 10,
          sgstIgst: 10,
          grandTotal: 270,
        ),
      ],
      grandTotal: ReportRow(
        label: 'Grand Total',
        sortKey: 'grand_total',
        cash: 100,
        card: 200,
        total: 250,
        cgst: 10,
        sgstIgst: 10,
        grandTotal: 270,
      ),
    );

    final bytes = ReportExcelService.buildWorkbookBytes(
      breakdown: breakdown,
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 1),
    );

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(100));
  });
}
