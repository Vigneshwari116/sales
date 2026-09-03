import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/repositories/location_sync_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Admin main view: today's totals per location in a compact grid.
class AdminLocationGridScreen extends StatefulWidget {
  final int refreshGeneration;

  const AdminLocationGridScreen({
    super.key,
    this.refreshGeneration = 0,
  });

  @override
  State<AdminLocationGridScreen> createState() =>
      _AdminLocationGridScreenState();
}

class _AdminLocationGridScreenState extends State<AdminLocationGridScreen> {
  Map<String, AbstractSummary> _todayByLocation = {
    for (final code in allLocationCodes)
      displayNameForLocationCode(code): AbstractSummary.zero(),
  };
  Map<String, DateTime?> _lastSyncedByLocation = {
    for (final code in allLocationCodes)
      displayNameForLocationCode(code): null,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AdminLocationGridScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshGeneration != widget.refreshGeneration) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final today = DateTime.now();
      final summaries = <String, AbstractSummary>{};
      final lastSynced = <String, DateTime?>{};

      for (final code in allLocationCodes) {
        final name = displayNameForLocationCode(code);
        summaries[name] = await AbstractRepository.getSummaryForLocationCode(
          locationCode: code,
          fromDate: today,
          toDate: today,
        );
        lastSynced[name] =
            await LocationSyncRepository.getLastSyncedAtForLocationCode(code);
      }

      if (!mounted) return;

      setState(() {
        _todayByLocation = summaries;
        _lastSyncedByLocation = lastSynced;
      });
    } catch (_) {
      // Keep zeroed placeholders on error.
    }
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String _formatLastSynced(DateTime? syncedAt) {
    if (syncedAt == null) {
      return 'Not synced';
    }

    final local = syncedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final syncedDay = DateTime(local.year, local.month, local.day);

    if (syncedDay == today) {
      return 'Synced ${DateFormat('h:mm a').format(local)}';
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (syncedDay == yesterday) {
      return 'Synced yesterday';
    }

    return 'Synced ${DateFormat('dd-MMM').format(local)}';
  }

  Color _lastSyncedColor(DateTime? syncedAt) {
    if (syncedAt == null) {
      return AppColors.danger;
    }

    final age = DateTime.now().difference(syncedAt.toLocal());
    if (age > const Duration(hours: 24)) {
      return const Color(0xFFB45309);
    }

    return AppColors.mutedBlue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'DASHBOARD',
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in allLocationCodes)
                _locationCard(displayNameForLocationCode(code)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationCard(String locationName) {
    final summary = _todayByLocation[locationName];
    final lastSynced = _lastSyncedByLocation[locationName];
    final syncLabel = _formatLastSynced(lastSynced);
    final amount = summary?.totalSaleAmount ?? 0;
    final gst = summary?.totalGst ?? 0;

    return Container(
      key: Key('admin_location_card_${locationName.toLowerCase()}'),
      width: 470,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LocationBrandingHeader(
            locationDisplayName: locationName,
            align: TextAlign.left,
            compact: true,
          ),
          const SizedBox(height: 8),
          CompactAbstractSummary(
            amountValue: _formatMoney(amount),
            gstValue: _formatMoney(gst),
            grandTotalValue: _formatMoney(amount + gst),
            grandTotalLabel: 'Total sales',
            cardWidth: 146,
          ),
          const SizedBox(height: 6),
          Text(
            syncLabel,
            key: Key('admin_last_synced_${locationName.toLowerCase()}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _lastSyncedColor(lastSynced),
            ),
          ),
        ],
      ),
    );
  }
}
