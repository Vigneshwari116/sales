import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/services/ledger_pdf_service.dart';
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
  static const double _tableMinWidth = 760;

  bool _loading = true;
  bool _pulling = false;
  bool _exportingPdf = false;
  List<LocalLedgerEntry> _entries = [];
  LedgerSummary? _summary;
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  bool _customRange = false;

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

  String? get _fromKey => _dateKey(_fromDate);
  String? get _toKey => _dateKey(_toDate);

  String? _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
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
      result = await LedgerRepository.getLedger(
        location: widget.location,
        from: _fromKey,
        to: _toKey,
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

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _fromDate = now;
      _toDate = now;
      _customRange = false;
    });
    _loadLedger();
  }

  Future<void> _exportPdf() async {
    if (_entries.isEmpty || _summary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No ledger rows to export')),
      );
      return;
    }

    setState(() => _exportingPdf = true);

    try {
      final path = await LedgerPdfService.saveLedgerPdf(
        location: widget.location,
        entries: _entries,
        summary: _summary!,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ledger PDF saved: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save ledger PDF: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
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

  double _entryGst(LocalLedgerEntry entry) =>
      entry.cgst + entry.sgst + entry.igst;

  double _summaryGst(LedgerSummary summary) =>
      summary.cgst + summary.sgst + summary.igst;

  String get _periodLabel {
    if (!_customRange) {
      return 'Today — ${DateFormat('dd MMM yyyy').format(DateTime.now())}';
    }
    final from = DateFormat('dd MMM yyyy').format(_fromDate);
    final to = DateFormat('dd MMM yyyy').format(_toDate);
    return from == to ? from : '$from — $to';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'SALES LEDGER',
        automaticallyImplyLeading: !widget.embeddedInDashboard,
        actions: [
          if (_exportingPdf)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              key: const Key('ledger_save_pdf_button'),
              onPressed: _entries.isEmpty ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Save as PDF',
            ),
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _periodLabel,
                        style: const TextStyle(
                          fontSize: AppTextSizes.listTitle,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                      DateRangeButton(
                        fromDate: _fromDate,
                        toDate: _toDate,
                        onChanged: (range) {
                          setState(() {
                            _fromDate = range.start;
                            _toDate = range.end;
                            _customRange = true;
                          });
                          _loadLedger();
                        },
                      ),
                      OutlinedButton(
                        onPressed: _setToday,
                        child: const Text('TODAY'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _entries.isEmpty
                      ? _buildEmptyState()
                      : CenteredContent(
                          maxWidth: 1100,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                ),
              ],
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
              _customRange
                  ? 'No bills in the selected date range.'
                  : 'No bills saved today. Use DATE RANGE to view older bills.',
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

  Widget _headerRow() {
    return Container(
      color: AppColors.tableHeader,
      child: Row(
        children: [
          _cell('BILLNO', flex: 6, bold: true),
          _cell('DATE', flex: 7, bold: true),
          _cell('NAME', flex: 10, bold: true),
          _cell('MOBILE', flex: 8, bold: true),
          _cell('PAY', flex: 6, bold: true),
          _cell('TOTAL', flex: 7, bold: true, alignRight: true),
          _cell('GST', flex: 6, bold: true, alignRight: true),
          _cell('GRAND TOTAL', flex: 8, bold: true, alignRight: true),
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
          _cell('${entry.billNo}', flex: 6),
          _cell(_formatDate(entry.date), flex: 7),
          _cell(entry.customerName, flex: 10),
          _cell(entry.mobile.isEmpty ? '—' : entry.mobile, flex: 8),
          _cell(LedgerPdfService.formatPayMode(entry.paymentMode), flex: 6),
          _cell(_formatMoney(entry.total), flex: 7, alignRight: true),
          _cell(_formatMoney(_entryGst(entry)), flex: 6, alignRight: true),
          _cell(_formatMoney(entry.grandTotal), flex: 8, alignRight: true),
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
          _cell('', flex: 6, bold: true),
          _cell('', flex: 7, bold: true),
          _cell('', flex: 10, bold: true),
          _cell('', flex: 8, bold: true),
          _cell('', flex: 6, bold: true),
          _cell(_formatMoney(summary.total),
              flex: 7, bold: true, alignRight: true),
          _cell(_formatMoney(_summaryGst(summary)),
              flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(summary.grandTotal),
              flex: 8, bold: true, alignRight: true),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
            fontSize: 9,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }
}
