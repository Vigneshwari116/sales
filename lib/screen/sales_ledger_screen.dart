import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';
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
  static const double _tableMinWidth = 920;

  bool _loading = true;
  bool _pulling = false;
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
    setState(() => _loading = true);

    final ({
      List<LocalLedgerEntry> entries,
      LedgerSummary summary,
    }) result;

    if (widget.loadLedgerOverride != null) {
      result = await widget.loadLedgerOverride!()!;
    } else {
      result = await LedgerRepository.getLedger(location: widget.location);
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

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

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
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'SALES LEDGER',
        automaticallyImplyLeading: !widget.embeddedInDashboard,
        actions: [
          if (_pulling)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.navy,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: () => _pullInBackground(showFeedback: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : CenteredContent(
                  maxWidth: 1100,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final needsHScroll =
                          constraints.maxWidth < _tableMinWidth;
                      final table = _buildTable();

                      if (!needsHScroll) {
                        return SingleChildScrollView(child: table);
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: SizedBox(
                            width: _tableMinWidth,
                            child: table,
                          ),
                        ),
                      );
                    },
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
            const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppColors.mutedBlue),
            const SizedBox(height: 16),
            Text(
              'No bills for ${widget.location}',
              style: const TextStyle(
                fontSize: AppTextSizes.sectionHeader,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.readOnly
                  ? 'Use Sync → Sync Location to pull bills from the server, or tap Refresh above.'
                  : 'Save bills on this device or open Sync to push pending bills.',
              style: const TextStyle(fontSize: AppTextSizes.listSubtitle),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
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

  bool get _hideTaxColumns => widget.embeddedInDashboard;

  Widget _headerRow() {
    return Container(
      color: AppColors.tableHeader,
      child: Row(
        children: [
          _cell('BILLNO', flex: 7, bold: true),
          _cell('DATE', flex: 8, bold: true),
          _cell('NAME', flex: 13, bold: true),
          _cell('MOBILE', flex: 11, bold: true),
          _cell('PAY', flex: 7, bold: true),
          _cell('TOTAL', flex: 8, bold: true, alignRight: true),
          if (!_hideTaxColumns) ...[
            _cell('CGST', flex: 7, bold: true, alignRight: true),
            _cell('SGST', flex: 7, bold: true, alignRight: true),
            _cell('IGST', flex: 7, bold: true, alignRight: true),
          ],
          _cell('GRAND TOTAL', flex: 9, bold: true, alignRight: true),
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
          _cell('${entry.billNo}', flex: 7),
          _cell(_formatDate(entry.date), flex: 8),
          _cell(entry.customerName, flex: 13),
          _cell(entry.mobile.isEmpty ? '—' : entry.mobile, flex: 11),
          _cell(entry.paymentMode, flex: 7),
          _cell(_formatMoney(entry.total), flex: 8, alignRight: true),
          if (!_hideTaxColumns) ...[
            _cell(_formatMoney(entry.cgst), flex: 7, alignRight: true),
            _cell(_formatMoney(entry.sgst), flex: 7, alignRight: true),
            _cell(_formatMoney(entry.igst), flex: 7, alignRight: true),
          ],
          _cell(_formatMoney(entry.grandTotal), flex: 9, alignRight: true),
        ],
      ),
    );
  }

  Widget _summaryRow() {
    final summary = _summary!;
    return Container(
      color: AppColors.headerBand,
      child: Row(
        children: [
          _cell('', flex: 7, bold: true),
          _cell('', flex: 8, bold: true),
          _cell('', flex: 13, bold: true),
          _cell('', flex: 11, bold: true),
          _cell('', flex: 7, bold: true),
          _cell(_formatMoney(summary.total),
              flex: 8, bold: true, alignRight: true),
          if (!_hideTaxColumns) ...[
            _cell(_formatMoney(summary.cgst),
                flex: 7, bold: true, alignRight: true),
            _cell(_formatMoney(summary.sgst),
                flex: 7, bold: true, alignRight: true),
            _cell(_formatMoney(summary.igst),
                flex: 7, bold: true, alignRight: true),
          ],
          _cell(_formatMoney(summary.grandTotal),
              flex: 9, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required int flex,
    bool bold = false,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.6),
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Text(
          text,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppTextSizes.tableRowText,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }
}
