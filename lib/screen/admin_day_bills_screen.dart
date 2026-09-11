import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/day_drill_down_repository.dart';
import 'package:sales/repositories/ledger_repository.dart';
import 'package:sales/screen/ledger_bill_detail_screen.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

/// Scrollable bill list for one day with compact mode for very large days.
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

  @override
  Widget build(BuildContext context) {
    final filteredBills = _filteredBills;
    final compact = DayDrillDownRepository.shouldUseCompactBillList(
      filteredBills.length,
    );
    final fullDetail = DayDrillDownRepository.shouldShowFullBillDetails(
      filteredBills.length,
    );

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
                    if (compact)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: Text(
                          'Showing bill number and amount only for performance.',
                          style: TextStyle(
                            fontSize: AppTextSizes.listSubtitle,
                            color: AppColors.mutedBlue,
                          ),
                        ),
                      ),
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
                          : compact
                              ? _buildCompactList(filteredBills)
                              : fullDetail
                                  ? _buildFullList(filteredBills)
                                  : _buildFullList(filteredBills),
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

  Widget _buildCompactList(List<DayBillRow> bills) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final bill = bills[index];
        return _BillListTile(
          title: 'Bill ${bill.billNo}',
          subtitle: branchLabelForDisplayName(bill.location),
          amount: _formatMoney(bill.grandTotal),
          onTap: () => _openBill(bill),
        );
      },
    );
  }

  Widget _buildFullList(List<DayBillRow> bills) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final bill = bills[index];
        return Material(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => _openBill(bill),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Bill ${bill.billNo}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatMoney(bill.grandTotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    branchLabelForDisplayName(bill.location),
                    style: const TextStyle(
                      fontSize: AppTextSizes.listSubtitle,
                      color: AppColors.mutedBlue,
                    ),
                  ),
                  if (bill.customerName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bill.customerName,
                      style: const TextStyle(fontSize: AppTextSizes.listTitle),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _metaChip('Cash', _paymentColumnAmount(bill, cash: true)),
                      _metaChip(
                        'Card/UPI',
                        _paymentColumnAmount(bill, cash: false),
                      ),
                      _metaChip('Amount', _formatMoney(bill.total)),
                      _metaChip('GST', _formatMoney(bill.gst)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BillListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;

  const _BillListTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: AppTextSizes.listSubtitle,
                        color: AppColors.mutedBlue,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                amount,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _metaChip(String label, String value) {
  if (value.isEmpty) {
    return const SizedBox.shrink();
  }

  return Text(
    '$label: $value',
    style: const TextStyle(
      fontSize: AppTextSizes.listSubtitle,
      color: AppColors.navy,
    ),
  );
}
