import 'package:flutter/material.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/services/credential_service.dart';

/// One-time owner setup — required before any login on a fresh install.
class OwnerSetupScreen extends StatefulWidget {
  const OwnerSetupScreen({super.key});

  @override
  State<OwnerSetupScreen> createState() => _OwnerSetupScreenState();
}

class _OwnerSetupScreenState extends State<OwnerSetupScreen> {
  static const Color _btn = Color(0xFF9C1C1C);

  final _formKey = GlobalKey<FormState>();

  final _staffUserCtrl = TextEditingController();
  final _staffPassCtrl = TextEditingController();
  final _staffConfirmCtrl = TextEditingController();

  final _adminUserCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();
  final _adminConfirmCtrl = TextEditingController();

  final _deletePinCtrl = TextEditingController();
  final _deletePinConfirmCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _staffUserCtrl.dispose();
    _staffPassCtrl.dispose();
    _staffConfirmCtrl.dispose();
    _adminUserCtrl.dispose();
    _adminPassCtrl.dispose();
    _adminConfirmCtrl.dispose();
    _deletePinCtrl.dispose();
    _deletePinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await CredentialService.saveInitialSetup(
        staffUsername: _staffUserCtrl.text.trim(),
        staffPassword: _staffPassCtrl.text,
        adminUsername: _adminUserCtrl.text.trim(),
        adminPassword: _adminPassCtrl.text,
        ownerDeletePin: _deletePinCtrl.text,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on CredentialValidationException catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Setup failed: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC6F5C6),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF808080)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.security, size: 48, color: _btn),
                    const SizedBox(height: 8),
                    const Text(
                      'Owner Setup',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configure credentials for this device. Each location '
                      'device runs setup independently — secrets are not '
                      'synced across Win 1–4 tablets.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Staff POS login'),
                    _textField(
                      controller: _staffUserCtrl,
                      label: 'Staff username',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    _passwordField(
                      controller: _staffPassCtrl,
                      label: 'Staff password',
                      minLength: CredentialService.minPasswordLength,
                    ),
                    _passwordField(
                      controller: _staffConfirmCtrl,
                      label: 'Confirm staff password',
                      matchController: _staffPassCtrl,
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Admin dashboard login'),
                    _textField(
                      controller: _adminUserCtrl,
                      label: 'Admin username',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    _passwordField(
                      controller: _adminPassCtrl,
                      label: 'Admin password',
                      minLength: CredentialService.minPasswordLength,
                    ),
                    _passwordField(
                      controller: _adminConfirmCtrl,
                      label: 'Confirm admin password',
                      matchController: _adminPassCtrl,
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Owner delete PIN'),
                    const Text(
                      'Separate from admin login — unlocks bill deletion on '
                      'the ledger. Staff should not know this PIN.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    _passwordField(
                      controller: _deletePinCtrl,
                      label: 'Owner-delete PIN',
                      minLength: CredentialService.minPinLength,
                    ),
                    _passwordField(
                      controller: _deletePinConfirmCtrl,
                      label: 'Confirm owner-delete PIN',
                      matchController: _deletePinCtrl,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        key: const Key('owner_setup_save_button'),
                        onPressed: _busy ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _btn,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_busy ? 'SAVING...' : 'SAVE & CONTINUE'),
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: validator,
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    int minLength = 0,
    TextEditingController? matchController,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        obscureText: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Required';
          if (minLength > 0 && v.length < minLength) {
            return 'At least $minLength characters';
          }
          if (matchController != null && v != matchController.text) {
            return 'Does not match';
          }
          return null;
        },
      ),
    );
  }
}
