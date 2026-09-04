import 'package:sales/api/sales_api.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/local_db.dart' as db;
import 'package:sales/db/location_database.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/location_seed_service.dart';
import 'package:sales/services/sync_service.dart';

class LocalLedgerEntry {
  final String localId;
  final int billNo;
  final String date;
  final String customerName;
  final String mobile;
  final String paymentMode;
  final double total;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;
  final String syncStatus;

  LocalLedgerEntry({
    required this.localId,
    required this.billNo,
    required this.date,
    required this.customerName,
    required this.mobile,
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
      final locationCode = locationCodeFromDisplayName(location);
      await LocationSeedService.ensureLocationSeeded(locationCode);
      final rows = await LocationDatabase.getLedgerEntries(
        location: location,
        from: from,
        to: to,
      );

      final entries = rows
          .map(
            (row) => LocalLedgerEntry(
              localId: row.localId,
              billNo: row.billNo,
              date: row.billDate,
              customerName: row.customerName,
              mobile: row.mobile,
              paymentMode: row.paymentMode,
              total: row.totalAmount,
              cgst: row.totalCgst,
              sgst: row.totalSgst,
              igst: row.totalIgst,
              grandTotal: row.grandTotal,
              syncStatus: row.syncStatus,
            ),
          )
          .toList(growable: false);

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

  static Future<SaleBill?> getBillByLocalId(String localId) async {
    return db.LocalDb.instance.getBillByLocalId(localId);
  }

  static Future<void> softDeleteBill(String localId) async {
    await db.LocalDb.instance.markBillDeleted(localId);
  }

  static Future<void> refreshFromServer({required String location}) async {
    await SyncService.instance.pullAdminUpdates(location);
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
