import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/screen/admin_day_bills_screen.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Scrollable day totals for a month — tap a day to open bills when detail exists.
class AdminMonthDaysScreen extends StatefulWidget {
  final String title;
  final int year;
  final int month;
  final String? location;
  final bool adminFullEdit;

  @visibleForTesting
  final Future<List<DaySummaryRow>> Function()? loadDaysOverride;

  const AdminMonthDaysScreen({
    super.key,
    required this.title,
    required this.year,
    required this.month,
    this.location,
    this.adminFullEdit = true,
    this.loadDaysOverride,
  });

  @override
  State<AdminMonthDaysScreen> createState() => _AdminMonthDaysScreenState();
}

class _AdminMonthDaysScreenState extends State<AdminMonthDaysScreen> {
  bool _loading = true;
  List<DaySummaryRow> _days = const [];

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  Future<void> _loadDays() async {
    setState(() => _loading = true);

    final days = widget.loadDaysOverride != null
        ? await widget.loadDaysOverride!()
        : await DayDrillDownRepository.getDaySummariesForMonth(
            year: widget.year,
            month: widget.month,
            location: widget.location,
          );

    if (!mounted) return;

    setState(() {
      _days = days;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  Future<void> _openDay(DaySummaryRow row) async {
    if (!row.hasLineItemDetail) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminDayBillsScreen(
          day: row.day,
          title: row.label,
          location: widget.location,
          adminFullEdit: widget.adminFullEdit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        widget.title,
        automaticallyImplyLeading: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _days.isEmpty
              ? const Center(
                  child: Text(
                    'No daily totals for this period',
                    style: TextStyle(color: AppColors.mutedBlue),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _days.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = _days[index];
                    return _DaySummaryCard(
                      row: row,
                      amountLabel: _formatMoney(row.grandTotal),
                      onTap: row.hasLineItemDetail ? () => _openDay(row) : null,
                    );
                  },
                ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  final DaySummaryRow row;
  final String amountLabel;
  final VoidCallback? onTap;

  const _DaySummaryCard({
    required this.row,
    required this.amountLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canDrill = onTap != null;

    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: AppTextSizes.listTitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    if (!canDrill)
                      const Text(
                        'Grand total only',
                        style: TextStyle(
                          fontSize: AppTextSizes.listSubtitle,
                          color: AppColors.mutedBlue,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                amountLabel,
                style: const TextStyle(
                  fontSize: AppTextSizes.listTitle,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              if (canDrill) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.mutedBlue,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
