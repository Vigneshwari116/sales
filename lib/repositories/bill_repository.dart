import 'package:flutter/foundation.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/summary_update_service.dart';

class BillRepository {
  /// When set (tests only), replaces [SalesApi.saveBill] for faster, offline saves.
  @visibleForTesting
  static Future<SalesApiResult<int>> Function(SaleBill bill)?
      saveBillApiOverride;

  static Future<int> getNextBillNumber(String location) async {
    return LocalDb.instance.getNextBillNumber(location);
  }

  static Future<SalesApiResult<int>> saveBill(
    SaleBill bill, {
    String? updateLocalId,
  }) async {
    final saveApi = saveBillApiOverride ?? SalesApi.saveBill;
    final apiResult = await saveApi(bill);
    final syncStatus = apiResult.ok ? 'synced' : 'pending';

    SaleBill? previous;
    try {
      if (updateLocalId != null) {
        previous = await LocalDb.instance.getBillByLocalId(updateLocalId);
      } else {
        final existingId = await LocalDb.instance.findLocalIdByBillNo(
          location: bill.location,
          billNo: bill.billNo,
        );
        if (existingId != null) {
          previous = await LocalDb.instance.getBillByLocalId(existingId);
        }
      }

      await LocalDb.instance.persistBill(
        bill,
        updateLocalId: updateLocalId,
        syncStatus: syncStatus,
      );

      await SummaryUpdateService.onBillSaved(previous: previous, current: bill);
      return SalesApiResult.success(bill.billNo);
    } catch (_) {
      if (apiResult.ok) {
        return apiResult;
      }
      return SalesApiResult.failure('Could not save bill locally.');
    }
  }
}
