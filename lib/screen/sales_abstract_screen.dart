import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/abstract_repository.dart';

class SalesAbstractScreen extends StatefulWidget {
  final String location;

  const SalesAbstractScreen({
    super.key,
    required this.location,
  });

  @override
  State<SalesAbstractScreen> createState() => _SalesAbstractScreenState();
}

class _SalesAbstractScreenState extends State<SalesAbstractScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _border = Color(0xFF888888);

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

  Future<void> _pickFromDate() async {
    var picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _fromDate = picked);
    await _loadSummary();
  }

  Future<void> _pickToDate() async {
    var picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _toDate = picked);
    await _loadSummary();
  }

  String _formatMoney(double value) {
    return NumberFormat('#,##0.00').format(value);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  Widget _datePickerRow({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 10),
            Text(
              '$label: ${_formatDate(date)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SALES ABSTRACT',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _datePickerRow(
                    label: 'From Date',
                    date: _fromDate,
                    onTap: _pickFromDate,
                  ),
                  const SizedBox(height: 10),
                  _datePickerRow(
                    label: 'To Date',
                    date: _toDate,
                    onTap: _pickToDate,
                  ),
                  if (_dateRangeError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _dateRangeError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _summaryRow(
                    'Total Sale Amount',
                    _formatMoney(_summary?.totalSaleAmount ?? 0),
                  ),
                  const SizedBox(height: 10),
                  _summaryRow(
                    'Total GST',
                    _formatMoney(_summary?.totalGst ?? 0),
                  ),
                  const SizedBox(height: 10),
                  _summaryRow(
                    'Grand Total',
                    _formatMoney(_summary?.grandTotal ?? 0),
                    bold: true,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 18 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
