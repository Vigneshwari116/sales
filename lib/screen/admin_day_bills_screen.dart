import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// One day of bills shown as a ledger-style table (admin drill-down).
class AdminDayBillsScreen extends StatefulWidget {
  final String day;
  final String title;
  final String? location;
  final bool adminFullEdit;

  @visibleForTesting
  final Future<List<DayBillRow>> Function()? loadBillsOverride;

  @visibleForTesting
  final Future<SaleBill?> Function(DayBillRow bill)? loadBillOverride;

  const AdminDayBillsScreen({
    super.key,
    required this.day,
    required this.title,
    this.location,
    this.adminFullEdit = true,
    this.loadBillsOverride,
    this.loadBillOverride,
  });

  @override
  State<AdminDayBillsScreen> createState() => _AdminDayBillsScreenState();
}

class _AdminDayBillsScreenState extends State<AdminDayBillsScreen> {
  static const double _tableMinWidth = 860;

  bool _loading = true;
  List<DayBillRow> _bills = const [];
  final TextEditingController _minAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBills();
    _minAmountController.addListener(_onMinAmountChanged);
  }

  @override
  void dispose() {
    _minAmountController.removeListener(_onMinAmountChanged);
    _minAmountController.dispose();
    super.dispose();
  }

  void _onMinAmountChanged() {
    setState(() {});
  }

  double? get _minAmountFilter {
    final text = _minAmountController.text.trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  List<DayBillRow> get _filteredBills {
    final minAmount = _minAmountFilter;
    if (minAmount == null) {
      return _bills;
    }
    return _bills
        .where((bill) => bill.grandTotal >= minAmount)
        .toList(growable: false);
  }

  Future<void> _loadBills() async {
    setState(() => _loading = true);

    final bills = widget.loadBillsOverride != null
        ? await widget.loadBillsOverride!()
        : await DayDrillDownRepository.getBillsForDay(
            day: widget.day,
            location: widget.location,
          );

    if (!mounted) return;

    setState(() {
      _bills = bills;
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String _formatMoneyCell(double value) {
    if (value == 0) {
      return '';
    }
    return _formatMoney(value);
  }

  String _formatDate(String value) {
    try {
      return DateFormat('dd-MMM-yy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  bool _isCashPayment(String mode) => mode.toUpperCase() == 'CASH';

  String _paymentColumnAmount(DayBillRow bill, {required bool cash}) {
    if (_isCashPayment(bill.paymentMode) != cash) {
      return '';
    }
    return _formatMoney(bill.grandTotal);
  }

  Future<void> _openBill(DayBillRow bill) async {
    final loaded = widget.loadBillOverride != null
        ? await widget.loadBillOverride!(bill)
        : await LedgerRepository.getBillByLocalId(
            location: bill.location,
            localId: bill.localId,
          );

    if (!mounted) return;

    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load bill')),
      );
      return;
    }

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LedgerBillDetailScreen(
          bill: loaded,
          localId: bill.localId,
          syncStatus: bill.syncStatus,
          readOnly: !widget.adminFullEdit,
          adminFullEdit: widget.adminFullEdit,
        ),
      ),
    );

    if (updated == true) {
      await _loadBills();
    }
  }

  ({double cash, double card, double total, double gst, double grand})
      _totalsFor(List<DayBillRow> rows) {
    var cash = 0.0;
    var card = 0.0;
    var total = 0.0;
    var gst = 0.0;
    var grand = 0.0;

    for (final row in rows) {
      if (_isCashPayment(row.paymentMode)) {
        cash += row.grandTotal;
      } else {
        card += row.grandTotal;
      }
      total += row.total;
      gst += row.gst;
      grand += row.grandTotal;
    }

    return (cash: cash, card: card, total: total, gst: gst, grand: grand);
  }

  @override
  Widget build(BuildContext context) {
    final filteredBills = _filteredBills;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        widget.title,
        automaticallyImplyLeading: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
              ? const Center(
                  child: Text(
                    'No bills for this day',
                    style: TextStyle(color: AppColors.mutedBlue),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAmountFilterBar(),
                    Expanded(
                      child: filteredBills.isEmpty
                          ? Center(
                              child: Text(
                                _minAmountFilter == null
                                    ? 'No bills for this day'
                                    : 'No bills with amount '
                                        '${_formatMoney(_minAmountFilter!)} or above',
                                style: const TextStyle(
                                  color: AppColors.mutedBlue,
                                ),
                              ),
                            )
                          : CenteredContent(
                              maxWidth: 1100,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final needsHScroll =
                                      constraints.maxWidth < _tableMinWidth;
                                  final table = _buildTable(filteredBills);

                                  if (!needsHScroll) {
                                    return table;
                                  }

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: _tableMinWidth,
                                      height: constraints.maxHeight,
                                      child: table,
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

  Widget _buildAmountFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          const Text(
            'Min amount:',
            style: TextStyle(
              fontSize: AppTextSizes.fieldLabel,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _minAmountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'e.g. 2000',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: AppTextSizes.fieldText),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _minAmountFilter == null
                  ? 'Showing all ${_bills.length} bills'
                  : 'Showing ${_filteredBills.length} of ${_bills.length} bills '
                      '(>= ${_formatMoney(_minAmountFilter!)})',
              style: const TextStyle(
                fontSize: AppTextSizes.listSubtitle,
                color: AppColors.mutedBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<DayBillRow> rows) {
    final totals = _totalsFor(rows);

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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: rows.map(_dataRow).toList(growable: false),
              ),
            ),
          ),
          _summaryRow(totals),
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
          _cell('CASH', flex: 7, bold: true, alignRight: true),
          _cell('CARD/UPI', flex: 7, bold: true, alignRight: true),
          _cell('TOTAL', flex: 7, bold: true, alignRight: true),
          _cell('GST', flex: 6, bold: true, alignRight: true),
          _cell('GRAND TOTAL', flex: 8, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _dataRow(DayBillRow row) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openBill(row),
      child: Row(
        children: [
          _cell('${row.billNo}', flex: 6),
          _cell(_formatDate(row.date), flex: 7),
          _cell(row.customerName, flex: 10),
          _cell(row.mobile.isEmpty ? '—' : row.mobile, flex: 8),
          _cell(_paymentColumnAmount(row, cash: true),
              flex: 7, alignRight: true),
          _cell(_paymentColumnAmount(row, cash: false),
              flex: 7, alignRight: true),
          _cell(_formatMoney(row.total), flex: 7, alignRight: true),
          _cell(_formatMoney(row.gst), flex: 6, alignRight: true),
          _cell(_formatMoney(row.grandTotal), flex: 8, alignRight: true),
        ],
      ),
    );
  }

  Widget _summaryRow(
    ({
      double cash,
      double card,
      double total,
      double gst,
      double grand
    }) totals,
  ) {
    return Container(
      color: AppColors.headerBand,
      child: Row(
        children: [
          _cell('', flex: 6, bold: true),
          _cell('', flex: 7, bold: true),
          _cell('', flex: 10, bold: true),
          _cell('', flex: 8, bold: true),
          _cell(_formatMoney(totals.cash), flex: 7, bold: true, alignRight: true),
          _cell(_formatMoney(totals.card), flex: 7, bold: true, alignRight: true),
          _cell(_formatMoney(totals.total), flex: 7, bold: true, alignRight: true),
          _cell(_formatMoney(totals.gst), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.grand),
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
