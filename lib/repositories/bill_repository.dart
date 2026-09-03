import 'package:flutter/foundation.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

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

    try {
      await LocalDb.instance.persistBill(
        bill,
        updateLocalId: updateLocalId,
        syncStatus: syncStatus,
      );
      return SalesApiResult.success(bill.billNo);
    } catch (_) {
      if (apiResult.ok) {
        return apiResult;
      }
      return SalesApiResult.failure('Could not save bill locally.');
    }
  }
}
