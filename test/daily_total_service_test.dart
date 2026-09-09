import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/services/daily_total_service.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

SaleBill _sampleBill({double grandTotal = 350}) {
  final items = [BillItem(qty: 1, rate: grandTotal)];

  return SaleBill(
    billNo: 12,
    location: 'Win1',
    billDate: DateTime(2026, 9, 8),
    paymentMode: 'CASH',
    customerName: '',
    mobile: '',
    items: items,
    totalQty: 1,
    totalAmount: items.first.amount,
    totalCgst: items.first.cgst,
    totalSgst: items.first.sgst,
    totalIgst: 0,
    grandTotal: grandTotal,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SalesApi.resetClientOverride();
    SharedPreferences.setMockInitialValues({});
  });

  test('pushBillDelta posts grand total for new bills', () async {
    var postedBody = <String, dynamic>{};

    SalesApi.clientOverride = MockClient((request) async {
      expect(request.url.path, '/api/daily-total');
      postedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'ok': true, 'amount': postedBody['amount']}),
        200,
      );
    });

    await DailyTotalService.pushBillDelta(current: _sampleBill());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(postedBody['location'], 'win1');
    expect(postedBody['date'], '2026-09-08');
    expect((postedBody['amount'] as num).toDouble(), 350);
  });

  test('pushBillDelta posts delta when bill is edited', () async {
    var postedAmount = 0.0;

    SalesApi.clientOverride = MockClient((request) async {
      postedAmount = (jsonDecode(request.body) as Map<String, dynamic>)['amount']
          .toDouble();
      return http.Response(jsonEncode({'ok': true, 'amount': postedAmount}), 200);
    });

    await DailyTotalService.pushBillDelta(
      previous: _sampleBill(grandTotal: 300),
      current: _sampleBill(grandTotal: 350),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(postedAmount, 50);
  });

  test('failed push is queued and flushed later', () async {
    var callCount = 0;

    SalesApi.clientOverride = MockClient((request) async {
      callCount++;
      if (callCount == 1) {
        return http.Response(jsonEncode({'ok': false, 'error': 'offline'}), 500);
      }
      return http.Response(jsonEncode({'ok': true, 'amount': 120}), 200);
    });

    await DailyTotalService.pushBillDelta(current: _sampleBill(grandTotal: 120));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(callCount, 1);

    await DailyTotalService.flushPending();
    expect(callCount, 2);
  });
}
