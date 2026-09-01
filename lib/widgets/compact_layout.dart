import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_date_range_picker.dart';

/// Compact date-range trigger — opens a small from/to calendar popup.
class DateRangeButton extends StatelessWidget {
  final DateTime fromDate;
  final DateTime toDate;
  final ValueChanged<DateTimeRange> onChanged;

  const DateRangeButton({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showCompactDateRangePicker(
      context,
      fromDate: fromDate,
      toDate: toDate,
    );

    if (picked == null) return;
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('date_range_button'),
      onPressed: () => _pick(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.navy),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      child: const Text('DATE RANGE'),
    );
  }
}

/// Centers [child] at an explicit width capped by [maxWidth].
class CenteredContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, maxWidth);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Light header band app bar used inside staff/admin dashboard sections.
PreferredSizeWidget sectionHeaderAppBar(String title) {
  return AppBar(
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: AppTextSizes.appBarTitle,
        color: AppColors.navy,
      ),
    ),
    backgroundColor: AppColors.headerBand,
    foregroundColor: AppColors.navy,
    iconTheme: const IconThemeData(color: AppColors.navy),
    automaticallyImplyLeading: false,
  );
}

/// Small dashboard-style stat cards for abstract totals.
class CompactAbstractSummary extends StatelessWidget {
  final String totalSalesLabel;
  final String totalSalesValue;
  final String totalGstLabel;
  final String totalGstValue;

  const CompactAbstractSummary({
    super.key,
    this.totalSalesLabel = 'Total sales',
    this.totalGstLabel = 'Total GST',
    required this.totalSalesValue,
    required this.totalGstValue,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _statCard(totalSalesLabel, totalSalesValue),
          _statCard(totalGstLabel, totalGstValue),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      width: 190,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: AppTextSizes.listSubtitle,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTextSizes.statNumber,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
