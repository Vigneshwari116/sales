import 'package:sales/db/summary_db.dart';
import 'package:sales/models/sale_bill.dart';

/// Applies incremental updates to [SummaryDb] when bills change.
class SummaryUpdateService {
  static Future<void> onBillSaved({
    required SaleBill? previous,
    required SaleBill current,
  }) async {
    await SummaryDb.instance.initialize();

    if (previous != null) {
      await SummaryDb.instance.applyBillDelta(
        location: previous.location,
        billDate: previous.billDate,
        delta: -previous.grandTotal,
      );
    }

    await SummaryDb.instance.applyBillDelta(
      location: current.location,
      billDate: current.billDate,
      delta: current.grandTotal,
    );
  }

  static Future<void> onBillDeleted(SaleBill bill) async {
    await SummaryDb.instance.initialize();
    await SummaryDb.instance.applyBillDelta(
      location: bill.location,
      billDate: bill.billDate,
      delta: -bill.grandTotal,
    );
  }

  static Future<void> onPulledBill({
    required SaleBill? previous,
    required SaleBill current,
  }) async {
    if (previous != null) {
      await SummaryDb.instance.applyBillDelta(
        location: previous.location,
        billDate: previous.billDate,
        delta: -previous.grandTotal,
      );
    }

    await SummaryDb.instance.applyBillDelta(
      location: current.location,
      billDate: current.billDate,
      delta: current.grandTotal,
    );
  }

  static Future<void> onImportedBills(Iterable<SaleBill> bills) async {
    await SummaryDb.instance.initialize();
    for (final bill in bills) {
      await SummaryDb.instance.applyBillDelta(
        location: bill.location,
        billDate: bill.billDate,
        delta: bill.grandTotal,
      );
    }
  }
}
