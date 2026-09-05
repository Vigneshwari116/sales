import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/config/app_license.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/screen/admin_dashboard_screen.dart';
import 'package:sales/screen/staff_dashboard_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/theme/app_theme.dart';

/// Single login for staff (win1–win3) and admin — no role toggle on screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  /// Test seam: replace dashboard destinations without mounting heavy screens.
  @visibleForTesting
  static WidgetBuilder? adminHomeBuilder;

  @visibleForTesting
  static WidgetBuilder? staffHomeBuilder;

  @visibleForTesting
  static void resetTestHooks() {
    adminHomeBuilder = null;
    staffHomeBuilder = null;
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loggingIn = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (!AppLicense.isValid) {
      setState(() => _error = AppLicense.expiryMessage);
      return;
    }

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text.trim();

    final isAdmin = verifyAdminLogin(username, password);
    final isStaff = verifyStaffLogin(username, password);

    if (!isAdmin && !isStaff) {
      setState(() => _error = 'Incorrect username or password.');
      return;
    }

    setState(() => _error = null);

    setState(() => _loggingIn = true);

    try {
      await SessionService.clearBillSession();

      if (isAdmin) {
        await AppConfig.setLocation('win1');
        await SessionService.saveLogin(username, role: SessionRole.admin);

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: LoginScreen.adminHomeBuilder ??
                (_) => const AdminDashboardScreen(),
          ),
        );
        unawaited(AppSessionService.onLoginComplete());
        return;
      }

      final locationCode = staffLocationCodeForUsername(username);
      await AppConfig.setLocation(locationCode);
      await SessionService.saveLogin(username, role: SessionRole.staff);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: LoginScreen.staffHomeBuilder ??
              (_) => const StaffDashboardScreen(),
        ),
      );
      unawaited(AppSessionService.onLoginComplete());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Login failed. Please try again.';
        _loggingIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardWhite,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.storefront,
                      size: 48,
                      color: AppColors.navy,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sales Bill Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _userCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Required' : null,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loggingIn ? null : _login,
                        child: _loggingIn
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'LOGIN',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
