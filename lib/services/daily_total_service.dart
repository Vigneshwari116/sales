import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';

/// Pushes incremental daily sale totals to the server for live dashboards.
class DailyTotalService {
  static const _pendingKey = 'pending_daily_total_pushes_v1';

  static Future<void> pushBillDelta({
    required SaleBill current,
    SaleBill? previous,
  }) async {
    final delta = previous == null
        ? current.grandTotal
        : current.grandTotal - previous.grandTotal;

    if (delta == 0) {
      return;
    }

    unawaited(
      _pushDelta(
        locationCode: locationCodeFromDisplayName(current.location),
        date: _formatDate(current.billDate),
        amount: delta,
      ),
    );
  }

  static Future<void> flushPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pendingKey) ?? const [];
    if (raw.isEmpty) {
      return;
    }

    final remaining = <String>[];

    for (final entry in raw) {
      try {
        final decoded = jsonDecode(entry) as Map<String, dynamic>;
        final locationCode = decoded['location'] as String? ?? '';
        final date = decoded['date'] as String? ?? '';
        final amount = (decoded['amount'] as num?)?.toDouble() ?? 0;

        if (locationCode.isEmpty || date.isEmpty || amount == 0) {
          continue;
        }

        final result = await SalesApi.incrementDailyTotal(
          locationCode: locationCode,
          date: date,
          amount: amount,
        );

        if (!result.ok) {
          remaining.add(entry);
        }
      } catch (_) {
        remaining.add(entry);
      }
    }

    await prefs.setStringList(_pendingKey, remaining);
  }

  static Future<void> _pushDelta({
    required String locationCode,
    required String date,
    required double amount,
  }) async {
    await flushPending();

    final result = await SalesApi.incrementDailyTotal(
      locationCode: locationCode,
      date: date,
      amount: amount,
    );

    if (!result.ok) {
      await _enqueuePending(
        locationCode: locationCode,
        date: date,
        amount: amount,
      );
    }
  }

  static Future<void> _enqueuePending({
    required String locationCode,
    required String date,
    required double amount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingKey) ?? <String>[];
    pending.add(
      jsonEncode({
        'location': locationCode,
        'date': date,
        'amount': amount,
      }),
    );
    await prefs.setStringList(_pendingKey, pending);
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
