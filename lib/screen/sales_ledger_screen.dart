import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/widgets/compact_layout.dart';

class SalesLedgerScreen extends StatefulWidget {
  final String location;
  final bool autoRefreshOnOpen;
  final bool embeddedInDashboard;
  final bool readOnly;
  final bool adminFullEdit;
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
    this.adminFullEdit = false,
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
  static const double _tableMinWidth = 980;

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

  Future<void> _pullInBackground({bool showFeedback = false}) async {
    setState(() => _pulling = true);

    final result = await SyncService.instance.pullAdminUpdates(widget.location);

    if (!mounted) return;

    setState(() => _pulling = false);
    await _loadLedger();

    if (!mounted || !showFeedback) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? 'Pulled ${result.pulledCount} bill update(s) for ${widget.location}'
              : 'Pull failed: ${result.error ?? "unknown error"}',
        ),
      ),
    );
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
    await _pullInBackground(showFeedback: true);
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
          readOnly: widget.readOnly && !widget.adminFullEdit,
          adminFullEdit: widget.adminFullEdit,
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
          : _entries.isEmpty
              ? _buildEmptyState()
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final tableWidth =
                              constraints.maxWidth > _tableMinWidth
                                  ? constraints.maxWidth
                                  : _tableMinWidth;

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: SizedBox(
                                width: tableWidth,
                                child: _buildTable(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            Text(
              'No bills for ${widget.location}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.readOnly
                  ? 'Use Sync → Sync Location to pull bills from the server, or tap Refresh above.'
                  : 'Save bills on this device or tap Sync Now to push pending bills.',
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
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
          _cell('BILLNO', 70, bold: true),
          _cell('DATE', 80, bold: true),
          _cell('NAME', 130, bold: true),
          _cell('MOBILE', 110, bold: true),
          _cell('PAY', 70, bold: true),
          _cell('TOTAL', 80, bold: true, alignRight: true),
          _cell('CGST', 70, bold: true, alignRight: true),
          _cell('SGST', 70, bold: true, alignRight: true),
          _cell('IGST', 70, bold: true, alignRight: true),
          _cell('GRAND TOTAL', 90, bold: true, alignRight: true),
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
          _cell('${entry.billNo}', 70),
          _cell(_formatDate(entry.date), 80),
          _cell(entry.customerName, 130),
          _cell(entry.mobile.isEmpty ? '—' : entry.mobile, 110),
          _cell(entry.paymentMode, 70),
          _cell(_formatMoney(entry.total), 80, alignRight: true),
          _cell(_formatMoney(entry.cgst), 70, alignRight: true),
          _cell(_formatMoney(entry.sgst), 70, alignRight: true),
          _cell(_formatMoney(entry.igst), 70, alignRight: true),
          _cell(_formatMoney(entry.grandTotal), 90, alignRight: true),
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
          _cell('', 70, bold: true),
          _cell('', 80, bold: true),
          _cell('', 130, bold: true),
          _cell('', 110, bold: true),
          _cell('', 70, bold: true),
          _cell(_formatMoney(summary.total), 80, bold: true, alignRight: true),
          _cell(_formatMoney(summary.cgst), 70, bold: true, alignRight: true),
          _cell(_formatMoney(summary.sgst), 70, bold: true, alignRight: true),
          _cell(_formatMoney(summary.igst), 70, bold: true, alignRight: true),
          _cell(
            _formatMoney(summary.grandTotal),
            90,
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
    return SizedBox(
      width: width,
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
