import 'package:sales/db/local_db.dart';

/// Reads GST percentages from locally synced master data (admin-pushed).
class GstConfigService {
  static const double defaultCgstPct = 2.5;
  static const double defaultSgstPct = 2.5;

  static Future<double> cgstPct() async {
    final value = await LocalDb.instance.getGstMasterValue('cgst_pct');
    return double.tryParse(value ?? '') ?? defaultCgstPct;
  }

  static Future<double> sgstPct() async {
    final value = await LocalDb.instance.getGstMasterValue('sgst_pct');
    return double.tryParse(value ?? '') ?? defaultSgstPct;
  }
}
