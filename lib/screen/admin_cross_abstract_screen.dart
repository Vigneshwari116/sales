import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/abstract_repository.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Cross-location abstract totals for admin (all four locations combined).
class AdminCrossAbstractScreen extends StatefulWidget {
  const AdminCrossAbstractScreen({super.key});

  @override
  State<AdminCrossAbstractScreen> createState() =>
      _AdminCrossAbstractScreenState();
}

class _AdminCrossAbstractScreenState extends State<AdminCrossAbstractScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _border = Color(0xFF888888);

  DateTime? _fromDate;
  DateTime? _toDate;
  bool _loading = true;
  String? _dateRangeError;
  AbstractSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  bool get _isDateRangeValid {
    if (_fromDate == null || _toDate == null) return true;
    final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
    final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
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

    final from = _fromDate ?? DateTime.now();
    final to = _toDate ?? DateTime.now();

    final summary = await AbstractRepository.getCrossLocationSummary(
      fromDate: from,
      toDate: to,
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _fromDate = picked);
    await _loadSummary();
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _toDate = picked);
    await _loadSummary();
  }

  void _clearRange() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadSummary();
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String _formatDate(DateTime date) => DateFormat('dd-MMM-yyyy').format(date);

  @override
  Widget build(BuildContext context) {
    final usingToday = _fromDate == null && _toDate == null;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'ABSTRACT (ALL LOCATIONS)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFE8F5E8),
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CenteredContent(
              maxWidth: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CompactDateField(
                          label: 'From',
                          valueText: _fromDate == null
                              ? 'Today'
                              : _formatDate(_fromDate!),
                          onTap: _pickFromDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CompactDateField(
                          label: 'To',
                          valueText: _toDate == null
                              ? 'Today'
                              : _formatDate(_toDate!),
                          onTap: _pickToDate,
                        ),
                      ),
                      if (!usingToday) ...[
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _clearRange,
                          child: const Text(
                            'Today',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (usingToday)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No range selected — showing today across all locations.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  if (_dateRangeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _dateRangeError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _summaryRow(
                    'Total sales',
                    _formatMoney(_summary?.totalSaleAmount ?? 0),
                  ),
                  const SizedBox(height: 8),
                  _summaryRow(
                    'Total GST',
                    _formatMoney(_summary?.totalGst ?? 0),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
