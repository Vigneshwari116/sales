import 'package:flutter/material.dart';
import 'package:sales/config/local_credentials.dart';

/// Prompts for sync password before manual push/pull.
class SyncGateService {
  static Future<bool> confirmSync(BuildContext context) async {
    final controller = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Sync password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter sync password to continue.'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      if (controller.text == syncPassword) {
                        Navigator.pop(dialogContext, true);
                      } else {
                        setState(() => error = 'Incorrect password');
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () {
                    if (controller.text == syncPassword) {
                      Navigator.pop(dialogContext, true);
                    } else {
                      setState(() => error = 'Incorrect password');
                    }
                  },
                  child: const Text('SYNC'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return ok ?? false;
  }
}
