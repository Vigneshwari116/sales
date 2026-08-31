import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/screen/admin_dashboard_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/owner_setup_screen.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/credential_service.dart';
import 'package:sales/services/session_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppConfig.loadFromPrefs();
  runApp(const SalesBillApp());
}

class SalesBillApp extends StatelessWidget {
  const SalesBillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sales Bill',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late Future<Widget> _homeFuture;

  @override
  void initState() {
    super.initState();
    _homeFuture = _resolveHome();
  }

  Future<Widget> _resolveHome() async {
    if (!await CredentialService.isConfigured()) {
      return const OwnerSetupScreen();
    }

    final loggedIn = await SessionService.isLoggedIn();

    if (loggedIn && AppConfig.isLocationSet) {
      final role = await SessionService.getRole();
      await AppSessionService.onLoginComplete();

      if (role == SessionRole.admin) {
        return const AdminDashboardScreen();
      }
      if (role == SessionRole.staff) {
        return const SalesBillScreen();
      }
    }

    if (loggedIn) {
      await SessionService.clearLogin();
    }

    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _homeFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFC6F5C6),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data!;
      },
    );
  }
}
