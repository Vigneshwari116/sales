import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';

class SalesLedgerScreen extends StatefulWidget {
  final String location;
  final bool autoRefreshOnOpen;
  final bool embeddedInDashboard;
  final bool readOnly;
  final int refreshGeneration;

  @visibleForTesting
  final Future<
      ({
        List<LocalLedgerEntry> entries,
        LedgerSummary summary,
      })>? Function()? loadLedgerOverride;

  @visibleForTesting
  final Future<SaleBill?> Function(String localId)? loadBillOverride;

  const SalesLedgerScreen({
    super.key,
    required this.location,
    this.autoRefreshOnOpen = true,
    this.embeddedInDashboard = false,
    this.readOnly = false,
    this.refreshGeneration = 0,
    this.loadLedgerOverride,
    this.loadBillOverride,
  });

  @override
  State<SalesLedgerScreen> createState() => _SalesLedgerScreenState();
}

class _SalesLedgerScreenState extends State<SalesLedgerScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _header = Color(0xFFFFF5C5);
  static const Color _border = Color(0xFF888888);
  static const Color _navSurface = Color(0xFFE8F5E8);

  bool _loading = true;
  bool _pulling = false;
  bool _pushing = false;
  List<LocalLedgerEntry> _entries = [];
  LedgerSummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadLedger();
    if (widget.autoRefreshOnOpen) {
      _pullInBackground();
    }
  }

  @override
  void didUpdateWidget(covariant SalesLedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location ||
        widget.refreshGeneration != oldWidget.refreshGeneration) {
      _loadLedger();
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

    await SyncService.instance.pullAdminUpdates(widget.location);

    if (!mounted) return;

    setState(() => _pulling = false);
    await _loadLedger();
  }

  Future<void> _syncNow() async {
    final allowed = await SyncGateService.confirmSync(context);
    if (!allowed || !mounted) return;

    setState(() => _pushing = true);

    final result = await SyncService.instance.manualSync(widget.location);

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

  Future<void> _viewBill(LocalLedgerEntry entry) async {
    final bill = widget.loadBillOverride != null
        ? await widget.loadBillOverride!(entry.localId)
        : await LedgerRepository.getBillByLocalId(entry.localId);

    if (!mounted) return;

    if (bill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load bill')),
      );
      return;
    }

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LedgerBillDetailScreen(
          bill: bill,
          localId: entry.localId,
          syncStatus: entry.syncStatus,
          readOnly: widget.readOnly,
        ),
      ),
    );

    if (updated == true) {
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
      appBar: widget.embeddedInDashboard
          ? AppBar(
              title: const Text(
                'SALES LEDGER',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              backgroundColor: _navSurface,
              foregroundColor: Colors.black,
              automaticallyImplyLeading: false,
              actions: _buildAppBarActions(),
            )
          : AppBar(
              title: const Text(
                'SALES LEDGER',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              backgroundColor: const Color(0xFFD5D8D5),
              foregroundColor: Colors.black,
              actions: _buildAppBarActions(),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
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
                ],
              ),
            ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      if (_pulling)
        const Padding(
          padding: EdgeInsets.only(right: 4),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      if (!widget.readOnly)
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
    ];
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
          _cell('MOBILE', 2, bold: true),
          _cell('PAY', 1, bold: true),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _viewBill(entry),
      child: Row(
        children: [
          _cell('${entry.billNo}', 1),
          _cell(_formatDate(entry.date), 1),
          _cell(entry.customerName, 2),
          _cell(entry.mobile.isEmpty ? '—' : entry.mobile, 2),
          _cell(entry.paymentMode, 1),
          _cell(_formatMoney(entry.total), 1, alignRight: true),
          _cell(_formatMoney(entry.cgst), 1, alignRight: true),
          _cell(_formatMoney(entry.sgst), 1, alignRight: true),
          _cell(_formatMoney(entry.igst), 1, alignRight: true),
          _cell(_formatMoney(entry.grandTotal), 1, alignRight: true),
        ],
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
