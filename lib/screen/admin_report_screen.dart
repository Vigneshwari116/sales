import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/repositories/report_repository.dart';
import 'package:sales/services/report_excel_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Admin cross-location bill report with Excel export.
class AdminReportScreen extends StatefulWidget {
  @visibleForTesting
  final Future<ReportBreakdown> Function({
    required DateTime fromDate,
    required DateTime toDate,
  })? loadBreakdownOverride;

  const AdminReportScreen({
    super.key,
    this.loadBreakdownOverride,
  });

  @override
  State<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends State<AdminReportScreen> {
  static const double _tableMinWidth = 1000;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  bool _loading = true;
  bool _exporting = false;
  String? _dateRangeError;
  ReportBreakdown? _breakdown;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  bool get _isDateRangeValid {
    final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final to = DateTime(_toDate.year, _toDate.month, _toDate.day);
    return !to.isBefore(from);
  }

  Future<void> _loadReport() async {
    if (!_isDateRangeValid) {
      setState(() {
        _loading = false;
        _dateRangeError = 'To Date cannot be before From Date';
        _breakdown = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _dateRangeError = null;
    });

    final breakdown = widget.loadBreakdownOverride != null
        ? await widget.loadBreakdownOverride!(
            fromDate: _fromDate,
            toDate: _toDate,
          )
        : await ReportRepository.getBreakdown(
            fromDate: _fromDate,
            toDate: _toDate,
          );

    if (!mounted) return;

    setState(() {
      _breakdown = breakdown;
      _loading = false;
    });
  }

  void _setToday() {
    final now = DateTime.now();
    setState(() {
      _fromDate = now;
      _toDate = now;
    });
    _loadReport();
  }

  Future<void> _exportExcel() async {
    final breakdown = _breakdown;
    if (breakdown == null || breakdown.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report rows to export')),
      );
      return;
    }

    setState(() => _exporting = true);

    try {
      final path = await ReportExcelService.saveAndShareReport(
        breakdown: breakdown,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export report: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
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

  String _paymentColumnAmount(ReportBillRow row, {required bool cash}) {
    if (row.isCashPayment != cash) {
      return '';
    }
    return _formatMoney(row.grandTotal);
  }

  String get _periodLabel {
    final from = DateFormat('dd MMM yyyy').format(_fromDate);
    final to = DateFormat('dd MMM yyyy').format(_toDate);
    return from == to ? from : '$from — $to';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'REPORT',
        actions: [
          if (_exporting)
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
              key: const Key('admin_report_export_excel_button'),
              onPressed: _breakdown == null ? null : _exportExcel,
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export to Excel',
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
                          });
                          _loadReport();
                        },
                      ),
                      OutlinedButton(
                        onPressed: _setToday,
                        child: const Text('TODAY'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('admin_report_export_excel_text_button'),
                        onPressed: _exporting || _breakdown == null
                            ? null
                            : _exportExcel,
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: const Text('EXPORT TO EXCEL'),
                      ),
                    ],
                  ),
                ),
                if (_dateRangeError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      _dateRangeError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: AppTextSizes.listTitle,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _breakdown == null
                      ? const SizedBox.shrink()
                      : _breakdown!.rows.isEmpty
                          ? _buildEmptyState()
                          : CenteredContent(
                              maxWidth: 1200,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final needsHScroll =
                                      constraints.maxWidth < _tableMinWidth;
                                  final table = _buildTable(_breakdown!);

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
            const Text(
              'No bills in selected range',
              style: TextStyle(
                fontSize: AppTextSizes.sectionHeader,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'All locations — $_periodLabel',
              style: const TextStyle(fontSize: AppTextSizes.listSubtitle),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ReportBreakdown breakdown) {
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
          ...breakdown.rows.map(_dataRow),
          _grandTotalRow(breakdown.grandTotal),
        ],
      ),
    );
  }

  Widget _headerRow() {
    return Container(
      color: AppColors.tableHeader,
      child: Row(
        children: [
          _cell('BILLNO', flex: 5, bold: true),
          _cell('DATE', flex: 6, bold: true),
          _cell('NAME', flex: 9, bold: true),
          _cell('MOBILE', flex: 7, bold: true),
          _cell('CASH', flex: 6, bold: true, alignRight: true),
          _cell('CARD/UPI', flex: 6, bold: true, alignRight: true),
          _cell('TOTAL', flex: 6, bold: true, alignRight: true),
          _cell('CGST', flex: 5, bold: true, alignRight: true),
          _cell('SGST/IGST', flex: 6, bold: true, alignRight: true),
          _cell('GRAND TOTAL', flex: 7, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _dataRow(ReportBillRow row) {
    return Row(
      children: [
        _cell('${row.billNo}', flex: 5),
        _cell(_formatDate(row.date), flex: 6),
        _cell(row.customerName, flex: 9),
        _cell(row.mobile.isEmpty ? '—' : row.mobile, flex: 7),
        _cell(_paymentColumnAmount(row, cash: true),
            flex: 6, alignRight: true),
        _cell(_paymentColumnAmount(row, cash: false),
            flex: 6, alignRight: true),
        _cell(_formatMoney(row.total), flex: 6, alignRight: true),
        _cell(_formatMoney(row.cgst), flex: 5, alignRight: true),
        _cell(_formatMoney(row.sgstIgst), flex: 6, alignRight: true),
        _cell(_formatMoney(row.grandTotal), flex: 7, alignRight: true),
      ],
    );
  }

  Widget _grandTotalRow(ReportTotals totals) {
    return Container(
      color: AppColors.headerBand,
      child: Row(
        children: [
          _cell('', flex: 5, bold: true),
          _cell('', flex: 6, bold: true),
          _cell('', flex: 9, bold: true),
          _cell('Grand Total', flex: 7, bold: true),
          _cell(_formatMoney(totals.cash), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.card), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.total), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.cgst), flex: 5, bold: true, alignRight: true),
          _cell(_formatMoney(totals.sgstIgst),
              flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.grandTotal),
              flex: 7, bold: true, alignRight: true),
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
