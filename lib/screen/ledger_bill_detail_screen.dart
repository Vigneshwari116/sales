import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:sales/models/sale_bill.dart';
import 'package:sales/screen/bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';

/// Read-only drill-down for a saved bill from the sales ledger.
class LedgerBillDetailScreen extends StatelessWidget {
  final SaleBill bill;
  final String? syncStatus;

  const LedgerBillDetailScreen({
    super.key,
    required this.bill,
    this.syncStatus,
  });

  static const Color _background = Color(0xFFC5F6C5);
  static const Color _header = Color(0xFFFFF5C5);
  static const Color _border = Color(0xFF888888);
  static const Color _billNoColor = Color(0xFFFFE5A0);

  String _format(num value) => NumberFormat('#,##0.00').format(value);

  String _formatDate(DateTime date) =>
      DateFormat('dd-MMM-yy').format(date);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: Text(
          'BILL ${bill.billNo}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
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
        border: Border.all(color: _border),
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
                color: _billNoColor,
                child: Text(
                  '${bill.billNo}',
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
                _formatDate(bill.billDate),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              Text(
                bill.paymentMode,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Location: ${bill.location}',
                style: const TextStyle(fontSize: 10),
              ),
              if (syncStatus != null) ...[
                const Spacer(),
                _syncBadge(syncStatus!),
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
        color: isPending ? const Color(0xFFFFF3CD) : const Color(0xFFD4EDDA),
        border: Border.all(color: _border),
      ),
      child: Text(
        isPending ? 'Pending sync' : 'Synced',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isPending ? const Color(0xFF856404) : const Color(0xFF155724),
        ),
      ),
    );
  }

  Widget _buildCustomerSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _border),
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
          _readOnlyField('Name', bill.customerName),
          const SizedBox(height: 4),
          _readOnlyField('Mobile', bill.mobile),
        ],
      ),
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
          child: Text(
            value,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildItemTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tableHeader(),
          if (bill.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This bill has no line items stored locally.',
                style: TextStyle(fontSize: 11),
              ),
            )
          else
            ...List.generate(bill.items.length, (index) {
              return _tableRow(index, bill.items[index]);
            }),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Container(
      color: _header,
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
    return Row(
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
    );
  }

  Widget _buildTotals() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _totalRow('Total Qty', _format(bill.totalQty)),
          _totalRow('Total Amt', _format(bill.totalAmount)),
          _totalRow('CGST', _format(bill.totalCgst)),
          _totalRow('SGST', _format(bill.totalSgst)),
          _totalRow('IGST', _format(bill.totalIgst)),
          const SizedBox(height: 8),
          const Text(
            'Grand Total',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _format(bill.grandTotal),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              amountInWords(bill.grandTotal),
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
            bottom: BorderSide(color: LedgerBillDetailScreen._border, width: 0.6),
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
