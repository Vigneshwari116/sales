import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sales/api/sales_api.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/services/bill_print_service.dart';
import 'package:sales/services/session_service.dart';

import 'bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'login_screen.dart';
import 'sales_ledger_screen.dart';

class SalesBillScreen extends StatefulWidget {
  const SalesBillScreen({super.key});

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color backgroundColor = Color(0xFFC5F6C5);
  static const Color buttonColor = Color(0xFF9D1717);
  static const Color headerColor = Color(0xFFFFF5C5);
  static const Color borderColor = Color(0xFF888888);
  static const Color billNoColor = Color(0xFF7FE8E8);
  static const double _entryBoxWidth = 100;
  static const double _entryBoxHeight = 42;

  // ============================================================
  // LOCATIONS
  // ============================================================

  final List<String> _locations = const [
    'Location 1',
    'Location 2',
    'Location 3',
    'Location 4',
  ];

  String _selectedLocation = 'Location 1';

  // Current bill number.
  int _billNo = 1;

  // Whether the bill has been saved/completed.
  bool _billSaved = false;

  bool _busy = false;

  // ============================================================
  // BILL DATE
  // ============================================================

  DateTime _billDate = DateTime.now();

  // ============================================================
  // PAYMENT
  // ============================================================

  String _paymentMode = 'CASH';

  final List<String> _paymentModes = const [
    'CASH',
    'CARD',
    'PHONE PEE',
  ];

  // ============================================================
  // CUSTOMER
  // ============================================================

  final TextEditingController _customerNameController =
  TextEditingController();

  final TextEditingController _mobileController =
  TextEditingController();

  // ============================================================
  // RATE / QTY
  // ============================================================

  final TextEditingController _rateController =
  TextEditingController(text: '0');

  final TextEditingController _qtyController =
  TextEditingController(text: '0');

  final TextEditingController _amountController =
  TextEditingController(text: '0');

  final FocusNode _rateFocus = FocusNode();

  final FocusNode _qtyFocus = FocusNode();

  // ============================================================
  // AUTO FOCUS TIMERS
  // ============================================================

  Timer? _rateTimer;
  Timer? _qtyTimer;

  // ============================================================
  // PRINTER
  // ============================================================

  String _printer = 'TVS-E RP 3230 on Ne00:';

  final List<String> _printers = const [
    'TVS-E RP 3230 on Ne00:',
    'Microsoft Print to PDF',
  ];

  // ============================================================
  // ITEMS
  // ============================================================

  final List<BillItem> _items = [];

  int? _selectedIndex;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _rateController.text = '0';
    _qtyController.text = '0';

