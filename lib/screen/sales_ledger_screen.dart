import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/services/owner_delete_service.dart';
import 'package:sales/services/sync_service.dart';

class SalesLedgerScreen extends StatefulWidget {
  final String location;
  final bool autoRefreshOnOpen;

  /// When set (tests only), bypasses [LedgerRepository.getLedger].
  @visibleForTesting
  final Future<
      ({
        List<LocalLedgerEntry> entries,
        LedgerSummary summary,
      })>? Function()? loadLedgerOverride;

  const SalesLedgerScreen({
    super.key,
    required this.location,
    this.autoRefreshOnOpen = true,
    this.loadLedgerOverride,
  });

  @override
  State<SalesLedgerScreen> createState() => _SalesLedgerScreenState();
}

class _SalesLedgerScreenState extends State<SalesLedgerScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _header = Color(0xFFFFF5C5);
  static const Color _border = Color(0xFF888888);

  bool _loading = true;
  bool _pulling = false;
  bool _pushing = false;
  bool _showOwnerPasswordField = false;
  String? _ownerPasswordError;
  List<LocalLedgerEntry> _entries = [];
  LedgerSummary? _summary;

  final TextEditingController _ownerPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    OwnerDeleteService.instance.addListener(_onOwnerDeleteChanged);
    _loadLedger();
    if (widget.autoRefreshOnOpen) {
      _pullInBackground();
    }
  }

  @override
  void dispose() {
    OwnerDeleteService.instance.removeListener(_onOwnerDeleteChanged);
    _ownerPasswordController.dispose();
    super.dispose();
  }

  void _onOwnerDeleteChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadLedger() async {
    setState(() {
      _loading = true;
    });

    final ({
      List<LocalLedgerEntry> entries,
      LedgerSummary summary,
    }) result;

    if (widget.loadLedgerOverride != null) {
      result = await widget.loadLedgerOverride!()!;
    } else {
      result = await LedgerRepository.getLedger(
        location: widget.location,
      );
    }

    if (!mounted) return;

    setState(() {
      _entries = result.entries;
      _summary = result.summary;
      _loading = false;
    });
  }

  Future<void> _pullInBackground() async {
    setState(() => _pulling = true);

    await LedgerRepository.refreshFromServer(location: widget.location);

    if (!mounted) return;

    setState(() => _pulling = false);
    await _loadLedger();
  }

  Future<void> _syncNow() async {
    setState(() => _pushing = true);

    final result = await SyncService.instance.manualPush(widget.location);

    if (!mounted) return;

    setState(() => _pushing = false);
    await _loadLedger();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.summaryMessage)),
    );
  }

  Future<void> _refreshLedger() async {
    await _pullInBackground();
  }

  void _onOwnerUnlockDoubleTap() {
    if (OwnerDeleteService.instance.isDeleteEnabled) {
      return;
    }

    setState(() {
      _showOwnerPasswordField = true;
      _ownerPasswordError = null;
      _ownerPasswordController.clear();
    });
  }

  void _tryUnlockOwnerDelete() {
    final unlocked = OwnerDeleteService.instance.tryUnlockWithPassword(
      _ownerPasswordController.text,
    );

    if (!unlocked) {
      setState(() => _ownerPasswordError = 'Incorrect password');
      return;
    }

    setState(() {
      _showOwnerPasswordField = false;
      _ownerPasswordError = null;
      _ownerPasswordController.clear();
    });
  }

  Future<void> _deleteBill(LocalLedgerEntry entry) async {
    await LedgerRepository.softDeleteBill(entry.localId);
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
    final deleteEnabled = OwnerDeleteService.instance.isDeleteEnabled;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: GestureDetector(
          onDoubleTap: _onOwnerUnlockDoubleTap,
          child: const Text(
            'SALES LEDGER',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
        actions: [
          if (_pulling)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton.icon(
            onPressed: _pushing ? null : _syncNow,
            icon: _pushing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Sync Now'),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showOwnerPasswordField && !deleteEnabled)
                    _buildOwnerPasswordPrompt(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: _buildTable(deleteEnabled),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOwnerPasswordPrompt() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  flex: 2,
                  child: Text(
                    'Owner password',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ownerPasswordController,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => _tryUnlockOwnerDelete(),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _tryUnlockOwnerDelete,
                  child: const Text('Unlock'),
                ),
              ],
            ),
            if (_ownerPasswordError != null) ...[
              const SizedBox(height: 6),
              Text(
                _ownerPasswordError!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTable(bool deleteEnabled) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(deleteEnabled),
          ..._entries.map((entry) => _dataRow(entry, deleteEnabled)),
          if (_summary != null) _summaryRow(deleteEnabled),
        ],
      ),
    );
  }

  Widget _headerRow(bool deleteEnabled) {
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
          if (deleteEnabled) _deleteHeaderCell(),
        ],
      ),
    );
  }

  Widget _dataRow(LocalLedgerEntry entry, bool deleteEnabled) {
    return Row(
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
        if (deleteEnabled) _deleteCell(entry),
      ],
    );
  }

  Widget _summaryRow(bool deleteEnabled) {
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
          if (deleteEnabled) _deleteHeaderCell(),
        ],
      ),
    );
  }

  Widget _deleteHeaderCell() {
    return SizedBox(
      width: 34,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: _border, width: 0.6),
            bottom: BorderSide(color: _border, width: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _deleteCell(LocalLedgerEntry entry) {
    return SizedBox(
      width: 34,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: _border, width: 0.6),
            bottom: BorderSide(color: _border, width: 0.6),
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Text(
            'X',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          tooltip: 'Delete bill',
          onPressed: () => _deleteBill(entry),
        ),
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
