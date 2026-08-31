import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/owner_setup_screen.dart';
import 'package:sales/services/credential_service.dart';
import 'package:sales/services/credential_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CredentialService.useStorage(InMemoryCredentialStorage());
    await CredentialService.resetForTesting();
  });

  tearDown(() async {
    await CredentialService.resetForTesting();
  });

  testWidgets('unconfigured app shows owner setup', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OwnerSetupScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Owner Setup'), findsOneWidget);
    expect(find.text('SAVE & CONTINUE'), findsOneWidget);
  });

  testWidgets('owner setup saves credentials and opens staff login',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: OwnerSetupScreen()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'counter');
    await tester.enterText(fields.at(1), 'staffpass1');
    await tester.enterText(fields.at(2), 'staffpass1');
    await tester.enterText(fields.at(3), 'owner');
    await tester.enterText(fields.at(4), 'adminpass1');
    await tester.enterText(fields.at(5), 'adminpass1');
    await tester.enterText(fields.at(6), 'delete99');
    await tester.enterText(fields.at(7), 'delete99');

    await tester.ensureVisible(find.byKey(const Key('owner_setup_save_button')));
    await tester.tap(find.byKey(const Key('owner_setup_save_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await CredentialService.isConfigured(), isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
