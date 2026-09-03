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

/// Light header band app bar — dark navy title on pale header for readability.
PreferredSizeWidget sectionHeaderAppBar(
  String title, {
  bool automaticallyImplyLeading = false,
  Widget? leading,
  List<Widget>? actions,
}) {
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
    actionsIconTheme: const IconThemeData(color: AppColors.navy),
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    actions: actions,
  );
}

/// Compact primary action button used on bill and admin screens.
class CompactSaveButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  const CompactSaveButton({
    super.key,
    this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 148,
        height: 34,
        child: ElevatedButton(
          key: buttonKey,
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: AppTextSizes.buttonText,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Small dashboard-style stat cards for abstract totals.
class CompactAbstractSummary extends StatelessWidget {
  final String totalSalesLabel;
  final String totalSalesValue;
  final String? totalGstLabel;
  final String? totalGstValue;

  const CompactAbstractSummary({
    super.key,
    this.totalSalesLabel = 'Total sales',
    this.totalGstLabel = 'Total GST',
    required this.totalSalesValue,
    this.totalGstValue,
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
          if (totalGstLabel != null && totalGstValue != null)
            _statCard(totalGstLabel!, totalGstValue!),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.mutedBlue,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
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
