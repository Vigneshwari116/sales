import 'dart:convert';

import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/services/sync_service.dart';

class LocalLedgerEntry {
  final int billNo;
  final String date;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;
  final String syncStatus;

  LocalLedgerEntry({
    required this.billNo,
    required this.date,
    required this.paymentMode,
    required this.total,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
    required this.syncStatus,
  });
}

class LedgerRepository {
  static Future<
      ({List<LocalLedgerEntry> entries, LedgerSummary summary})> getLedger({
    required String location,
    String? from,
    String? to,
  }) async {
    try {
      var rows =
          await LocalDb.instance.getBillsForLedger(location: location);
      var entries = <LocalLedgerEntry>[];

      for (var row in rows) {
        var entry = _entryFromRow(row);
        if (entry == null) {
          continue;
        }

        if (!_isWithinDateRange(entry.date, from: from, to: to)) {
          continue;
        }

        entries.add(entry);
      }

      entries.sort((a, b) => b.billNo.compareTo(a.billNo));

      return (
        entries: entries,
        summary: _buildSummary(entries),
      );
    } catch (_) {
      return (
        entries: <LocalLedgerEntry>[],
        summary: LedgerSummary(
          total: 0,
          cgst: 0,
          sgst: 0,
          igst: 0,
          grandTotal: 0,
        ),
      );
    }
  }

  static Future<void> syncWithServer({required String location}) async {
    await SyncService.instance.pushPendingBills();

    var result = await SalesApi.getLedger(location: location);

    if (result.ok && result.data != null) {
      await LocalDb.instance.mergeLedgerFromServer(
        location: location,
        entries: result.data!.entries
            .map(
              (entry) => (
                billNo: entry.billNo,
                date: entry.date,
                paymentMode: entry.paymentMode,
                total: entry.total,
                cgst: entry.cgst,
                sgst: entry.sgst,
                igst: entry.igst,
                grandTotal: entry.grandTotal,
              ),
            )
            .toList(),
      );
    }
  }

  static LocalLedgerEntry? _entryFromRow(Map<String, dynamic> row) {
    try {
      var payloadRaw = row['payload'] as String?;
      if (payloadRaw == null || payloadRaw.isEmpty) {
        return null;
      }

      var payload = jsonDecode(payloadRaw) as Map<String, dynamic>;

      return LocalLedgerEntry(
        billNo: (row['bill_no'] as num).toInt(),
        date: payload['billDate'] as String? ?? '',
        paymentMode: payload['paymentMode'] as String? ?? 'CASH',
        total: (payload['totalAmount'] as num?)?.toDouble() ?? 0,
        cgst: (payload['totalCgst'] as num?)?.toDouble() ?? 0,
        sgst: (payload['totalSgst'] as num?)?.toDouble() ?? 0,
        igst: (payload['totalIgst'] as num?)?.toDouble() ?? 0,
        grandTotal: (payload['grandTotal'] as num?)?.toDouble() ?? 0,
        syncStatus: row['sync_status'] as String? ?? 'pending',
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isWithinDateRange(
    String date, {
    String? from,
    String? to,
  }) {
    if (from == null && to == null) {
      return true;
    }

    try {
      var value = DateTime.parse(date);

      if (from != null) {
        var fromDate = DateTime.parse(from);
        if (value.isBefore(fromDate)) {
          return false;
        }
      }

      if (to != null) {
        var toDate = DateTime.parse(to);
        if (value.isAfter(toDate)) {
          return false;
        }
      }
    } catch (_) {
      return true;
    }

    return true;
  }

  static LedgerSummary _buildSummary(List<LocalLedgerEntry> entries) {
    var total = 0.0;
    var cgst = 0.0;
    var sgst = 0.0;
    var igst = 0.0;
    var grandTotal = 0.0;

    for (var entry in entries) {
      total += entry.total;
      cgst += entry.cgst;
      sgst += entry.sgst;
      igst += entry.igst;
      grandTotal += entry.grandTotal;
    }

    return LedgerSummary(
      total: total,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      grandTotal: grandTotal,
    );
  }
}
