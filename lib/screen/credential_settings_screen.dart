import 'package:flutter/material.dart';
import 'package:sales/services/credential_service.dart';

/// Admin-only credential rotation (staff / admin / owner-delete PIN).
class CredentialSettingsScreen extends StatefulWidget {
  const CredentialSettingsScreen({super.key});

  @override
  State<CredentialSettingsScreen> createState() =>
      _CredentialSettingsScreenState();
}

class _CredentialSettingsScreenState extends State<CredentialSettingsScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _btn = Color(0xFF9C1C1C);

  String? _staffUsername;
  String? _adminUsername;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsernames();
  }

  Future<void> _loadUsernames() async {
    final staff = await CredentialService.staffUsername();
    final admin = await CredentialService.adminUsername();
    if (!mounted) return;
    setState(() {
      _staffUsername = staff;
      _adminUsername = admin;
      _loading = false;
    });
  }

  Future<void> _rotateStaffPassword() async {
    final result = await showDialog<_StaffRotationResult>(
      context: context,
      builder: (_) => _StaffPasswordDialog(currentStaffUser: _staffUsername),
    );
    if (result == null) return;

    try {
      final ok = await CredentialService.rotateStaffPassword(
        currentAdminPassword: result.adminPassword,
        newPassword: result.newPassword,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Staff password updated.'
                : 'Incorrect admin password.',
          ),
        ),
      );
    } on CredentialValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _rotateAdminPassword() async {
    final result = await showDialog<_AdminRotationResult>(
      context: context,
      builder: (_) => _AdminPasswordDialog(currentAdminUser: _adminUsername),
    );
    if (result == null) return;

    try {
      final ok = await CredentialService.rotateAdminPassword(
        currentAdminPassword: result.currentAdminPassword,
        newUsername: result.newUsername,
        newPassword: result.newPassword,
      );

      if (!mounted) return;

      if (ok) {
        if (!mounted) return;
        await _loadUsernames();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin credentials updated.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect current admin password.')),
        );
      }
    } on CredentialValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _rotateDeletePin() async {
    final result = await showDialog<_DeletePinRotationResult>(
      context: context,
      builder: (_) => const _DeletePinDialog(),
    );
    if (result == null) return;

    try {
      final ok = await CredentialService.rotateOwnerDeletePin(
        currentDeletePin: result.currentPin,
        newPin: result.newPin,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Owner-delete PIN updated.' : 'Incorrect current PIN.',
          ),
        ),
      );
    } on CredentialValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SECURITY',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _settingsCard(
                  key: const Key('credential_rotate_staff'),
                  title: 'Staff POS password',
                  subtitle: 'User: ${_staffUsername ?? '—'}',
                  buttonLabel: 'CHANGE STAFF PASSWORD',
                  onPressed: _rotateStaffPassword,
                ),
                const SizedBox(height: 12),
                _settingsCard(
                  key: const Key('credential_rotate_admin'),
                  title: 'Admin dashboard login',
                  subtitle: 'User: ${_adminUsername ?? '—'}',
                  buttonLabel: 'CHANGE ADMIN LOGIN',
                  onPressed: _rotateAdminPassword,
                ),
                const SizedBox(height: 12),
                _settingsCard(
                  key: const Key('credential_rotate_delete_pin'),
                  title: 'Owner-delete PIN',
                  subtitle:
                      'Requires current PIN only — not the admin password.',
                  buttonLabel: 'CHANGE DELETE PIN',
                  onPressed: _rotateDeletePin,
                ),
              ],
            ),
    );
  }

  Widget _settingsCard({
    required Key key,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _btn,
                foregroundColor: Colors.white,
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffRotationResult {
  final String adminPassword;
  final String newPassword;

  _StaffRotationResult({
    required this.adminPassword,
    required this.newPassword,
  });
}

class _StaffPasswordDialog extends StatefulWidget {
  final String? currentStaffUser;

  const _StaffPasswordDialog({this.currentStaffUser});

  @override
  State<_StaffPasswordDialog> createState() => _StaffPasswordDialogState();
}

class _StaffPasswordDialogState extends State<_StaffPasswordDialog> {
  final _adminPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _adminPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change staff password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.currentStaffUser != null)
            Text('Staff user: ${widget.currentStaffUser}'),
          TextField(
            controller: _adminPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Your admin password'),
          ),
          TextField(
            controller: _newPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New staff password'),
          ),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () {
            if (_newPassCtrl.text.length < CredentialService.minPasswordLength) {
              return;
            }
            if (_newPassCtrl.text != _confirmCtrl.text) return;
            Navigator.pop(
              context,
              _StaffRotationResult(
                adminPassword: _adminPassCtrl.text,
                newPassword: _newPassCtrl.text,
              ),
            );
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

class _AdminRotationResult {
  final String currentAdminPassword;
  final String newUsername;
  final String newPassword;

  _AdminRotationResult({
    required this.currentAdminPassword,
    required this.newUsername,
    required this.newPassword,
  });
}

class _AdminPasswordDialog extends StatefulWidget {
  final String? currentAdminUser;

  const _AdminPasswordDialog({this.currentAdminUser});

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final _currentPassCtrl = TextEditingController();
  final _newUserCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _newUserCtrl.text = widget.currentAdminUser ?? '';
  }

  @override
  void dispose() {
    _currentPassCtrl.dispose();
    _newUserCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change admin login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPassCtrl,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Current admin password'),
          ),
          TextField(
            controller: _newUserCtrl,
            decoration: const InputDecoration(labelText: 'New admin username'),
          ),
          TextField(
            controller: _newPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New admin password'),
          ),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () {
            if (_newUserCtrl.text.trim().isEmpty) return;
            if (_newPassCtrl.text.length < CredentialService.minPasswordLength) {
              return;
            }
            if (_newPassCtrl.text != _confirmCtrl.text) return;
            Navigator.pop(
              context,
              _AdminRotationResult(
                currentAdminPassword: _currentPassCtrl.text,
                newUsername: _newUserCtrl.text.trim(),
                newPassword: _newPassCtrl.text,
              ),
            );
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}

class _DeletePinRotationResult {
  final String currentPin;
  final String newPin;

  _DeletePinRotationResult({
    required this.currentPin,
    required this.newPin,
  });
}

class _DeletePinDialog extends StatefulWidget {
  const _DeletePinDialog();

  @override
  State<_DeletePinDialog> createState() => _DeletePinDialogState();
}

class _DeletePinDialogState extends State<_DeletePinDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change owner-delete PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Current delete PIN required. Admin password cannot be used here.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _currentCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current delete PIN'),
          ),
          TextField(
            controller: _newCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New delete PIN'),
          ),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new PIN'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () {
            if (_newCtrl.text.length < CredentialService.minPinLength) return;
            if (_newCtrl.text != _confirmCtrl.text) return;
            Navigator.pop(
              context,
              _DeletePinRotationResult(
                currentPin: _currentCtrl.text,
                newPin: _newCtrl.text,
              ),
            );
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }
}
