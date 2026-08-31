// Basic app smoke test — verifies login screen loads.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app loads login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SalesBillApp());
    await tester.pumpAndSettle();

    expect(find.text('Sales Bill Login'), findsOneWidget);
  });
}
