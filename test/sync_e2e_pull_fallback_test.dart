import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/sync_service.dart';

import 'test_guards.dart';

/// Sync pull-fallback coverage using [MockClient] only.
///
/// IMPORTANT: This file must never call the live VPS. Production rows such as
/// "E2E Sync Customer" / "SyncProbe" were created by ad-hoc curl probes during
/// debugging — not by this test. The production-network guard below will throw
/// if a request ever escapes to the real host.

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String root;

  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _locationCode = 'win3';
const _locationName = 'Win3';

SaleBill _bill(int billNo, {String customer = 'Sync Integration Customer'}) {
  final items = [
    BillItem(qty: 1, rate: 55, cgstPct: 2.5, sgstPct: 2.5),
  ];
  return SaleBill(
    billNo: billNo,
    location: _locationName,
    billDate: DateTime(2026, 9, 1),
    paymentMode: 'CASH',
    customerName: customer,
    mobile: '9000000003',
    items: items,
    totalQty: 1,
    totalAmount: items.first.amount,
    totalCgst: items.first.cgst,
    totalSgst: items.first.sgst,
    totalIgst: 0,
    grandTotal: items.first.netAmt,
  );
}

Map<String, dynamic> _billJson(SaleBill bill) => bill.toJson();

/// Simulates the live VPS bug: /api/bills/updates-since is handled by :billNo.
http.Client _vpsCollisionClient({
  required List<SaleBill> serverBills,
  List<Map<String, dynamic>>? postedBodies,
}) {
  return MockClient((request) async {
    final path = request.url.path;

    if (request.method == 'POST' && path == '/api/bills') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      postedBodies?.add(body);
      return http.Response(
        jsonEncode({'ok': true, 'billNo': body['billNo']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/sync/bill-updates') {
      // Old VPS does not have this route.
      return http.Response(
        jsonEncode({'ok': false, 'error': 'Not found'}),
        404,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/bills/updates-since') {
      // Collision with /api/bills/:billNo where billNo = "updates-since".
      return http.Response(
        jsonEncode({'ok': false, 'error': 'Invalid bill number'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/ledger') {
      final entries = serverBills
          .map(
            (bill) => {
              'billNo': bill.billNo,
              'date': bill.billDate.toIso8601String().substring(0, 10),
              'paymentMode': bill.paymentMode,
              'total': bill.totalAmount,
              'cgst': bill.totalCgst,
              'sgst': bill.totalSgst,
              'igst': bill.totalIgst,
              'grandTotal': bill.grandTotal,
            },
          )
          .toList();
      return http.Response(
        jsonEncode({
          'ok': true,
          'entries': entries,
          'summary': {
            'total': 0,
            'cgst': 0,
            'sgst': 0,
            'igst': 0,
            'grandTotal': 0,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final billMatch = RegExp(r'^/api/bills/(\d+)$').firstMatch(path);
    if (billMatch != null) {
      final billNo = int.parse(billMatch.group(1)!);
      final bill = serverBills.cast<SaleBill?>().firstWhere(
            (b) => b!.billNo == billNo,
            orElse: () => null,
          );
      if (bill == null) {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'Bill not found'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'ok': true, 'bill': _billJson(bill)}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path == '/api/gst/sync') {
      return http.Response(
        jsonEncode({
          'ok': true,
          'db_name': 'win3_gst',
          'version': '1',
          'data': [
            {'key': 'cgst_pct', 'value': '2.5'},
            {'key': 'sgst_pct', 'value': '2.5'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.Response(
      jsonEncode({'ok': false, 'error': 'Unhandled ${request.method} $path'}),
      500,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<void> _deleteTestDb() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/${_locationCode}_sales.db');
  if (await file.exists()) {
    await file.delete();
  }
}

void main() {
  late Directory tempDir;

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    enableProductionNetworkGuard();
    tempDir =
        await Directory.systemTemp.createTemp('sync_e2e_invalid_billno_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() async {
    disableProductionNetworkGuard();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await AppConfig.setLocation(_locationCode);
    await LocalDb.resetForTesting();
    await SyncService.resetForTesting();
    SalesApi.resetClientOverride();
    await _deleteTestDb();
  });

  tearDown(() async {
    SalesApi.resetClientOverride();
    await SyncService.resetForTesting();
    await LocalDb.resetForTesting();
    await _deleteTestDb();
    await AppConfig.clearLocation();
  });

  test(
    'getBillUpdatesSince recovers when updates-since returns Invalid bill number',
    () async {
      final serverBill = _bill(42, customer: 'From Server');
      SalesApi.clientOverride = _vpsCollisionClient(serverBills: [serverBill]);

      final result = await SalesApi.getBillUpdatesSince(
        location: _locationName,
        since: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(result.data!.bills, hasLength(1));
      expect(result.data!.bills.first.customerName, 'From Server');
    },
  );

  test(
    'manualSync pushes a saved pending bill then pulls without Invalid bill number',
    () async {
      final db = LocalDb.instance;
      await db.initialize();

      final pending = _bill(77);
      await db.insertBill(pending, syncStatus: 'pending');

      final posted = <Map<String, dynamic>>[];
      final serverBills = <SaleBill>[pending];
      SalesApi.clientOverride = _vpsCollisionClient(
        serverBills: serverBills,
        postedBodies: posted,
      );

      final sync = SyncService.instance;
      sync.isOnlineOverride = () async => true;

      final result = await sync.manualSync(_locationName);

      expect(
        result.summaryMessage.toLowerCase(),
        isNot(contains('invalid bill number')),
        reason: result.summaryMessage,
      );
      expect(result.pushedCount, 1);
      expect(result.pushFailedCount, 0);
      expect(result.ok, isTrue, reason: result.summaryMessage);
      expect(posted, hasLength(1));
      expect(posted.first['billNo'], 77);

      final stillPending = await db.getBillsBySyncStatus(
        'pending',
        location: _locationName,
      );
      expect(stillPending, isEmpty);
    },
  );
}
