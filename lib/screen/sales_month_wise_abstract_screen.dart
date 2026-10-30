import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/repositories/summary_repository.dart';
import 'package:sales/screen/admin_month_days_screen.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

class SalesMonthWiseAbstractScreen extends StatefulWidget {
  final String location;

  const SalesMonthWiseAbstractScreen({
    super.key,
    required this.location,
  });

  @override
  State<SalesMonthWiseAbstractScreen> createState() =>
      _SalesMonthWiseAbstractScreenState();
}

class _SalesMonthWiseAbstractScreenState
    extends State<SalesMonthWiseAbstractScreen> {
  int _year = DateTime.now().year;
  bool _loading = true;
  List<double> _monthTotals = List<double>.filled(12, 0);

  @override
  void initState() {
    super.initState();
    _loadMonths();
  }

  Future<void> _loadMonths() async {
    setState(() => _loading = true);

    final futures = <Future<AbstractSummary>>[];
    for (var month = 1; month <= 12; month++) {
      final fromDate = DateTime(_year, month, 1);
      final toDate = DateTime(_year, month + 1, 0);
      futures.add(
        AbstractRepository.getSummaryForDateRange(
          location: widget.location,
          fromDate: fromDate,
          toDate: toDate,
        ),
      );
    }

    final summaries = await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      _monthTotals = summaries
          .map((s) => s.totalSaleAmount + s.totalGst)
          .toList(growable: false);
      _loading = false;
    });
  }

  void _shiftYear(int delta) {
    setState(() => _year += delta);
    _loadMonths();
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String _monthTitle(int month) {
    final monthName = SummaryRepository.formatMonthLabel(month);
    return '$monthName $_year';
  }

  Future<void> _openMonth(int month) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminMonthDaysScreen(
          title: _monthTitle(month),
          year: _year,
          month: month,
          location: widget.location,
          adminFullEdit: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'MONTH WISE ABSTRACT',
        automaticallyImplyLeading: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left, color: AppColors.navy),
                        onPressed: () => _shiftYear(-1),
                      ),
                      Expanded(
                        child: Text(
                          '$_year',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTextSizes.statNumber,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right, color: AppColors.navy),
                        onPressed: () => _shiftYear(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildTable()),
                ],
              ),
            ),
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tableHeaderRow(),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: 12,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, thickness: 1, color: AppColors.border),
              itemBuilder: (context, index) {
                final month = index + 1;
                return _monthRow(
                  month: month,
                  total: _monthTotals[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderRow() {
    return Container(
      color: AppColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'MONTH',
              style: TextStyle(
                fontSize: AppTextSizes.tableHeaderText,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
          ),
          Text(
            'TOTAL',
            style: TextStyle(
              fontSize: AppTextSizes.tableHeaderText,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          SizedBox(width: 26),
        ],
      ),
    );
  }

  Widget _monthRow({required int month, required double total}) {
    final monthLabel =
        SummaryRepository.formatMonthLabel(month).toUpperCase();

    return Material(
      color: AppColors.cardWhite,
      child: InkWell(
        onTap: () => _openMonth(month),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    fontSize: AppTextSizes.tableRowText,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ),
              Text(
                _formatMoney(total),
                style: const TextStyle(
                  fontSize: AppTextSizes.tableRowText,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.mutedBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
