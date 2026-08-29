import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class BillRepository {
  static Future<int> getNextBillNumber(String location) async {
    return LocalDb.instance.getNextBillNumber(location);
  }

  static Future<SalesApiResult<int>> saveBill(SaleBill bill) async {
    var result = await SalesApi.saveBill(bill);

    if (result.ok) {
      try {
        await LocalDb.instance.insertSavedBill(bill, syncStatus: 'synced');
      } catch (_) {
        // Bill saved on server; local record is best-effort for numbering.
      }
      return result;
    }

    try {
      await LocalDb.instance.insertPendingBill(bill);
      return SalesApiResult.success(bill.billNo);
    } catch (_) {
      return SalesApiResult.failure('Could not save bill locally.');
    }
  }
}
