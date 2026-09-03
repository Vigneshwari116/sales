import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

class SalesAbstractScreen extends StatefulWidget {
  final String location;
  final int refreshGeneration;

  const SalesAbstractScreen({
    super.key,
    required this.location,
    this.refreshGeneration = 0,
  });

  @override
  State<SalesAbstractScreen> createState() => _SalesAbstractScreenState();
}

class _SalesAbstractScreenState extends State<SalesAbstractScreen> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  bool _loading = true;
  String? _dateRangeError;
  AbstractSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void didUpdateWidget(covariant SalesAbstractScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location ||
        widget.refreshGeneration != oldWidget.refreshGeneration) {
      _loadSummary();
    }
  }

  bool get _isDateRangeValid {
    final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final to = DateTime(_toDate.year, _toDate.month, _toDate.day);
    return !to.isBefore(from);
  }

  Future<void> _loadSummary() async {
    if (!_isDateRangeValid) {
      setState(() {
        _loading = false;
        _dateRangeError = 'To Date cannot be before From Date';
        _summary = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _dateRangeError = null;
    });

    var summary = await AbstractRepository.getSummaryForDateRange(
      location: widget.location,
      fromDate: _fromDate,
      toDate: _toDate,
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _fromDate = now;
      _toDate = now;
    });
    _loadSummary();
  }

  String _formatMoney(double value) {
    return NumberFormat('#,##0.00').format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar('SALES ABSTRACT'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 1100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DateRangeButton(
                        fromDate: _fromDate,
                        toDate: _toDate,
                        onChanged: (range) {
                          setState(() {
                            _fromDate = range.start;
                            _toDate = range.end;
                          });
                          _loadSummary();
                        },
                      ),
                      OutlinedButton(
                        onPressed: _setToday,
                        child: const Text('TODAY'),
                      ),
                    ],
                  ),
                  if (_dateRangeError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _dateRangeError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: AppTextSizes.listTitle,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  CompactAbstractSummary(
                    totalSalesLabel: 'Total sales',
                    totalGstLabel: 'Total GST',
                    totalSalesValue:
                        _formatMoney(_summary?.totalSaleAmount ?? 0),
                    totalGstValue: _formatMoney(_summary?.totalGst ?? 0),
                  ),
                ],
              ),
            ),
    );
  }
}
