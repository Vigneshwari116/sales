import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:sales/config/local_credentials.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/utils/bill_totals.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Drill-down for a saved bill — password-gated edit for staff.
class LedgerBillDetailScreen extends StatefulWidget {
  final SaleBill bill;
  final String localId;
  final String? syncStatus;
  final bool readOnly;
  final bool adminFullEdit;

  const LedgerBillDetailScreen({
    super.key,
    required this.bill,
    required this.localId,
    this.syncStatus,
    this.readOnly = false,
    this.adminFullEdit = false,
  });

  static const Color billNoColor = Color(0xFFFFE5A0);

  static const List<String> paymentModes = ['CASH', 'CARD', 'UPI'];

  @override
  State<LedgerBillDetailScreen> createState() => _LedgerBillDetailScreenState();
}

class _LedgerBillDetailScreenState extends State<LedgerBillDetailScreen> {
  late SaleBill _bill;
  late List<BillItem> _items;
  late String _paymentMode;
  String? _syncStatus;

  bool _editUnlocked = false;
  bool _saving = false;
  bool _canPersistOnDevice = false;
  bool _checkedPersist = false;
  int? _editingIndex;

  final _passwordCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _grandTotalCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
    _items = widget.bill.items.map((e) => e.copyWith()).toList();
    _paymentMode = _normalizePaymentMode(widget.bill.paymentMode);
    _syncStatus = widget.syncStatus;
    _customerNameCtrl.text = _bill.customerName;
    _mobileCtrl.text = _bill.mobile;
    _syncSummaryFields();
    _loadPersistEligibility();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _rateCtrl.dispose();
    _qtyCtrl.dispose();
    _customerNameCtrl.dispose();
    _mobileCtrl.dispose();
    _amountCtrl.dispose();
    _gstCtrl.dispose();
    _grandTotalCtrl.dispose();
    super.dispose();
  }

  String _normalizePaymentMode(String mode) {
    final upper = mode.toUpperCase();
    if (upper == 'CASH') {
      return 'CASH';
    }
    if (upper == 'UPI') {
      return 'UPI';
    }
    return 'CARD';
  }

  Future<void> _loadPersistEligibility() async {
    final canPersist =
        await BillRepository.canUpdateBillOnDevice(_bill.location);
    if (!mounted) return;
    setState(() {
      _canPersistOnDevice = canPersist;
      _checkedPersist = true;
    });
  }

  String _format(num value) => NumberFormat('#,##0.00').format(value);

  String _formatDate(DateTime date) => DateFormat('dd-MMM-yy').format(date);

  BillTotals _computedTotals() {
    if (_items.isNotEmpty) {
      return BillTotals.fromItems(_items);
    }

    return BillTotals(
      totalQty: _bill.totalQty,
      totalAmount: _bill.totalAmount,
      totalCgst: _bill.totalCgst,
      totalSgst: _bill.totalSgst,
      totalIgst: _bill.totalIgst,
      grandTotal: _bill.grandTotal,
    );
  }

  void _syncSummaryFields() {
    final totals = _computedTotals();
    _amountCtrl.text = _format(totals.totalAmount);
    _gstCtrl.text = _format(totals.totalGst);
    _grandTotalCtrl.text = _format(totals.grandTotal);
  }

  Future<void> _onEditPressed() async {
    if (widget.readOnly) {
      return;
    }

    if (!_canPersistOnDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Edit this bill from its own location'),
        ),
      );
      return;
    }

    if (widget.adminFullEdit) {
      setState(() => _editUnlocked = true);
      return;
    }

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (context) => _PasswordDialog(controller: _passwordCtrl),
    );

    if (unlocked == true && mounted) {
      setState(() => _editUnlocked = true);
    }
  }

  void _startEditLine(int index) {
    if (!_editUnlocked) return;

    setState(() {
      _editingIndex = index;
      _rateCtrl.text = _items[index].rate.toString();
      _qtyCtrl.text = _items[index].qty.toString();
    });
  }

  void _applyLineEdit() {
    final index = _editingIndex;
    if (index == null) return;

    final rate = double.tryParse(_rateCtrl.text.trim());
    final qty = double.tryParse(_qtyCtrl.text.trim());

    if (rate == null || rate <= 0 || qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid rate and quantity')),
      );
      return;
    }

    setState(() {
      _items[index] = _items[index].copyWith(rate: rate, qty: qty);
      _editingIndex = null;
      _syncSummaryFields();
    });
  }

  Future<void> _saveBill() async {
    if (!_editUnlocked || _saving) return;

    setState(() => _saving = true);

    final amount = double.tryParse(_amountCtrl.text.trim());
    final gst = double.tryParse(_gstCtrl.text.trim());
    final grandTotal = double.tryParse(_grandTotalCtrl.text.trim());

    if (widget.adminFullEdit &&
        _items.isEmpty &&
        (amount == null || gst == null || grandTotal == null)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid amount, GST, and grand total')),
      );
      return;
    }

    final totals = _computedTotals();

    final updated = SaleBill(
      billNo: _bill.billNo,
      location: _bill.location,
      billDate: _bill.billDate,
      paymentMode: _paymentMode,
      customerName: widget.adminFullEdit
          ? _customerNameCtrl.text.trim()
          : _bill.customerName,
      mobile: widget.adminFullEdit ? _mobileCtrl.text.trim() : _bill.mobile,
      items: _items,
      totalQty: _items.isEmpty ? _bill.totalQty : totals.totalQty,
      totalAmount: widget.adminFullEdit && _items.isEmpty
          ? amount ?? _bill.totalAmount
          : totals.totalAmount,
      totalCgst: widget.adminFullEdit && _items.isEmpty
          ? (gst ?? 0) / 2
          : totals.totalCgst,
      totalSgst: widget.adminFullEdit && _items.isEmpty
          ? (gst ?? 0) / 2
          : totals.totalSgst,
      totalIgst: widget.adminFullEdit && _items.isEmpty ? 0 : totals.totalIgst,
      grandTotal: widget.adminFullEdit && _items.isEmpty
          ? grandTotal ?? _bill.grandTotal
          : totals.grandTotal,
    );

    final result = await BillRepository.saveBill(
      updated,
      updateLocalId: widget.localId,
    );

    if (!mounted) return;

    setState(() => _saving = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not save bill')),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computedTotals();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'BILL ${_bill.billNo}',
        automaticallyImplyLeading: true,
        actions: [
          if (!widget.readOnly && _checkedPersist)
            if (!_editUnlocked)
              TextButton(
                onPressed: _canPersistOnDevice ? _onEditPressed : _onEditPressed,
                child: const Text('EDIT'),
              )
            else
              TextButton(
                onPressed: _saving ? null : _saveBill,
                child: Text(_saving ? 'SAVING...' : 'SAVE'),
              ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBillHeader(),
            const SizedBox(height: 8),
            _buildTotalsSummary(totals),
            const SizedBox(height: 8),
            _buildCustomerSection(),
            const SizedBox(height: 8),
            _buildItemTable(),
            const SizedBox(height: 8),
            _buildTotals(totals),
          ],
        ),
      ),
    );
  }

  Widget _buildBillHeader() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('BILL NO:', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 6),
              Container(
                width: 72,
                height: 28,
                alignment: Alignment.center,
                color: LedgerBillDetailScreen.billNoColor,
                child: Text(
                  '${_bill.billNo}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text('DATE:', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 6),
              Text(
                _formatDate(_bill.billDate),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (_editUnlocked)
                DropdownButton<String>(
                  value: _paymentMode,
                  items: LedgerBillDetailScreen.paymentModes
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(mode),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _paymentMode = value);
                  },
                )
              else
                Text(
                  _paymentMode,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Location: ${_bill.location}',
                style: const TextStyle(fontSize: 10),
              ),
              if (_syncStatus != null) ...[
                const Spacer(),
                _syncBadge(_syncStatus!),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _syncBadge(String status) {
    final isPending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPending ? AppColors.warningBg : AppColors.successBg,
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        isPending ? 'Pending sync' : 'Synced',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isPending ? AppColors.warningFg : AppColors.success,
        ),
      ),
    );
  }

  Widget _buildTotalsSummary(BillTotals totals) {
    final useManualTotals =
        widget.adminFullEdit && _editUnlocked && _items.isEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: useManualTotals
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bill totals',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _editableTotalField('Amount', _amountCtrl)),
                    const SizedBox(width: 8),
                    Expanded(child: _editableTotalField('GST', _gstCtrl)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _editableTotalField('Grand Total', _grandTotalCtrl),
                    ),
                  ],
                ),
              ],
            )
          : CompactAbstractSummary(
              amountValue: _format(totals.totalAmount),
              gstValue: _format(totals.totalGst),
              grandTotalValue: _format(totals.grandTotal),
              cardWidth: 120,
            ),
    );
  }

  Widget _editableTotalField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: AppColors.mutedBlue,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer Details',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (_editUnlocked && widget.adminFullEdit) ...[
            _editableField('Name', _customerNameCtrl),
            const SizedBox(height: 4),
            _editableField('Mobile', _mobileCtrl, number: true),
          ] else ...[
            _readOnlyField('Name', _bill.customerName),
            const SizedBox(height: 4),
            _readOnlyField('Mobile', _bill.mobile),
          ],
          if (_editUnlocked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.adminFullEdit
                    ? 'Admin edit — update customer, payment, line items, then SAVE.'
                    : 'Edit mode — tap a line item to correct rate/qty, then SAVE.',
                style: const TextStyle(
                  fontSize: AppTextSizes.listSubtitle,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _editableField(
    String label,
    TextEditingController controller, {
    bool number = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 10)),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: number ? TextInputType.phone : TextInputType.text,
            inputFormatters: number
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 10)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildItemTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tableHeader(),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This bill has no line items stored locally.',
                style: TextStyle(fontSize: 11),
              ),
            )
          else
            ...List.generate(_items.length, (index) {
              if (_editingIndex == index) {
                return _editRow(index);
              }
              return _tableRow(index, _items[index]);
            }),
        ],
      ),
    );
  }

  Widget _editRow(int index) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Text('Line ${index + 1}', style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            height: 32,
            child: TextField(
              controller: _rateCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Rate',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            height: 32,
            child: TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Qty',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _applyLineEdit, child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: AppColors.tableHeader,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Row(
        children: [
          _HeaderCell('S.no', 1),
          _HeaderCell('Qty', 1),
          _HeaderCell('RATE', 1),
          _HeaderCell('AMOUNT', 1),
          _HeaderCell('t amt', 1),
          _HeaderCell('CGST %', 1),
          _HeaderCell('SGST %', 1),
          _HeaderCell('IGST', 1),
        ],
      ),
    );
  }

  Widget _tableRow(int index, BillItem item) {
    return InkWell(
      onTap: _editUnlocked ? () => _startEditLine(index) : null,
      child: Row(
        children: [
          _DataCell('${index + 1}', 1),
          _DataCell(_format(item.qty), 1),
          _DataCell(_format(item.rate), 1),
          _DataCell(_format(item.amount), 1),
          _DataCell(_format(item.grossAmt), 1),
          _DataCell(_format(item.cgstPct), 1),
          _DataCell(_format(item.sgstPct), 1),
          _DataCell(_format(item.igst), 1),
        ],
      ),
    );
  }

  Widget _buildTotals(BillTotals totals) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _totalRow('Total Qty', _format(totals.totalQty)),
          _totalRow('Total Amt', _format(totals.totalAmount)),
          _totalRow('CGST', _format(totals.totalCgst)),
          _totalRow('SGST', _format(totals.totalSgst)),
          _totalRow('IGST', _format(totals.totalIgst)),
          const SizedBox(height: 8),
          const Text(
            'Grand Total',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _format(totals.grandTotal),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              amountInWords(totals.grandTotal),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 10)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final TextEditingController controller;

  const _PasswordDialog({required this.controller});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  String? _error;

  void _submit() {
    if (widget.controller.text == billEditPassword) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = 'Incorrect password');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter edit password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _HeaderCell(this.text, this.flex);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final int flex;

  const _DataCell(this.text, this.flex);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
