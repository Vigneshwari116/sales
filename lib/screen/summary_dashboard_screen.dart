import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/summary_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Fast dashboard: today's total sales from summary database only.
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
    final total = await SummaryRepository.getTodayTotal();
    if (!mounted) return;
    setState(() {
      _todayTotal = total;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 520,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TODAY'S TOTAL SALES",
                      style: TextStyle(
                        fontSize: AppTextSizes.listSubtitle,
                        fontWeight: FontWeight.w600,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatMoney(_todayTotal),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('dd MMM yyyy').format(DateTime.now()),
                      style: const TextStyle(
                        fontSize: AppTextSizes.listSubtitle,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
