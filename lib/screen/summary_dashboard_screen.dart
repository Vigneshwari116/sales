import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/db/summary_db.dart';
import 'package:sales/repositories/summary_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Fast dashboard: today's sales per location + current month date-wise totals.
class SummaryDashboardScreen extends StatefulWidget {
  final int refreshGeneration;

  const SummaryDashboardScreen({
    super.key,
    this.refreshGeneration = 0,
  });

  @override
  State<SummaryDashboardScreen> createState() => _SummaryDashboardScreenState();
}

class _SummaryDashboardScreenState extends State<SummaryDashboardScreen> {
  bool _loading = true;
  double _todayTotal = 0;
  Map<String, double> _todayByLocation = {
    for (final code in allLocationCodes)
      displayNameForLocationCode(code): 0,
  };
  List<DaySummaryRow> _monthDays = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SummaryDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshGeneration != oldWidget.refreshGeneration) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    await SummaryDb.instance.initialize();

    final now = DateTime.now();
    final day = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final byLocation = <String, double>{};
    for (final code in allLocationCodes) {
      final name = displayNameForLocationCode(code);
      byLocation[name] = await SummaryDb.instance.getTotalForDay(
        day: day,
        location: name,
      );
    }

    final monthDays = await SummaryRepository.getDayTotalsForMonth(
      year: now.year,
      month: now.month,
    );

    if (!mounted) return;

    setState(() {
      _todayByLocation = byLocation;
      _todayTotal = byLocation.values.fold(0, (sum, value) => sum + value);
      _monthDays = monthDays;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 520;
                final cardWidth = isNarrow
                    ? constraints.maxWidth - 24
                    : math.min(470.0, constraints.maxWidth - 24);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _combinedTodayCard(),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final code in allLocationCodes)
                              _locationCard(
                                displayNameForLocationCode(code),
                                cardWidth: cardWidth,
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'DATE-WISE TOTALS — $monthLabel',
                          style: const TextStyle(
                            fontSize: AppTextSizes.listSubtitle,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedBlue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _dateWiseSection(cardWidth: cardWidth),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _combinedTodayCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "TODAY'S TOTAL SALES (ALL LOCATIONS)",
            style: TextStyle(
              fontSize: AppTextSizes.listSubtitle,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatMoney(_todayTotal),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM yyyy').format(DateTime.now()),
            style: const TextStyle(
              fontSize: AppTextSizes.listSubtitle,
              color: AppColors.mutedBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard(String locationName, {required double cardWidth}) {
    final total = _todayByLocation[locationName] ?? 0;

    return Container(
      key: Key('summary_location_card_${locationName.toLowerCase()}'),
      width: cardWidth,
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
          const Text(
            "Today's sales",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatMoney(total),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateWiseSection({required double cardWidth}) {
    if (_monthDays.isEmpty) {
      return Container(
        width: cardWidth,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'No date-wise totals for this month yet',
          style: TextStyle(color: AppColors.mutedBlue),
        ),
      );
    }

    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _monthDays.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _dateRow(_monthDays[i]),
          ],
        ],
      ),
    );
  }

  Widget _dateRow(DaySummaryRow row) {
    final label = DateFormat('dd MMM yyyy').format(DateTime.parse(row.day));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTextSizes.listTitle,
                fontWeight: FontWeight.w500,
                color: AppColors.navy,
              ),
            ),
          ),
          Text(
            _formatMoney(row.totalAmount),
            style: const TextStyle(
              fontSize: AppTextSizes.listTitle,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}
