import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/ledger_repository.dart';

/// Lists saved bills with customer mobile numbers from LocalDb.
class SalesReportsScreen extends StatefulWidget {
  final String location;
  final int refreshGeneration;

  const SalesReportsScreen({
    super.key,
    required this.location,
    this.refreshGeneration = 0,
  });

  @override
  State<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends State<SalesReportsScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _header = Color(0xFFFFF5C5);
  static const Color _border = Color(0xFF888888);
  static const Color _navSurface = Color(0xFFE8F5E8);

  bool _loading = true;
  List<LocalLedgerEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SalesReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshGeneration != oldWidget.refreshGeneration ||
        widget.location != oldWidget.location) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final result = await LedgerRepository.getLedger(location: widget.location);

    if (!mounted) return;

    setState(() {
      _entries = result.entries;
      _loading = false;
    });
  }

  String _formatDate(String value) {
    try {
      return DateFormat('dd-MMM-yy').format(DateTime.parse(value));
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
          'REPORTS',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: _navSurface,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Customer mobile numbers from local bills',
                    style: TextStyle(fontSize: 12),
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
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _header,
            child: Row(
              children: [
                _cell('BILL NO', 1, bold: true),
                _cell('DATE', 1, bold: true),
                _cell('NAME', 2, bold: true),
                _cell('MOBILE', 2, bold: true),
              ],
            ),
          ),
          if (_entries.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No bills found in local database.',
                style: TextStyle(fontSize: 12),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return Row(
                    children: [
                      _cell('${entry.billNo}', 1),
                      _cell(_formatDate(entry.date), 1),
                      _cell(entry.customerName, 2),
                      _cell(
                        entry.mobile.isEmpty ? '—' : entry.mobile,
                        2,
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, int flex, {bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: _border, width: 0.6),
            bottom: BorderSide(color: _border, width: 0.6),
          ),
        ),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
