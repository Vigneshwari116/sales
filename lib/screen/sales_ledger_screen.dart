import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';

class SalesLedgerScreen extends StatefulWidget {
  final String location;

  const SalesLedgerScreen({
    super.key,
    required this.location,
  });

  @override
  State<SalesLedgerScreen> createState() => _SalesLedgerScreenState();
}

class _SalesLedgerScreenState extends State<SalesLedgerScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _header = Color(0xFFFFF5C5);
  static const Color _border = Color(0xFF888888);

  bool _loading = true;
  String? _error;
  List<LedgerEntry> _entries = [];
  LedgerSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await SalesApi.getLedger(location: widget.location);

    if (!mounted) return;

    if (result.ok && result.data != null) {
      setState(() {
        _entries = result.data!.entries;
        _summary = result.data!.summary;
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.error ?? 'Could not load ledger';
        _loading = false;
      });
    }
  }

  String _formatMoney(double value) {
    return NumberFormat('#,##0.00').format(value);
  }

  String _formatDate(String value) {
    try {
      final date = DateTime.parse(value);
      return DateFormat('dd-MMM-yy').format(date);
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SALES LEDGER',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _loadLedger,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadLedger,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        widget.location,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: _buildTable(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(),
          ..._entries.map(_dataRow),
          if (_summary != null) _summaryRow(),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: _header,
      child: Row(
        children: [
          _cell('BILLNO', 80, bold: true),
          _cell('DATE', 90, bold: true),
          _cell('', 80, bold: true),
          _cell('TOTAL', 90, bold: true, alignRight: true),
          _cell('CGST', 80, bold: true, alignRight: true),
          _cell('SGST', 80, bold: true, alignRight: true),
          _cell('IGST', 80, bold: true, alignRight: true),
          _cell('GRAND TOTAL', 110, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _dataRow(LedgerEntry entry) {
    return Row(
      children: [
        _cell('${entry.billNo}', 80),
        _cell(_formatDate(entry.date), 90),
        _cell(entry.paymentMode, 80),
        _cell(_formatMoney(entry.total), 90, alignRight: true),
        _cell(_formatMoney(entry.cgst), 80, alignRight: true),
        _cell(_formatMoney(entry.sgst), 80, alignRight: true),
        _cell(_formatMoney(entry.igst), 80, alignRight: true),
        _cell(_formatMoney(entry.grandTotal), 110, alignRight: true),
      ],
    );
  }

  Widget _summaryRow() {
    final summary = _summary!;
    return Container(
      color: const Color(0xFFE8F4E8),
      child: Row(
        children: [
          _cell('', 80, bold: true),
          _cell('', 90, bold: true),
          _cell('', 80, bold: true),
          _cell(_formatMoney(summary.total), 90, bold: true, alignRight: true),
          _cell(_formatMoney(summary.cgst), 80, bold: true, alignRight: true),
          _cell(_formatMoney(summary.sgst), 80, bold: true, alignRight: true),
          _cell(_formatMoney(summary.igst), 80, bold: true, alignRight: true),
          _cell(
            _formatMoney(summary.grandTotal),
            110,
            bold: true,
            alignRight: true,
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text,
    double width, {
    bool bold = false,
    bool alignRight = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _border, width: 0.6),
          bottom: BorderSide(color: _border, width: 0.6),
        ),
      ),
      child: Text(
        text,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
