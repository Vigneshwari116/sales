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

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  AbstractSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);

    var summary = await AbstractRepository.getSummaryForDate(
      location: widget.location,
      date: _selectedDate,
    );

    if (!mounted) return;

    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    var picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() => _selectedDate = picked);
    await _loadSummary();
  }

  String _formatMoney(double value) {
    return NumberFormat('#,##0.00').format(value);
  }

  String _formatSelectedDate() {
    return DateFormat('dd-MMM-yyyy').format(_selectedDate);
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
                  InkWell(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Date: ${_formatSelectedDate()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
