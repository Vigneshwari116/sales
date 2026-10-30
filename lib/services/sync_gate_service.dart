import 'package:flutter/material.dart';
import 'package:sales/config/local_credentials.dart';

/// Password and confirmation prompts before sync or data reset.
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return ok ?? false;
  }

  static Future<bool> confirmReset(BuildContext context) async {
    final passwordOk = await _promptPassword(
      context,
      title: 'Reset password',
      message: 'Enter reset password to continue.',
      confirmLabel: 'CONTINUE',
    );
    if (!passwordOk || !context.mounted) {
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset all sales data?'),
          content: const Text(
            'This will permanently delete ALL sales data for this location '
            'on this device and on the server, and reset bill numbers to 1.\n\n'
            'RESET wipes local and server data for this location. '
            'Always finish with SYNC if you reset while offline.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('RESET'),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  static Future<bool> confirmDeleteAllBills(BuildContext context) async {
    final controller = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Delete all bills?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently deletes every saved bill for this location '
                    'on this device, resets bill numbers to 1, and clears local '
                    'totals and pending sync.\n\n'
                    'Users, GST settings, and printer settings are not changed.\n\n'
                    'Type DELETE to confirm.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Confirmation',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setState(() => error = null);
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
                    if (controller.text.trim() == 'DELETE') {
                      Navigator.pop(dialogContext, true);
                    } else {
                      setState(
                        () => error = 'Type DELETE exactly to continue',
                      );
                    }
                  },
                  child: const Text('DELETE ALL BILLS'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return ok ?? false;
  }

  static Future<bool> _promptPassword(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
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
                      if (controller.text == resetPassword) {
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
                    if (controller.text == resetPassword) {
                      Navigator.pop(dialogContext, true);
                    } else {
                      setState(() => error = 'Incorrect password');
                    }
                  },
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    return ok ?? false;
  }
}
