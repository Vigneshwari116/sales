import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Staff view: today's sales totals for the logged-in location (LocalDb).
class StaffSalesDashboardScreen extends StatefulWidget {
  final String location;
  final int refreshGeneration;

  const StaffSalesDashboardScreen({
    super.key,
    required this.location,
    this.refreshGeneration = 0,
  });

  @override
  State<StaffSalesDashboardScreen> createState() =>
      _StaffSalesDashboardScreenState();
}

class _StaffSalesDashboardScreenState extends State<StaffSalesDashboardScreen> {
  bool _loading = true;
  AbstractSummary? _todaySummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StaffSalesDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshGeneration != oldWidget.refreshGeneration ||
        widget.location != oldWidget.location) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final today = DateTime.now();
    final summary = await AbstractRepository.getSummaryForDateRange(
      location: widget.location,
      fromDate: today,
      toDate: today,
    );

    if (!mounted) return;

    setState(() {
      _todaySummary = summary;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'TODAY\'S SALES',
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
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.location,
                    style: const TextStyle(
                      fontSize: AppTextSizes.statNumber,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, dd MMM yyyy').format(DateTime.now()),
                    style: const TextStyle(fontSize: AppTextSizes.listTitle),
                  ),
                  const SizedBox(height: 20),
                  _summaryCard(
                    'Total sales today',
                    _formatMoney(_todaySummary?.totalSaleAmount ?? 0),
                  ),
                  const SizedBox(height: 12),
                  _summaryCard(
                    'Total GST today',
                    _formatMoney(_todaySummary?.totalGst ?? 0),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: AppTextSizes.fieldText),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTextSizes.statNumber,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}
