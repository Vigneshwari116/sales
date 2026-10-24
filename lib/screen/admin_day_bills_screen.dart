import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/repositories/ledger_repository.dart';
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

class _BillTableRow {
  final String localId;
  final String location;
  final int billNo;
  final String date;
  String customerName;
  String group;
  String mobile;
  String paymentMode;
  double pcs;
  double cash;
  double card;
  double total;
  double gst;
  double grandTotal;
  final String syncStatus;

  _BillTableRow({
    required this.localId,
    required this.location,
    required this.billNo,
    required this.date,
    required this.customerName,
    required this.group,
    required this.mobile,
    required this.paymentMode,
    required this.pcs,
    required this.cash,
    required this.card,
    required this.total,
    required this.gst,
    required this.grandTotal,
    required this.syncStatus,
  });

  factory _BillTableRow.fromDayBill(DayBillRow bill) {
    final isCash = bill.paymentMode.toUpperCase() == 'CASH';
    return _BillTableRow(
      localId: bill.localId,
      location: bill.location,
      billNo: bill.billNo,
      date: bill.date,
      customerName: bill.customerName,
      group: '',
      mobile: bill.mobile,
      paymentMode: bill.paymentMode,
      pcs: bill.totalQty,
      cash: isCash ? bill.grandTotal : 0,
      card: isCash ? 0 : bill.grandTotal,
      total: bill.total,
      gst: bill.gst,
      grandTotal: bill.grandTotal,
      syncStatus: bill.syncStatus,
    );
  }

  void applyAmounts({
    required double cashAmount,
    required double cardAmount,
  }) {
    cash = cashAmount;
    card = cardAmount;
    grandTotal = cashAmount + cardAmount;
    total = grandTotal / 1.05;
    gst = grandTotal - total;
  }
}

class _AdminDayBillsScreenState extends State<AdminDayBillsScreen> {
  static const double _tableMinWidth = 1020;

  bool _loading = true;
  List<_BillTableRow> _bills = const [];
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

