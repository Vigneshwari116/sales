import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/repositories/daily_total_repository.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    SalesApi.resetClientOverride();
  });

  test('fetchLiveTotals maps server codes to display names', () async {
    SalesApi.clientOverride = MockClient((request) async {
      expect(request.url.path, '/api/daily-totals');
      return http.Response(
        jsonEncode({
          'ok': true,
          'date': '2026-09-08',
          'totals': {'win1': 100, 'win2': 200, 'win3': 50},
        }),
        200,
      );
    });

    final totals = await DailyTotalRepository.fetchLiveTotals(
      date: DateTime(2026, 9, 8),
    );

    expect(totals, isNotNull);
    expect(totals![displayNameForLocationCode('win1')], 100);
    expect(totals![displayNameForLocationCode('win2')], 200);
    expect(totals![displayNameForLocationCode('win3')], 50);
  });

  test('fetchLiveTotals returns null when server is unreachable', () async {
    SalesApi.clientOverride = MockClient((request) async {
      throw const http.ClientException('offline');
    });

    final totals = await DailyTotalRepository.fetchLiveTotals();
    expect(totals, isNull);
  });
}
