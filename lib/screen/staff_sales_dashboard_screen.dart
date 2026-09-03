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
    final amount = _todaySummary?.totalSaleAmount ?? 0;
    final gst = _todaySummary?.totalGst ?? 0;

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
          : CenteredContent(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 16),
                  CompactAbstractSummary(
                    amountValue: _formatMoney(amount),
                    gstValue: _formatMoney(gst),
                    grandTotalValue: _formatMoney(amount + gst),
                    grandTotalLabel: 'Total sales',
                  ),
                ],
              ),
            ),
    );
  }
}
