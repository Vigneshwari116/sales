import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/bill_item.dart';

class LedgerBillEditDialog extends StatefulWidget {
  final String localId;
  final SaleBill bill;

  const LedgerBillEditDialog({
    super.key,
    required this.localId,
    required this.bill,
  });

  @override
  State<LedgerBillEditDialog> createState() => _LedgerBillEditDialogState();
}

class _LedgerBillEditDialogState extends State<LedgerBillEditDialog> {
  late List<BillItem> _items;
  late List<TextEditingController> _rateControllers;
  late List<TextEditingController> _qtyControllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List<BillItem>.from(widget.bill.items);
    _rateControllers = _items
        .map((item) => TextEditingController(text: _format(item.rate)))
        .toList();
    _qtyControllers = _items
        .map((item) => TextEditingController(text: _format(item.qty)))
        .toList();
  }

  @override
  void dispose() {
    for (var controller in _rateControllers) {
      controller.dispose();
    }
    for (var controller in _qtyControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _save() async {
    var updatedItems = <BillItem>[];

    for (var i = 0; i < _items.length; i++) {
      var rate = double.tryParse(_rateControllers[i].text.trim());
      var qty = double.tryParse(_qtyControllers[i].text.trim());

      if (rate == null || rate <= 0 || qty == null || qty <= 0) {
        _showError('Line ${i + 1}: rate and qty must be greater than 0');
        return;
      }

      updatedItems.add(
        _items[i].copyWith(rate: rate, qty: qty),
      );
    }

    if (updatedItems.isEmpty) {
      _showError('Bill has no line items to save');
      return;
    }

    setState(() => _saving = true);

    var updatedBill =
        LedgerRepository.recalculateBill(widget.bill, updatedItems);

    await LedgerRepository.updateBill(
      localId: widget.localId,
      bill: updatedBill,
    );

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Bill ${widget.bill.billNo}'),
      content: SizedBox(
        width: 420,
        child: _items.isEmpty
            ? const Text('This bill has no line items stored locally.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Divider(height: 16),
                      Text(
                        'Item ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _rateControllers[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Rate',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _qtyControllers[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Qty',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving || _items.isEmpty ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('SAVE'),
        ),
      ],
    );
  }
}
