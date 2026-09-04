import 'package:flutter/material.dart';
import 'package:sales/config/app_license.dart';
import 'package:sales/theme/app_theme.dart';

/// Shown when the app is past its licensed support window.
class AppExpiredScreen extends StatelessWidget {
  const AppExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event_busy_outlined,
                  size: 56,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 16),
                const Text(
                  'App License Expired',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLicense.expiryMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.mutedBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