    _restoreSessionOrLoadBill().then((_) {
      if (mounted) {
        _focusRate();
      }
    });
  }

  Future<void> _restoreSessionOrLoadBill() async {
    final session = await SessionService.loadBillSession();

    if (!mounted) return;

    if (session != null) {
      setState(() {
        _selectedLocation = session.location;
        _billNo = session.billNo;
        _billDate = session.billDate;
        _paymentMode = session.paymentMode;
        _customerNameController.text = session.customerName;
        _mobileController.text = session.mobile;
        _items
          ..clear()
          ..addAll(session.items);
        _billSaved = session.billSaved;
        _selectedIndex = null;
      });
      return;
    }

    await _loadBillNumber();
  }

  Future<void> _persistSession() async {
    await SessionService.saveBillSession(
      location: _selectedLocation,
      billNo: _billNo,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim().isEmpty
          ? 'CASH'
          : _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      billSaved: _billSaved,
    );
  }

  // ============================================================
  // LOCATION BILL NUMBER
  // ============================================================

  String _billNumberKey(String location) {
    switch (location) {
      case 'Location 1':
        return 'sales_bill_number_location_1';

      case 'Location 2':
        return 'sales_bill_number_location_2';

      case 'Location 3':
        return 'sales_bill_number_location_3';

      case 'Location 4':
        return 'sales_bill_number_location_4';

      default:
        return 'sales_bill_number_location_1';
    }
  }

  // ============================================================
  // LOAD BILL NUMBER
  // ============================================================

  Future<void> _loadBillNumber() async {
    final serverResult =
        await SalesApi.getNextBillNumber(_selectedLocation);

    if (serverResult.ok && serverResult.data != null) {
      if (!mounted) return;
      setState(() {
        _billNo = serverResult.data!;
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = _billNumberKey(_selectedLocation);
    final lastBillNumber = prefs.getInt(key) ?? 0;

    if (!mounted) return;

    setState(() {
      _billNo = lastBillNumber + 1;
    });
  }

  // ============================================================
  // SAVE LAST COMPLETED BILL NUMBER
  // ============================================================

  Future<void> _saveBillNumber() async {
    final prefs = await SharedPreferences.getInstance();

    final key = _billNumberKey(_selectedLocation);

    await prefs.setInt(key, _billNo);
  }

  // ============================================================
  // FOCUS RATE
  // ============================================================

  void _focusRate() {
    if (!mounted) return;

    _rateFocus.requestFocus();

    _rateController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _rateController.text.length,
    );
  }

  // ============================================================
  // FOCUS QTY
  // ============================================================

  void _focusQty() {
    if (!mounted) return;

    _qtyFocus.requestFocus();

    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  // ============================================================
  // RATE CHANGED
  //
  // Automatically moves to QTY after the user stops typing.
  // ============================================================

  void _rateChanged(String value) {
    _rateTimer?.cancel();

    final text = value.trim();

    if (text.isEmpty || text == '0') {
      return;
    }

    final rate = double.tryParse(text);

    if (rate == null || rate <= 0) {
      return;
    }

    _rateTimer = Timer(
      const Duration(milliseconds: 700),
          () {
        if (!mounted) return;

        final currentRate =
            double.tryParse(_rateController.text) ?? 0;

        if (currentRate > 0) {
          _focusQty();
        }
      },
    );

    setState(() {});
  }

  // ============================================================
  // QTY CHANGED
  //
  // Automatically adds item after the user stops typing.
  // ============================================================

  void _qtyChanged(String value) {
    _qtyTimer?.cancel();

    final text = value.trim();

    if (text.isEmpty || text == '0') {
      setState(() {});
      return;
    }

    final qty = double.tryParse(text);

    if (qty == null || qty <= 0) {
      setState(() {});
      return;
    }

    _qtyTimer = Timer(
      const Duration(milliseconds: 700),
          () {
        if (!mounted) return;

        final currentQty =
            double.tryParse(_qtyController.text) ?? 0;

        if (currentQty > 0) {
          if (_selectedIndex != null) {
            _updateModifiedItem();
          } else {
            _addItem();
          }
        }
      },
    );

    setState(() {});
  }

  // ============================================================
  // RATE ENTER
  // ============================================================

  void _rateSubmitted() {
    final double? rate =
    double.tryParse(_rateController.text);

    if (rate == null || rate <= 0) {
      _showMessage('Rate must be greater than 0');
      _focusRate();
      return;
    }

    _focusQty();
  }

  // ============================================================
  // QTY ENTER
  // ============================================================

  void _qtySubmitted() {
    final double? rate =
    double.tryParse(_rateController.text);

    final double? qty =
    double.tryParse(_qtyController.text);

    if (rate == null || rate <= 0) {
      _showMessage('Rate must be greater than 0');
      _focusRate();
      return;
    }

    if (qty == null || qty <= 0) {
      _showMessage('Quantity must be greater than 0');
      _focusQty();
      return;
    }

    if (_selectedIndex != null) {
      _updateModifiedItem();
    } else {
      _addItem();
    }
  }

  // ============================================================
  // ADD ITEM
  // ============================================================

  void _addItem() {
    final double? rate =
    double.tryParse(_rateController.text);

    final double? qty =
    double.tryParse(_qtyController.text);

    if (rate == null || rate <= 0) {
      _showMessage('Rate must be greater than 0');
      _focusRate();
      return;
    }

    if (qty == null || qty <= 0) {
      _showMessage('Quantity must be greater than 0');
      _focusQty();
      return;
    }

    setState(() {
      _items.add(
        BillItem(
          qty: qty,
          rate: rate,

          // Legacy GST
          cgstPct: 2.5,
          sgstPct: 2.5,
          igstPct: 0,
        ),
      );

      _selectedIndex = null;
      _billSaved = false;

      // Reset fields to ZERO
      _rateController.text = '0';
      _qtyController.text = '0';
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // MODIFY SELECTED ITEM
  // ============================================================

  void _modifyItem() {
    if (_selectedIndex == null) {
      _showMessage('Select an item first');
      return;
    }

    final BillItem item =
    _items[_selectedIndex!];

    setState(() {
      _rateController.text =
          _format(item.rate);

      _qtyController.text =
          _format(item.qty);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // UPDATE MODIFIED ITEM
  // ============================================================

  void _updateModifiedItem() {
    if (_selectedIndex == null) {
      _addItem();
      return;
    }

    final double? rate =
    double.tryParse(_rateController.text);

    final double? qty =
    double.tryParse(_qtyController.text);

    if (rate == null || rate <= 0) {
      _showMessage('Rate must be greater than 0');
      _focusRate();
      return;
    }

    if (qty == null || qty <= 0) {
      _showMessage('Quantity must be greater than 0');
      _focusQty();
      return;
    }

    setState(() {
      _items[_selectedIndex!] =
          _items[_selectedIndex!].copyWith(
            rate: rate,
            qty: qty,
          );

      _selectedIndex = null;
      _billSaved = false;

      _rateController.text = '0';
      _qtyController.text = '0';
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // DELETE ITEM
  // ============================================================

  void _deleteItem() {
    if (_selectedIndex == null) {
      _showMessage('Select an item first');
      return;
    }

    setState(() {
      _items.removeAt(_selectedIndex!);

      _selectedIndex = null;
      _billSaved = false;

      _rateController.text = '0';
      _qtyController.text = '0';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // CLEAR CURRENT BILL
  // ============================================================

  void _clearCurrentBill() {
    _billDate = DateTime.now();

    _paymentMode = 'CASH';

    _customerNameController.text = '';

    _mobileController.clear();

    _rateController.text = '0';

    _qtyController.text = '0';

    _items.clear();

    _selectedIndex = null;

    _billSaved = false;
  }

  // ============================================================
  // NEW BILL
  //
  // Starts the next bill number.
  // ============================================================

  Future<void> _newBill() async {
    // If current bill has not been saved, don't silently lose it.
    if (_items.isNotEmpty && !_billSaved) {
      _showMessage(
        'Save the current bill before starting the next bill',
      );
      return;
    }

    await _saveBillNumber();

    if (!mounted) return;

    setState(() {
      _billNo++;
      _clearCurrentBill();
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // NEXT BILL
  // ============================================================

  Future<void> _nextBill() async {
    await _newBill();
  }

  // ============================================================
  // PREVIOUS BILL
  //
  // Only changes the displayed number.
  // ============================================================

  Future<void> _previousBill() async {
    if (_busy) return;

    if (_items.isNotEmpty && !_billSaved) {
      _showMessage('Save the current bill before loading previous bill');
      return;
    }

    setState(() => _busy = true);

    final result = await SalesApi.getPreviousBill(
      billNo: _billNo,
      location: _selectedLocation,
    );

    if (!mounted) return;

    setState(() => _busy = false);

    if (!result.ok || result.data == null) {
      _showMessage(result.error ?? 'No previous bill found');
      return;
    }

    _applyBill(result.data!);
    _persistSession();
    _showMessage('Loaded Bill ${result.data!.billNo}');
  }

  // ============================================================
  // SAVE BILL
  //
  // Save current bill and automatically move to next bill.
  // ============================================================

  Future<void> _saveBill() async {
    if (_busy) return;

    if (_items.isEmpty) {
      _showMessage('Add at least one item before saving');
      return;
    }

    setState(() => _busy = true);

    final bill = _buildCurrentBill();
    final result = await SalesApi.saveBill(bill);

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _busy = false);
      _showMessage(result.error ?? 'Failed to save bill');
      return;
    }

    await _saveBillNumber();

    if (!mounted) return;

    final int savedBillNo = _billNo;

    try {
      final path = await BillPrintService.saveReceiptToDesktop(bill);
      setState(() {
        _billSaved = true;
        _busy = false;
      });

      _showMessage(
        'Bill $savedBillNo saved. Receipt: $path',
      );
    } catch (e) {
      setState(() {
        _billSaved = true;
        _busy = false;
      });
      _showMessage('Bill $savedBillNo saved on server');
    }

    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    await _loadBillNumber();

    if (!mounted) return;

    setState(() {
      _clearCurrentBill();
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // PRINT
  // ============================================================

  Future<void> _printBill() async {
    if (_busy) return;

    if (_items.isEmpty) {
      _showMessage('Add items before printing');
      return;
    }

    setState(() => _busy = true);

    try {
      final bill = _buildCurrentBill();
      await BillPrintService.printReceipt(
        bill,
        printerName: _printer,
      );
      if (!mounted) return;
      _showMessage('Printing Bill $_billNo (${bill.items.length} items)');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Print failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openLedger() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalesLedgerScreen(location: _selectedLocation),
      ),
    );
  }

  SaleBill _buildCurrentBill() {
    return SaleBill(
      billNo: _billNo,
      location: _selectedLocation,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim().isEmpty
          ? 'CASH'
          : _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      totalQty: _totalQty,
      totalAmount: _totalAmount,
      totalCgst: _totalCgst,
      totalSgst: _totalSgst,
      totalIgst: _totalIgst,
      grandTotal: _grandTotal,
    );
  }

  void _applyBill(SaleBill bill) {
    setState(() {
      _billNo = bill.billNo;
      _billDate = bill.billDate;
      _paymentMode = bill.paymentMode;
      _customerNameController.text = bill.customerName;
      _mobileController.text = bill.mobile;
      _items
        ..clear()
        ..addAll(bill.items);
      _selectedIndex = null;
      _billSaved = true;
      _rateController.text = '0';
      _qtyController.text = '0';
    });
  }

  // ============================================================
  // EXIT
  // ============================================================

  void _exitScreen() async {
    await _persistSession();
    await SessionService.clearLogin();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ============================================================
  // LOCATION CHANGE
  // ============================================================

  Future<void> _changeLocation(
      String location) async {
    if (location == _selectedLocation) {
      return;
    }

    // Don't destroy an unsaved bill.
    if (_items.isNotEmpty && !_billSaved) {
      _showMessage(
        'Save the current bill before changing location',
      );
      return;
    }

    setState(() {
      _selectedLocation = location;

      _items.clear();

      _selectedIndex = null;

      _rateController.text = '0';
      _qtyController.text = '0';

      _customerNameController.text = '';
      _mobileController.clear();

      _paymentMode = 'CASH';

      _billDate = DateTime.now();
    });

    await _loadBillNumber();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRate();
    });
  }

  // ============================================================
  // TOTAL QTY
  // ============================================================

  double get _totalQty {
    return _items.fold(
      0,
          (sum, item) => sum + item.qty,
    );
  }

  // ============================================================
  // TOTAL TAXABLE AMOUNT
  // ============================================================

  double get _totalAmount {
    return _items.fold(
      0,
          (sum, item) => sum + item.amount,
    );
  }

  // ============================================================
  // TOTAL CGST
  // ============================================================

  double get _totalCgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.cgst,
    );
  }

  // ============================================================
  // TOTAL SGST
  // ============================================================

  double get _totalSgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.sgst,
    );
  }

  // ============================================================
  // TOTAL IGST
  // ============================================================

  double get _totalIgst {
    return _items.fold(
      0,
          (sum, item) => sum + item.igst,
    );
  }

  // ============================================================
  // GRAND TOTAL
  //
  // GST INCLUSIVE
  // ============================================================

  double get _grandTotal {
    return _items.fold(
      0,
          (sum, item) => sum + item.netAmt,
    );
  }

  // ============================================================
  // CURRENT AMOUNT
  // ============================================================

  double get _currentAmount {
    final double rate =
        double.tryParse(
          _rateController.text,
        ) ??
            0;

    final double qty =
        double.tryParse(
          _qtyController.text,
        ) ??
            0;

    return rate * qty;
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
        const Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    _updateAmountDisplay();

    return Scaffold(
      backgroundColor: backgroundColor,

      // ========================================================
      // NO "SALES BILL" TITLE
      // ========================================================

      appBar: AppBar(
        toolbarHeight: 52,

        title: const SizedBox.shrink(),

        backgroundColor:
        const Color(0xFFD5D8D5),

        foregroundColor: Colors.black,

        elevation: 0,

        actions: [
          _buildLocationDropdown(),

          const SizedBox(width: 8),

          _buildPrinterDropdown(),

          const SizedBox(width: 10),
        ],
      ),

      body: LayoutBuilder(
        builder: (
            context,
            constraints,
            ) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),

            child: Column(
              children: [
                // ==================================================
                // TOP AREA
                // ==================================================

                _buildTopArea(),

                const SizedBox(height: 6),

                Expanded(
                  child: _buildMainArea(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // LOCATION DROPDOWN
  // ============================================================

  Widget _buildLocationDropdown() {
    return SizedBox(
      width: 145,
      height: 40,
      child: DropdownButtonFormField<String>(
        value: _selectedLocation,

        decoration:
        const InputDecoration(
          labelText: 'Location',
          labelStyle: TextStyle(
            fontSize: 9,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding:
          EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 0,
          ),
        ),

        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
        ),

        items: _locations.map(
              (location) {
            return DropdownMenuItem<String>(
              value: location,
              child: Text(
                location,
                style: const TextStyle(
                  fontSize: 11,
                ),
              ),
            );
          },
        ).toList(),

        onChanged: (value) {
          if (value == null) return;

          _changeLocation(value);
        },
      ),
    );
  }

  // ============================================================
  // PRINTER DROPDOWN
  // ============================================================

  Widget _buildPrinterDropdown() {
    return SizedBox(
      width: 205,
      height: 40,
      child: DropdownButtonFormField<String>(
        value: _printer,

        decoration:
        const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding:
          EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 0,
          ),
        ),

        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
        ),

        items: _printers.map(
              (item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 11,
                ),
              ),
            );
          },
        ).toList(),

        onChanged: (value) {
          if (value == null) return;

          setState(() {
            _printer = value;
          });
        },
      ),
    );
  }

  // ============================================================
  // TOP AREA
  // ============================================================

  Widget _buildTopArea() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: _buildBillDetails(),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 6,
          child: _buildCustomerDetails(),
        ),
      ],
    );
  }

  // ============================================================
  // BILL DETAILS
  // ============================================================

  Widget _buildBillDetails() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: borderColor,
        ),
      ),

      padding:
      const EdgeInsets.all(5),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,

        children: [
          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text(
                  'BILL NO:',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
              ),

              // ==================================================
              // FIXED BILL NUMBER
              // ==================================================

              Container(
                width: 82,
                height: 29,

                alignment:
                Alignment.center,

                decoration:
                const BoxDecoration(
                  color: billNoColor,
                ),

                child: FittedBox(
                  fit: BoxFit.scaleDown,

                  child: Text(
                    '$_billNo',
                    style:
                    const TextStyle(
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              Expanded(
                child: SizedBox(
                  height: 29,

                  child:
                  DropdownButtonFormField<
                      String>(
                    value: _paymentMode,

                    isDense: true,

                    decoration:
                    const InputDecoration(
                      filled: true,
                      fillColor:
                      Colors.white,
                      border:
                      OutlineInputBorder(),
                      contentPadding:
                      EdgeInsets
                          .symmetric(
                        horizontal: 6,
                        vertical: 0,
                      ),
                    ),

                    style:
                    const TextStyle(
                      fontSize: 10,
                      color:
                      Colors.black,
                    ),

                    items:
                    _paymentModes.map(
                          (item) {
                        return DropdownMenuItem(
                          value: item,
                          child: Text(
                            item,
                            style:
                            const TextStyle(
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ).toList(),

                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _paymentMode =
                            value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text(
                  'BILL DATE:',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
              ),

              InkWell(
                onTap: _selectDate,

                child: Container(
                  width: 108,
                  height: 29,

                  alignment:
                  Alignment.center,

                  decoration:
                  BoxDecoration(
                    color: Colors.white,
                    border:
                    Border.all(
                      color:
                      borderColor,
                    ),
                  ),

                  child: Text(
                    '${_billDate.day.toString().padLeft(2, '0')}/'
                        '${_billDate.month.toString().padLeft(2, '0')}/'
                        '${_billDate.year}',

                    style:
                    const TextStyle(
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          _buildButtons(),
        ],
      ),
    );
  }

  // ============================================================
  // BUTTONS
  // ============================================================

  Widget _buildButtons() {
    Widget button(
        String text,
        VoidCallback onPressed,
        ) {
      return SizedBox(
        height: 25,

        child: ElevatedButton(
          onPressed: onPressed,

          style:
          ElevatedButton.styleFrom(
            backgroundColor:
            buttonColor,

            foregroundColor:
            Colors.white,

            padding:
            const EdgeInsets
                .symmetric(
              horizontal: 7,
            ),

            minimumSize:
            const Size(0, 25),

            shape:
            RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(
                2,
              ),
            ),
          ),

          child: Text(
            text,
            style:
            const TextStyle(
              fontSize: 8.5,
              fontWeight:
              FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        button('PRINT', _printBill),
        button('NEW', _newBill),
        button('NEXT', _nextBill),
        button('PREVIOUS', _previousBill),
        button('SAVE', _saveBill),
        button('EDIT', _modifyItem),
        button('DELETE', _deleteItem),
        button('LEDGER', _openLedger),
        button('EXIT', _exitScreen),
      ],
    );
  }

  // ============================================================
  // CUSTOMER DETAILS
  // ============================================================

  Widget _buildCustomerDetails() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer Details',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const SizedBox(
                width: 45,
                child: Text(
                  'Name',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
              ),

              Expanded(
                child: _smallTextField(
                  _customerNameController,
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          Row(
            children: [
              const SizedBox(
                width: 45,
                child: Text(
                  'MOBILE',
                  style: TextStyle(
                    fontSize: 10,
                  ),
                ),
              ),

              Expanded(
                child: _smallTextField(
                  _mobileController,
                  number: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SMALL TEXT FIELD
  // ============================================================

  Widget _smallTextField(
      TextEditingController controller, {
        bool number = false,
      }) {
    return SizedBox(
      height: 27,

      child: TextField(
        controller: controller,

        keyboardType: number
            ? TextInputType.phone
            : TextInputType.text,

        inputFormatters: number
            ? [
          FilteringTextInputFormatter
              .digitsOnly,
        ]
            : null,

        decoration:
        const InputDecoration(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding:
          EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 0,
          ),
        ),

        style:
        const TextStyle(
          fontSize: 10,
        ),
      ),
    );
  }

  // ============================================================
  // RATE / QTY / AMOUNT
  // ============================================================

  void _updateAmountDisplay() {
    final text = _format(_currentAmount);
    if (_amountController.text != text) {
      _amountController.text = text;
    }
  }

  InputDecoration _entryDecoration() {
    return const InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(),
      disabledBorder: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 11),
    );
  }

  Widget _buildEntryField({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    bool readOnly = false,
  }) {
    return _buildEntryBox(
      label: label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        showCursor: !readOnly,
        enableInteractiveSelection: !readOnly,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: readOnly
            ? null
            : [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
        onChanged: onChanged,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
        decoration: _entryDecoration(),
        style: const TextStyle(fontSize: 15, height: 1),
      ),
    );
  }

  Widget _buildRateQtyAmount() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildEntryField(
          label: 'RATE',
          controller: _rateController,
          focusNode: _rateFocus,
          onChanged: _rateChanged,
          onSubmitted: _rateSubmitted,
        ),
        const SizedBox(width: 12),
        _buildEntryField(
          label: 'QTY',
          controller: _qtyController,
          focusNode: _qtyFocus,
          onChanged: _qtyChanged,
          onSubmitted: _qtySubmitted,
        ),
        const SizedBox(width: 12),
        _buildEntryField(
          label: 'AMOUNT',
          controller: _amountController,
          readOnly: true,
        ),
      ],
    );
  }

  Widget _buildEntryBox({
    required String label,
    required Widget child,
  }) {
    return SizedBox(
      width: _entryBoxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _entryBoxHeight,
            width: _entryBoxWidth,
            child: ClipRect(
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TOP ACTION BUTTON
  // ============================================================

  Widget _topActionButton(
      String text,
      VoidCallback onPressed,
      ) {
    return SizedBox(
      width: 64,
      height: _entryBoxHeight,

      child: ElevatedButton(
        onPressed: onPressed,

        style:
        ElevatedButton.styleFrom(
          backgroundColor:
          buttonColor,

          foregroundColor:
          Colors.white,

          padding: EdgeInsets.zero,

          shape:
          RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(
              18,
            ),
          ),
        ),

        child: Text(
          text,
          style:
          const TextStyle(
            fontSize: 8.5,
            fontWeight:
            FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MAIN AREA
  // ============================================================

  Widget _buildMainArea() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Center(
                  child: _buildRateQtyAmount(),
                ),
              ),
              Expanded(
                child: _buildItemTable(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _topActionButton('MODIFY', _modifyItem),
              const SizedBox(height: 4),
              _topActionButton('DELETE', _deleteItem),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            width: 185,
            child: _buildTotals(),
          ),
        ),
      ],
    );
  }  // ============================================================
  // ITEM TABLE
  //
  // BEFORE ITEM:
  //
  // S.NO | QTY | RATE | AMOUNT | T AMT
  //
  // AFTER ITEM:
  //
  // S.NO | QTY | RATE | AMOUNT | T AMT |
  // CGST % | SGST % | IGST
  // ============================================================
  Widget _buildItemTable() {
    final bool showTax = _items.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        color: backgroundColor,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildTableHeader(showTax),
          Expanded(
            child: _items.isEmpty
                ? ColoredBox(color: backgroundColor)
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      return _buildTableRow(index, showTax);
                    },
                  ),
          ),
        ],
      ),
    );
  }  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildTableHeader(bool showTax) {
    return Container(
      height: 32,
      color: headerColor,
      child: Row(
        children: [
          _tableHeaderCell('S.no', 55),
          _tableHeaderCell('Qty', 65),
          _tableHeaderCell('RATE', 75),
          _tableHeaderCell('AMOUNT', 95),
          _tableHeaderCell('t amt', 95, last: !showTax),
          if (showTax) ...[
            _tableHeaderCell('CGST %', 70),
            _tableHeaderCell('SGST %', 70),
            _tableHeaderCell('IGST', 65, last: true),
          ],
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text, int flex, {bool last = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: borderColor, width: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildTableRow(
      int index,
      bool showTax,
      ) {
    final BillItem item =
    _items[index];

    final bool selected =
        _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex =
          selected ? null : index;
        });
      },

      child: Container(
        height: 34,

        color: selected
            ? const Color(
          0xFFFFE5A0,
        )
            : backgroundColor,

        child: Row(
          children: [
            _tableDataCell('${index + 1}', 55),
            _tableDataCell(_format(item.qty), 65),
            _tableDataCell(_format(item.rate), 75),
            _tableDataCell(_format(item.amount), 95),
            _tableDataCell(_format(item.grossAmt), 95, last: !showTax),
            if (showTax) ...[
              _tableDataCell(_format(item.cgstPct), 70),
              _tableDataCell(_format(item.sgstPct), 70),
              _tableDataCell(_format(item.igst), 65, last: true),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TABLE DATA CELL
  // ============================================================

  Widget _tableDataCell(String text, int flex, {bool last = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: borderColor, width: 0.6),
            bottom: BorderSide(color: borderColor, width: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, height: 1),
        ),
      ),
    );
  }

  // ============================================================
  // TOTALS
  // ============================================================

  Widget _buildTotals() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        _totalField('', _format(_totalQty)),
        const SizedBox(height: 3),
        _totalField('Total Amt', _format(_totalAmount)),
        const SizedBox(height: 3),
        _totalField('CGST', _format(_totalCgst)),
        const SizedBox(height: 3),
        _totalField('SGST', _format(_totalSgst)),
        const SizedBox(height: 3),
        _totalField('IGST', _format(_totalIgst)),
        const SizedBox(height: 8),
        const Text(
          'Grand Total',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 60,
          child: Container(
            color: Colors.white,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _format(_grandTotal),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 28,
          child: Container(
            color: Colors.white,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amountInWords(_grandTotal),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TOTAL FIELD
  // ============================================================

  Widget _totalField(
      String label,
      String value,
      ) {
    return SizedBox(
      height: 36,

      child: Row(
        children: [
          SizedBox(
            width: 72,

            child: Text(
              label,

              style:
              const TextStyle(
                fontSize: 10,
              ),
            ),
          ),

          Expanded(
            child: Container(
              height: 36,

              color: Colors.white,

              alignment:
              Alignment.centerRight,

              padding:
              const EdgeInsets
                  .symmetric(
                horizontal: 8,
              ),

              child: Text(
                value,

                style:
                const TextStyle(
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE
  // ============================================================

  Future<void> _selectDate() async {
    final DateTime? picked =
    await showDatePicker(
      context: context,

      initialDate: _billDate,

      firstDate:
      DateTime(2020),

      lastDate:
      DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _billDate = picked;
      });
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _rateTimer?.cancel();
    _qtyTimer?.cancel();
    _persistSession();

    _customerNameController.dispose();

    _mobileController.dispose();

    _rateController.dispose();

    _qtyController.dispose();

    _amountController.dispose();

    _rateFocus.dispose();

    _qtyFocus.dispose();

    super.dispose();
  }
}
