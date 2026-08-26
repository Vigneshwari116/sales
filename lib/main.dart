import 'package:flutter/material.dart';
import 'package:sales/screen/login_screen.dart';

void main() => runApp(const SalesBillApp());

class SalesBillApp extends StatelessWidget {
  const SalesBillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sales Bill',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const LoginScreen(),
    );
  }
}