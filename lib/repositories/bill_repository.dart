import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class BillRepository {
  static Future<int> getNextBillNumber(String location) async {
    return LocalDb.instance.getNextBillNumber(location);
  }

  static Future<SalesApiResult<int>> saveBill(
    SaleBill bill, {
    String? updateLocalId,
  }) async {
    final apiResult = await SalesApi.saveBill(bill);
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
