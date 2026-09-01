import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
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

  /// Optional HTTP client for tests. Production uses the default client.
  @visibleForTesting
  static http.Client? clientOverride;

  /// When true, any request to the baked-in production host is refused unless
  /// [clientOverride] is set. Enable in Flutter tests so a missing mock can
  /// never hit the live VPS.
  @visibleForTesting
  static bool forbidProductionHost = false;

  static http.Client get _client {
    if (clientOverride != null) {
      return clientOverride!;
    }
    if (forbidProductionHost) {
      return _ProductionBlockedClient();
    }
    return http.Client();
  }

  @visibleForTesting
  static void resetClientOverride() {
    clientOverride = null;
  }

  static Future<SalesApiResult<int>> getNextBillNumber(String location) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/bills/next-number').replace(
      queryParameters: {'location': location},
    );

    try {
      final res = await _client.get(uri).timeout(_timeout);
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
      final res = await _client.get(uri).timeout(_timeout);
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
      final res = await _client.get(uri).timeout(_timeout);
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
    final primary = await _fetchBillUpdatesFromPath(
      path: '/api/sync/bill-updates',
      location: location,
      since: since,
    );
    if (primary.ok) {
      return primary;
    }

    final legacy = await _fetchBillUpdatesFromPath(
      path: '/api/bills/updates-since',
      location: location,
      since: since,
    );
    if (legacy.ok) {
      return legacy;
    }

    // Live VPS may still route /api/bills/updates-since onto :billNo and
    // return "Invalid bill number". Fall back to ledger + per-bill GET.
    final legacyError = legacy.error ?? primary.error ?? '';
    if (_isUpdatesRouteCollision(legacyError) ||
        _isUpdatesRouteCollision(primary.error ?? '')) {
      return _pullAllBillsViaLedger(location: location);
    }

    return SalesApiResult.failure(
      legacy.error ?? primary.error ?? 'Could not load bill updates',
    );
  }

  static bool _isUpdatesRouteCollision(String error) {
    final lower = error.toLowerCase();
    return lower.contains('invalid bill number') ||
        lower.contains('bill not found') ||
        lower.contains('could not load bill updates');
  }

  static Future<
      SalesApiResult<({List<SaleBill> bills, DateTime serverTime})>>
      _fetchBillUpdatesFromPath({
    required String path,
    required String location,
    required DateTime since,
  }) async {
    final uri = Uri.parse('$salesBillApiBaseUrl$path').replace(
      queryParameters: {
        'location': location,
        'since': since.toUtc().toIso8601String(),
      },
    );

    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode == 404) {
        return SalesApiResult.failure('Could not load bill updates');
      }

      late final Map<String, dynamic> body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        return SalesApiResult.failure('Could not load bill updates');
      }

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

  /// Full pull using endpoints that exist on older VPS builds.
  static Future<
      SalesApiResult<({List<SaleBill> bills, DateTime serverTime})>>
      _pullAllBillsViaLedger({required String location}) async {
    final ledgerResult = await getLedger(location: location);
    if (!ledgerResult.ok || ledgerResult.data == null) {
      return SalesApiResult.failure(
        ledgerResult.error ?? 'Could not load ledger for sync pull',
      );
    }

    final bills = <SaleBill>[];
    for (final entry in ledgerResult.data!.entries) {
      final billResult = await getBill(
        billNo: entry.billNo,
        location: location,
      );
      if (billResult.ok && billResult.data != null) {
        bills.add(billResult.data!);
      }
    }

    return SalesApiResult.success((
      bills: bills,
      serverTime: DateTime.now().toUtc(),
    ));
  }

  static Future<SalesApiResult<int>> saveBill(SaleBill bill) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/bills');

    try {
      final res = await _client
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
      final res = await _client.get(uri).timeout(_timeout);
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
      String locationCode) async {
    final uri =
        Uri.parse('$salesBillApiBaseUrl/api/gst/sync').replace(
      queryParameters: {'location': locationCode},
    );

    try {
      final res = await _client.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode != 200 || body['ok'] != true) {
        return SalesApiResult.failure(
          body['error'] as String? ?? 'Could not sync GST data',
        );
      }

      final dbName = body['db_name'] as String? ?? '';
      final expected = '${locationCode}_gst';

      if (dbName != expected) {
        developer.log(
          'GST sync rejected: server db_name "$dbName" does not match '
          'expected "$expected" for location $locationCode',
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
        location: locationCode,
        expectedDbName: expected,
        lastGstVersion: version,
      );

      return SalesApiResult.success(version);
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  static Future<SalesApiResult<void>> updateGstConfig({
    required String locationCode,
    required double cgstPct,
    required double sgstPct,
  }) async {
    final uri = Uri.parse('$salesBillApiBaseUrl/api/gst/config');

    try {
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'location': locationCode,
              'cgstPct': cgstPct,
              'sgstPct': sgstPct,
            }),
          )
          .timeout(_timeout);

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode != 200 || body['ok'] != true) {
        return SalesApiResult.failure(
          body['error'] as String? ?? 'Could not save GST config',
        );
      }

      return SalesApiResult.success(null);
    } catch (_) {
      return SalesApiResult.failure('Could not reach the server.');
    }
  }

  /// Returns true when [serverDbName] matches this build's expected GST DB.
  static bool isGstDbNameValid(String serverDbName) {
    return serverDbName == AppConfig.expectedGstDbName;
  }
}

/// Blocks accidental live VPS calls from Flutter tests.
class _ProductionBlockedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final host = request.url.host;
    final productionHost = Uri.parse(salesBillApiBaseUrl).host;
    if (host == productionHost || host == '187.127.180.135') {
      throw StateError(
        'Refusing live API call to $host during tests. '
        'Set SalesApi.clientOverride to a MockClient instead.',
      );
    }
    return http.Client().send(request);
  }
}
