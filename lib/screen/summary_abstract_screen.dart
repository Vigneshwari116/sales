import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/db/summary_db.dart';
import 'package:sales/repositories/summary_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Month-wise and day-wise totals from summary database only.
class SummaryAbstractScreen extends StatefulWidget {
  final int refreshGeneration;

  const SummaryAbstractScreen({
    super.key,
    this.refreshGeneration = 0,
  });

  @override
  State<SummaryAbstractScreen> createState() => _SummaryAbstractScreenState();
}

class _SummaryAbstractScreenState extends State<SummaryAbstractScreen> {
  final int _year = DateTime.now().year;
  bool _loading = true;
  List<MonthSummaryRow> _months = const [];
  int? _selectedMonth;
  List<DaySummaryRow> _days = const [];

  @override
  void initState() {
    super.initState();
    _loadMonths();
  }

  @override
  void didUpdateWidget(covariant SummaryAbstractScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshGeneration != oldWidget.refreshGeneration) {
      _loadMonths();
    }
  }

  Future<void> _loadMonths() async {
    setState(() {
      _loading = true;
      _selectedMonth = null;
      _days = const [];
    });

    final months = await SummaryRepository.getMonthTotalsForYear(year: _year);
    if (!mounted) return;

    setState(() {
      _months = months;
      _loading = false;
    });
  }

  Future<void> _loadDays(int month) async {
    setState(() {
      _loading = true;
      _selectedMonth = month;
    });

    final days = await SummaryRepository.getDayTotalsForMonth(
      year: _year,
      month: month,
    );

    if (!mounted) return;

    setState(() {
      _days = days;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'ABSTRACT',
        actions: [
          IconButton(
            onPressed: _selectedMonth == null ? _loadMonths : () => _loadDays(_selectedMonth!),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Year $_year',
                    style: const TextStyle(
                      fontSize: AppTextSizes.sectionHeader,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedMonth == null) ...[
                    const Text(
                      'MONTH-WISE TOTALS',
                      style: TextStyle(
                        fontSize: AppTextSizes.listSubtitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildMonthList()),
                  ] else ...[
                    TextButton(
                      onPressed: _loadMonths,
                      child: const Text('BACK TO MONTHS'),
                    ),
                    Text(
                      SummaryRepository.formatMonthLabel(_selectedMonth!),
                      style: const TextStyle(
                        fontSize: AppTextSizes.listTitle,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildDayList()),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMonthList() {
    if (_months.isEmpty) {
      return const Center(
        child: Text(
          'No monthly totals yet',
          style: TextStyle(color: AppColors.mutedBlue),
        ),
      );
    }

    final monthMap = {for (final row in _months) row.month: row.totalAmount};

    return ListView.separated(
      itemCount: 12,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final month = index + 1;
        final total = monthMap[month] ?? 0;
        return ListTile(
          title: Text(SummaryRepository.formatMonthLabel(month)),
          trailing: Text(
            _formatMoney(total),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          onTap: () => _loadDays(month),
        );
      },
    );
  }

  Widget _buildDayList() {
    if (_days.isEmpty) {
      return const Center(
        child: Text(
          'No daily totals for this month',
          style: TextStyle(color: AppColors.mutedBlue),
        ),
      );
    }

    return ListView.separated(
      itemCount: _days.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = _days[index];
        final label = DateFormat('dd MMM yyyy').format(DateTime.parse(row.day));
        return ListTile(
          title: Text(label),
          trailing: Text(
            _formatMoney(row.totalAmount),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        );
      },
    );
  }
}
