import 'package:sales/api/sales_api.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';

class BillRepository {
  static Future<SalesApiResult<int>> saveBill(SaleBill bill) async {
    var result = await SalesApi.saveBill(bill);

    if (result.ok) {
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
