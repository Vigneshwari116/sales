import 'package:flutter/material.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/screen/admin_dashboard_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';

/// Admin login — cross-location; no location dropdown.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  static const Color _btn = Color(0xFF9C1C1C);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (!verifyAdminLogin(username, password)) {
      setState(() => _error = 'Incorrect username or password.');
      return;
    }

    setState(() => _error = null);

    await SessionService.clearBillSession();
    // Admin session uses win1 internally for any local DB paths; UI is cross-location.
    await AppConfig.setLocation('win1');
    await AppSessionService.onLoginComplete();
    await SessionService.saveLogin(username, role: SessionRole.admin);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
    );
  }

  void _openStaffLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC6F5C6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF808080)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
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
                    const Icon(Icons.admin_panel_settings,
                        size: 48, color: _btn),
                    const SizedBox(height: 8),
                    const Text(
                      'Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _userCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
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
                        border: const OutlineInputBorder(),
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
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _btn,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Switch login',
                        onPressed: _openStaffLogin,
                        icon: const Icon(Icons.swap_horiz, size: 20),
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
