import 'package:flutter/material.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/services/session_service.dart';

void main() => runApp(const SalesBillApp());

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
  late Future<bool> _loginFuture;

  @override
  void initState() {
    super.initState();
    _loginFuture = SessionService.isLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loginFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFC6F5C6),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data!
            ? const SalesBillScreen()
            : const LoginScreen();
      },
    );
  }
}
