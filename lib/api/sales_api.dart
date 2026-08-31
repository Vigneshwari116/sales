import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:sales/api/api%20config.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class LedgerEntry {
  final int billNo;
  final String date;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;

  LedgerEntry({
    required this.billNo,
    required this.date,
    required this.paymentMode,
    required this.total,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      billNo: (json['billNo'] as num).toInt(),
      date: json['date'] as String,
      paymentMode: json['paymentMode'] as String? ?? 'CASH',
      total: (json['total'] as num).toDouble(),
      cgst: (json['cgst'] as num).toDouble(),
      sgst: (json['sgst'] as num).toDouble(),
      igst: (json['igst'] as num).toDouble(),
      grandTotal: (json['grandTotal'] as num).toDouble(),
    );
  }
}

class LedgerSummary {
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;

  LedgerSummary({
    required this.total,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
  });

  factory LedgerSummary.fromJson(Map<String, dynamic> json) {
    return LedgerSummary(
      total: (json['total'] as num).toDouble(),
      cgst: (json['cgst'] as num).toDouble(),
      sgst: (json['sgst'] as num).toDouble(),
      igst: (json['igst'] as num).toDouble(),
      grandTotal: (json['grandTotal'] as num).toDouble(),
    );
  }
}

class SalesApiResult<T> {
  final bool ok;
  final T? data;
  final String? error;

  SalesApiResult.success(this.data) : ok = true, error = null;
  SalesApiResult.failure(this.error) : ok = false, data = null;
}

class SalesApi {
  static const Duration _timeout = Duration(seconds: 12);

  static Future<SalesApiResult<int>> getNextBillNumber(String location) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/bills/next-number').replace(
      queryParameters: {'location': location},
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        return SalesApiResult.success((body['billNo'] as num).toInt());
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'Could not load bill number',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<SalesApiResult<SaleBill>> getBill({
    required int billNo,
    required String location,
  }) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/bills/$billNo').replace(
      queryParameters: {'location': location},
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        return SalesApiResult.success(
          SaleBill.fromJson(body['bill'] as Map<String, dynamic>),
        );
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'Bill not found',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<SalesApiResult<SaleBill>> getPreviousBill({
    required int billNo,
    required String location,
  }) async {
    final uri =
        Uri.parse('$salesBillApiBaseUrl/api/bills/by-number/previous').replace(
      queryParameters: {
        'billNo': '$billNo',
        'location': location,
      },
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        return SalesApiResult.success(
          SaleBill.fromJson(body['bill'] as Map<String, dynamic>),
        );
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'No previous bill found',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<
      SalesApiResult<({List<SaleBill> bills, DateTime serverTime})>>
      getBillUpdatesSince({
    required String location,
    required DateTime since,
  }) async {
    final uri =
        Uri.parse('$salesBillApiBaseUrl/api/bills/updates-since').replace(
      queryParameters: {
        'location': location,
        'since': since.toUtc().toIso8601String(),
      },
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        final billsJson = body['bills'] as List<dynamic>? ?? [];
        final bills = billsJson
            .map((entry) => SaleBill.fromJson(entry as Map<String, dynamic>))
            .toList(growable: false);
        final serverTimeRaw = body['serverTime'] as String?;
        final serverTime = serverTimeRaw != null
            ? DateTime.tryParse(serverTimeRaw)?.toUtc() ??
                DateTime.now().toUtc()
            : DateTime.now().toUtc();

        return SalesApiResult.success((bills: bills, serverTime: serverTime));
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'Could not load bill updates',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<SalesApiResult<int>> saveBill(SaleBill bill) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/bills');

    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(bill.toJson()),
          )
          .timeout(_timeout);

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        return SalesApiResult.success((body['billNo'] as num).toInt());
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'Failed to save bill',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<
      SalesApiResult<({List<LedgerEntry> entries, LedgerSummary summary})>>
      getLedger({
    required String location,
    String? from,
    String? to,
  }) async {
    final params = <String, String>{'location': location};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('$salesBillApiBaseUrl/api/ledger').replace(
      queryParameters: params,
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['ok'] == true) {
        final entries = (body['entries'] as List<dynamic>)
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList();
        final summary = LedgerSummary.fromJson(
          body['summary'] as Map<String, dynamic>,
        );
        return SalesApiResult.success((entries: entries, summary: summary));
      }

      return SalesApiResult.failure(
        body['error'] as String? ?? 'Could not load ledger',
      );
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<SalesApiResult<String>> pullGstMasterData(
      String location) async {
    final uri =
        Uri.parse('$salesBillApiBaseUrl/api/gst/sync').replace(
      queryParameters: {'location': location},
    );

    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode != 200 || body['ok'] != true) {
        return SalesApiResult.failure(
          body['error'] as String? ?? 'Could not sync GST data',
        );
      }

      final dbName = body['db_name'] as String? ?? '';
      final expected = AppConfig.expectedGstDbName;

      if (dbName != expected) {
        developer.log(
          'GST sync rejected: server db_name "$dbName" does not match '
          'expected "$expected" for build LOCATION_CODE=${AppConfig.locationCode}',
          name: 'SalesApi',
        );
        return SalesApiResult.failure('Sync rejected: database mismatch.');
      }

      final version = body['version'] as String? ?? '';
      final data = body['data'] as List<dynamic>? ?? [];
      final rows = data.map((entry) {
        final map = entry as Map<String, dynamic>;
        return {
          'key': map['key'] as String,
          'value': map['value'] as String,
        };
      }).toList();

      await LocalDb.instance.replaceGstMaster(rows);
      await LocalDb.instance.updateSyncMeta(
        location: location,
        expectedDbName: expected,
        lastGstVersion: version,
      );

      return SalesApiResult.success(version);
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  /// Returns true when [serverDbName] matches this build's expected GST DB.
  static bool isGstDbNameValid(String serverDbName) {
    return serverDbName == AppConfig.expectedGstDbName;
  }
}
