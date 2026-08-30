import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_edit_dialog.dart';

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
  bool _syncing = false;
  List<LocalLedgerEntry> _entries = [];
  LedgerSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadLedger();
    _syncInBackground();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _loading = true;
    });

    final result = await LedgerRepository.getLedger(
      location: widget.location,
    );

    if (!mounted) return;

    setState(() {
      _entries = result.entries;
      _summary = result.summary;
      _loading = false;
    });
  }

  Future<void> _syncInBackground() async {
    setState(() => _syncing = true);

    await LedgerRepository.syncWithServer(location: widget.location);

    if (!mounted) return;

    setState(() => _syncing = false);
    await _loadLedger();
  }

  Future<void> _refreshLedger() async {
    await _loadLedger();
    await _syncInBackground();
  }

  Future<void> _editBill(LocalLedgerEntry entry) async {
    var bill = await LedgerRepository.getBillByLocalId(entry.localId);

    if (!mounted) return;

    if (bill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load bill for editing')),
      );
      return;
    }

    var saved = await showDialog<bool>(
      context: context,
      builder: (_) => LedgerBillEditDialog(
        localId: entry.localId,
        bill: bill,
      ),
    );

    if (saved == true) {
      await _loadLedger();
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
          if (_syncing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: _refreshLedger,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: _buildTable(),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          _cell('BILLNO', 1, bold: true),
          _cell('DATE', 1, bold: true),
          _cell('NAME', 2, bold: true),
          _cell('', 1, bold: true),
          _cell('TOTAL', 1, bold: true, alignRight: true),
          _cell('CGST', 1, bold: true, alignRight: true),
          _cell('SGST', 1, bold: true, alignRight: true),
          _cell('IGST', 1, bold: true, alignRight: true),
          _cell('GRAND TOTAL', 1, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _dataRow(LocalLedgerEntry entry) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editBill(entry),
        child: Row(
          children: [
            _cell('${entry.billNo}', 1),
            _cell(_formatDate(entry.date), 1),
            _cell(entry.customerName, 2),
            _cell(entry.paymentMode, 1),
            _cell(_formatMoney(entry.total), 1, alignRight: true),
            _cell(_formatMoney(entry.cgst), 1, alignRight: true),
            _cell(_formatMoney(entry.sgst), 1, alignRight: true),
            _cell(_formatMoney(entry.igst), 1, alignRight: true),
            _cell(_formatMoney(entry.grandTotal), 1, alignRight: true),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow() {
    final summary = _summary!;
    return Container(
      color: const Color(0xFFE8F4E8),
      child: Row(
        children: [
          _cell('', 1, bold: true),
          _cell('', 1, bold: true),
          _cell('', 2, bold: true),
          _cell('', 1, bold: true),
          _cell(_formatMoney(summary.total), 1, bold: true, alignRight: true),
          _cell(_formatMoney(summary.cgst), 1, bold: true, alignRight: true),
          _cell(_formatMoney(summary.sgst), 1, bold: true, alignRight: true),
          _cell(_formatMoney(summary.igst), 1, bold: true, alignRight: true),
          _cell(
            _formatMoney(summary.grandTotal),
            1,
            bold: true,
            alignRight: true,
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text,
    int flex, {
    bool bold = false,
    bool alignRight = false,
  }) {
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
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
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
