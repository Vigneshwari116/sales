import 'package:flutter/material.dart';

import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.online,
      builder: (context, online, _) {
        return ValueListenableBuilder<int>(
          valueListenable: SyncService.instance.pendingCount,
          builder: (context, pending, __) {
            final statusColor = online ? AppColors.success : AppColors.danger;
            final statusLabel = online ? 'Online' : 'Offline';
            final pendingLabel = pending == 0
                ? 'All bills synced'
                : pending == 1
                ? '1 bill pending upload'
                : '$pending bills pending upload';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    online
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    size: 18,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                          fontSize: AppTextSizes.fieldText,
                        ),
                      ),
                      Text(
                        pendingLabel,
                        style: TextStyle(
                          fontSize: AppTextSizes.listSubtitle,
                          color: AppColors.mutedBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
