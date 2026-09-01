import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:sales/config/local_credentials.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'package:sales/theme/app_theme.dart';

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

  @override
  State<LedgerBillDetailScreen> createState() => _LedgerBillDetailScreenState();
}

class _LedgerBillDetailScreenState extends State<LedgerBillDetailScreen> {
  late SaleBill _bill;
  late List<BillItem> _items;

  bool _editUnlocked = false;
  bool _showPasswordField = false;
  bool _saving = false;
  String? _passwordError;
  int? _editingIndex;

  final _passwordCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
    _items = widget.bill.items.map((e) => e.copyWith()).toList();
    _customerNameCtrl.text = _bill.customerName;
    _mobileCtrl.text = _bill.mobile;
    if (widget.adminFullEdit) {
      _editUnlocked = true;
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _rateCtrl.dispose();
    _qtyCtrl.dispose();
    _customerNameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  String _format(num value) => NumberFormat('#,##0.00').format(value);

  String _formatDate(DateTime date) => DateFormat('dd-MMM-yy').format(date);

  double get _totalQty =>
      _items.fold(0.0, (sum, item) => sum + item.qty);

  double get _totalAmount =>
      _items.fold(0.0, (sum, item) => sum + item.amount);

  double get _totalCgst =>
      _items.fold(0.0, (sum, item) => sum + item.cgst);

  double get _totalSgst =>
      _items.fold(0.0, (sum, item) => sum + item.sgst);

  double get _totalIgst =>
      _items.fold(0.0, (sum, item) => sum + item.igst);

  double get _grandTotal =>
      _items.fold(0.0, (sum, item) => sum + item.grossAmt);

  void _onMobileDoubleTap() {
    if (widget.adminFullEdit ||
        widget.readOnly ||
        _editUnlocked ||
        _showPasswordField) {
      return;
    }

    setState(() {
      _showPasswordField = true;
      _passwordError = null;
      _passwordCtrl.clear();
    });
  }

  void _tryUnlockEdit() {
    if (_passwordCtrl.text == billEditPassword) {
      setState(() {
        _editUnlocked = true;
        _showPasswordField = false;
        _passwordError = null;
      });
      return;
    }

    setState(() => _passwordError = 'Incorrect password');
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
    });
  }

  Future<void> _saveBill() async {
    if (!_editUnlocked || _saving) return;

    setState(() => _saving = true);

    final updated = SaleBill(
      billNo: _bill.billNo,
      location: _bill.location,
      billDate: _bill.billDate,
      paymentMode: _bill.paymentMode,
      customerName: widget.adminFullEdit
          ? _customerNameCtrl.text.trim()
          : _bill.customerName,
      mobile: widget.adminFullEdit ? _mobileCtrl.text.trim() : _bill.mobile,
      items: _items,
      totalQty: _totalQty,
      totalAmount: _totalAmount,
      totalCgst: _totalCgst,
      totalSgst: _totalSgst,
      totalIgst: _totalIgst,
      grandTotal: _grandTotal,
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'BILL ${_bill.billNo}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSizes.appBarTitle,
          ),
        ),
        backgroundColor: AppColors.headerBand,
        foregroundColor: AppColors.navy,
        actions: [
          if (_editUnlocked)
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
            _buildCustomerSection(),
            const SizedBox(height: 8),
            _buildItemTable(),
            const SizedBox(height: 8),
            _buildTotals(),
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
              Text(
                _bill.paymentMode,
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
              if (widget.syncStatus != null) ...[
                const Spacer(),
                _syncBadge(widget.syncStatus!),
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
            GestureDetector(
              onDoubleTap: _onMobileDoubleTap,
              child: _readOnlyField('Mobile', _bill.mobile),
            ),
            if (_showPasswordField && !_editUnlocked) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 48,
                    child: Text('Password', style: TextStyle(fontSize: 10)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      autofocus: true,
                      onSubmitted: (_) => _tryUnlockEdit(),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _tryUnlockEdit,
                    child: const Text('OK'),
                  ),
                ],
              ),
              if (_passwordError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _passwordError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: AppTextSizes.listSubtitle,
                    ),
                  ),
                ),
            ],
          ],
          if (_editUnlocked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.adminFullEdit
                    ? 'Admin edit — update customer, line items, then SAVE.'
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

  Widget _buildTotals() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _totalRow('Total Qty', _format(_totalQty)),
          _totalRow('Total Amt', _format(_totalAmount)),
          _totalRow('CGST', _format(_totalCgst)),
          _totalRow('SGST', _format(_totalSgst)),
          _totalRow('IGST', _format(_totalIgst)),
          const SizedBox(height: 8),
          const Text(
            'Grand Total',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _format(_grandTotal),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              amountInWords(_grandTotal),
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
