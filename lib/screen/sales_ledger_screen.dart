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
  static const double _deleteColumnWidth = 36;

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

  Future<void> _confirmDeleteBill(LocalLedgerEntry entry) async {
    var confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Delete bill #${entry.billNo}?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await LedgerRepository.deleteBill(entry.localId);
    await _loadLedger();
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
          _cell('SYNC', 70, bold: true),
          _cell('TOTAL', 90, bold: true, alignRight: true),
          _cell('CGST', 80, bold: true, alignRight: true),
          _cell('SGST', 80, bold: true, alignRight: true),
          _cell('IGST', 80, bold: true, alignRight: true),
          _cell('GRAND TOTAL', 110, bold: true, alignRight: true),
          SizedBox(width: _deleteColumnWidth, height: 32),
        ],
      ),
    );
  }

  Widget _dataRow(LocalLedgerEntry entry) {
    var row = Row(
      children: [
        _cell('${entry.billNo}', 80),
        _cell(_formatDate(entry.date), 90),
        _cell(entry.paymentMode, 80),
        _syncStatusCell(entry.syncStatus, 70),
        _cell(_formatMoney(entry.total), 90, alignRight: true),
        _cell(_formatMoney(entry.cgst), 80, alignRight: true),
        _cell(_formatMoney(entry.sgst), 80, alignRight: true),
        _cell(_formatMoney(entry.igst), 80, alignRight: true),
        _cell(_formatMoney(entry.grandTotal), 110, alignRight: true),
        _deleteCell(entry),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editBill(entry),
        child: row,
      ),
    );
  }

  Widget _deleteCell(LocalLedgerEntry entry) {
    return SizedBox(
      width: _deleteColumnWidth,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: const Icon(Icons.close, color: Colors.red, size: 18),
        tooltip: 'Delete bill',
        onPressed: () => _confirmDeleteBill(entry),
      ),
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
          _cell('', 70, bold: true),
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
          SizedBox(width: _deleteColumnWidth, height: 32),
        ],
      ),
    );
  }

  Widget _syncStatusCell(String syncStatus, double width) {
    var isPending = syncStatus == 'pending';

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: _border, width: 0.6),
          bottom: BorderSide(color: _border, width: 0.6),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isPending ? Colors.orange : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          if (isPending) ...[
            const SizedBox(width: 4),
            const Text(
              'Pending',
              style: TextStyle(fontSize: 9, color: Colors.orange),
            ),
          ],
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
