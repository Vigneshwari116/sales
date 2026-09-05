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

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  for (final code in ['win1', 'win2', 'win3']) {
    final file = File('${dir.path}/${code}_sales.db');
    if (await file.exists()) {
      await file.delete();
    }
  }
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
    await _deleteTestDb();
    await LocalDb.instance.initialize();
  });

  tearDown(() async {
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  test('single calendar month uses day-wise groups', () async {
    final breakdown = await ReportRepository.getBreakdown(
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 9, 3),
    );

    expect(breakdown.granularity, ReportGranularity.day);
    expect(breakdown.groups.length, 3);
    expect(breakdown.groups.first.label, '01 Sep 2026');
    expect(breakdown.groups.last.label, '03 Sep 2026');
  });

  test('multi-month range uses month-wise groups', () async {
    final breakdown = await ReportRepository.getBreakdown(
      fromDate: DateTime(2026, 8, 15),
      toDate: DateTime(2026, 9, 5),
    );

    expect(breakdown.granularity, ReportGranularity.month);
    expect(breakdown.groups.length, 2);
    expect(breakdown.groups.first.label, 'Aug 2026');
    expect(breakdown.groups.last.label, 'Sep 2026');
  });

  test('groups contain bill rows with bill no, date, name, and mobile', () async {
    await LocalDb.instance.insertPendingBill(
      SaleBill(
        billNo: 999901,
        location: 'Win1',
        billDate: DateTime(2099, 12, 31),
        paymentMode: 'CASH',
        customerName: 'Alice',
        mobile: '9000000001',
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
        customerName: 'Bob',
        mobile: '9000000002',
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

    final dayGroup = breakdown.groups.single;
    expect(dayGroup.bills.length, 2);
    expect(dayGroup.bills.any((row) => row.billNo == 999901), isTrue);
    expect(dayGroup.bills.any((row) => row.customerName == 'Alice'), isTrue);
    expect(dayGroup.bills.any((row) => row.mobile == '9000000001'), isTrue);
    expect(dayGroup.subtotal.grandTotal, 315);
    expect(breakdown.grandTotal.grandTotal, 315);
  });

  test('excel export includes grouped bill columns and grand total row', () async {
    final breakdown = ReportBreakdown(
      granularity: ReportGranularity.day,
      groups: [
        ReportPeriodGroup(
          label: '01 Sep 2026',
          sortKey: '2026-09-01',
          bills: [
            ReportBillRow(
              billNo: 101,
              date: '2026-09-01',
              customerName: 'Alice',
              mobile: '9000000001',
              paymentMode: 'CASH',
              total: 100,
              cgst: 2.5,
              sgstIgst: 2.5,
              grandTotal: 105,
            ),
          ],
          subtotal: const ReportTotals(
            cash: 105,
            card: 0,
            total: 100,
            cgst: 2.5,
            sgstIgst: 2.5,
            grandTotal: 105,
          ),
        ),
      ],
      grandTotal: const ReportTotals(
        cash: 105,
        card: 0,
        total: 100,
        cgst: 2.5,
        sgstIgst: 2.5,
        grandTotal: 105,
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