  List<_BillTableRow> get _filteredBills {
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
      _bills = bills.map(_BillTableRow.fromDayBill).toList(growable: false);
      _loading = false;
    });
  }

  String _formatMoney(double value) => NumberFormat('#,##0.00').format(value);

  String _formatPcs(double value) => NumberFormat('#,##0.00').format(value);

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

  Future<void> _editBill(_BillTableRow row) async {
    if (!widget.adminFullEdit) {
      return;
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _BillEditDialog(
        row: row,
        onSave: () => _persistBill(row),
      ),
    );

    if (updated == true) {
      setState(() {});
    }
  }

  Future<void> _persistBill(_BillTableRow row) async {
    final loaded = widget.loadBillOverride != null
        ? await widget.loadBillOverride!(
            DayBillRow(
              localId: row.localId,
              location: row.location,
              billNo: row.billNo,
              date: row.date,
              customerName: row.customerName,
              mobile: row.mobile,
              paymentMode: row.paymentMode,
              totalQty: row.pcs,
              total: row.total,
              gst: row.gst,
              grandTotal: row.grandTotal,
              syncStatus: row.syncStatus,
            ),
          )
        : await LedgerRepository.getBillByLocalId(
            location: row.location,
            localId: row.localId,
          );

    if (!mounted) return;

    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load bill')),
      );
      return;
    }

    final paymentMode = _paymentModeForAmounts(
      cash: row.cash,
      card: row.card,
      previous: loaded.paymentMode,
    );

    final updatedBill = SaleBill(
      billNo: loaded.billNo,
      location: loaded.location,
      billDate: loaded.billDate,
      paymentMode: paymentMode,
      customerName: row.customerName,
      mobile: row.mobile,
      items: loaded.items,
      totalQty: row.pcs,
      totalAmount: row.total,
      totalCgst: row.gst / 2,
      totalSgst: row.gst / 2,
      totalIgst: 0,
      grandTotal: row.grandTotal,
    );

    final result = await BillRepository.saveBill(
      updatedBill,
      updateLocalId: row.localId,
    );

    if (!mounted) return;

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not save bill')),
      );
      return;
    }

    row.paymentMode = paymentMode;
  }

  static String _paymentModeForAmounts({
    required double cash,
    required double card,
    required String previous,
  }) {
    if (cash > 0 && card <= 0) {
      return 'CASH';
    }
    if (card > 0 && cash <= 0) {
      final upper = previous.toUpperCase();
      if (upper == 'CASH') {
        return 'CARD';
      }
      return previous;
    }
    if (cash > 0 && card > 0) {
      return 'CARD';
    }
    return previous;
  }

  ({double pcs, double cash, double card, double total, double gst, double grand})
      _totalsFor(List<_BillTableRow> rows) {
    var pcs = 0.0;
    var cash = 0.0;
    var card = 0.0;
    var total = 0.0;
    var gst = 0.0;
    var grand = 0.0;

    for (final row in rows) {
      pcs += row.pcs;
      cash += row.cash;
      card += row.card;
      total += row.total;
      gst += row.gst;
      grand += row.grandTotal;
    }

    return (
      pcs: pcs,
      cash: cash,
      card: card,
      total: total,
      gst: gst,
      grand: grand,
    );
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
                              maxWidth: 1200,
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

  Widget _buildTable(List<_BillTableRow> rows) {
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
          _cell('BILLNO', flex: 5, bold: true),
          _cell('DATE', flex: 6, bold: true),
          _cell('NAME', flex: 9, bold: true),
          _cell('GROUP', flex: 6, bold: true),
          _cell('MOBILE', flex: 7, bold: true),
          _cell('PCS', flex: 5, bold: true, alignRight: true),
          _cell('CASH', flex: 6, bold: true, alignRight: true),
          _cell('CARD/UPI', flex: 6, bold: true, alignRight: true),
          _cell('TOTAL', flex: 6, bold: true, alignRight: true),
          _cell('GST', flex: 5, bold: true, alignRight: true),
          _cell('GRAND TOTAL', flex: 7, bold: true, alignRight: true),
        ],
      ),
    );
  }

  Widget _dataRow(_BillTableRow row) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.adminFullEdit ? () => _editBill(row) : null,
      child: Row(
        children: [
          _cell('${row.billNo}', flex: 5),
          _cell(_formatDate(row.date), flex: 6),
          _cell(row.customerName, flex: 9),
          _cell(row.group, flex: 6),
          _cell(row.mobile.isEmpty ? '—' : row.mobile, flex: 7),
          _cell(_formatPcs(row.pcs), flex: 5, alignRight: true),
          _cell(_formatMoneyCell(row.cash), flex: 6, alignRight: true),
          _cell(_formatMoneyCell(row.card), flex: 6, alignRight: true),
          _cell(_formatMoney(row.total), flex: 6, alignRight: true),
          _cell(_formatMoney(row.gst), flex: 5, alignRight: true),
          _cell(_formatMoney(row.grandTotal), flex: 7, alignRight: true),
        ],
      ),
    );
  }

  Widget _summaryRow(
    ({
      double pcs,
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
          _cell('', flex: 5, bold: true),
          _cell('', flex: 6, bold: true),
          _cell('', flex: 9, bold: true),
          _cell('', flex: 6, bold: true),
          _cell('', flex: 7, bold: true),
          _cell(_formatPcs(totals.pcs), flex: 5, bold: true, alignRight: true),
          _cell(_formatMoney(totals.cash), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.card), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.total), flex: 6, bold: true, alignRight: true),
          _cell(_formatMoney(totals.gst), flex: 5, bold: true, alignRight: true),
          _cell(_formatMoney(totals.grand),
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

class _BillEditDialog extends StatefulWidget {
  final _BillTableRow row;
  final Future<void> Function() onSave;

  const _BillEditDialog({
    required this.row,
    required this.onSave,
  });

  @override
  State<_BillEditDialog> createState() => _BillEditDialogState();
}

class _BillEditDialogState extends State<_BillEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _pcsCtrl;
  late final TextEditingController _cashCtrl;
  late final TextEditingController _cardCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.row.customerName);
    _groupCtrl = TextEditingController(text: widget.row.group);
    _mobileCtrl = TextEditingController(text: widget.row.mobile);
    _pcsCtrl = TextEditingController(
      text: widget.row.pcs == widget.row.pcs.roundToDouble()
          ? widget.row.pcs.toStringAsFixed(0)
          : widget.row.pcs.toString(),
    );
    _cashCtrl = TextEditingController(
      text: widget.row.cash == 0 ? '' : widget.row.cash.toString(),
    );
    _cardCtrl = TextEditingController(
      text: widget.row.card == 0 ? '' : widget.row.card.toString(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    _mobileCtrl.dispose();
    _pcsCtrl.dispose();
    _cashCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pcs = double.tryParse(_pcsCtrl.text.trim());
    final cash = double.tryParse(_cashCtrl.text.trim()) ?? 0;
    final card = double.tryParse(_cardCtrl.text.trim()) ?? 0;

    if (pcs == null || pcs < 0) {
      _showError('Enter a valid piece count');
      return;
    }

    if (cash < 0 || card < 0) {
      _showError('Cash and Card/UPI cannot be negative');
      return;
    }

    if (cash + card <= 0) {
      _showError('Enter cash and/or Card/UPI amount');
      return;
    }

    setState(() => _saving = true);

    widget.row.customerName = _nameCtrl.text.trim();
    widget.row.group = _groupCtrl.text.trim();
    widget.row.mobile = _mobileCtrl.text.trim();
    widget.row.pcs = pcs;
    widget.row.applyAmounts(cashAmount: cash, cardAmount: card);

    await widget.onSave();

    if (!mounted) return;

    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit bill ${widget.row.billNo}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Name', _nameCtrl),
              _field('Group', _groupCtrl),
              _field('Mobile', _mobileCtrl, digitsOnly: true),
              _field('Pcs', _pcsCtrl, number: true),
              _field('Cash', _cashCtrl, number: true),
              _field('Card/UPI', _cardCtrl, number: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool number = false,
    bool digitsOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : digitsOnly
                ? TextInputType.phone
                : TextInputType.text,
        inputFormatters: [
          if (number)
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
