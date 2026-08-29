import 'package:sales/config/app_config.dart';

/// Base URL for the Sales Bill API running on the VPS.
/// Matches the pattern used by the Shilpa/GRATE apps — a fixed URL baked
/// into the app, never typed in by staff.
const String salesBillApiBaseUrl = 'http://187.127.180.135:3003';

/// Expected GST database name for this build (e.g. `location1_gst`).
String get expectedGstDbName => AppConfig.expectedGstDbName;