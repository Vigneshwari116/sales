// Basic app smoke test — verifies login screen loads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app loads login screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SalesBillApp());
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.byIcon(Icons.storefront), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/surabhi_logo.png',
      ),
      findsOneWidget,
    );
  });
}
