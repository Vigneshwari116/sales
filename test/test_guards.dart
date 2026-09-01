/// Shared test guard — import from any test that might touch SalesApi.
///
/// Production host calls are refused unless [SalesApi.clientOverride] is set
/// to a mock client. Live curl/probes against the VPS must never live in tests.
library;

import 'package:sales/api/sales_api.dart';

void enableProductionNetworkGuard() {
  SalesApi.forbidProductionHost = true;
}

void disableProductionNetworkGuard() {
  SalesApi.forbidProductionHost = false;
  SalesApi.resetClientOverride();
}
