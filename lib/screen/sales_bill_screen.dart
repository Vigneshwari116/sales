import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sales/config/app_config.dart';
import 'package:sales/config/local_credentials.dart';
import 'package:sales/db/local_db.dart';
import 'package:sales/models/sale_bill.dart';
import 'package:sales/repositories/bill_repository.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/bill_print_service.dart';
import 'package:sales/services/session_service.dart';

import 'bill_item.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'login_screen.dart';
import 'sales_abstract_screen.dart';
import 'sales_ledger_screen.dart';
import 'printer_settings_screen.dart';
import 'package:sales/services/printer_settings_service.dart';

enum _ItemCellField {
  qty,
  rate,
  amount,
  grossAmt,
  cgstPct,
  sgstPct,
  igstPct,
}

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
  static const double _desktopBreakpoint = 900;
  static const double _sidebarBreakpoint = 700;
  static const double _sidebarWidth = 200;

  bool _sidebarOpen = false;

  // ============================================================
  // LOCATION (from login — not shown on screen)
  // ============================================================

  late String _selectedLocation;

  // Current bill number.
  int _billNo = 1;

  // Whether the bill has been saved/completed.
  bool _billSaved = false;

  bool _busy = false;
  bool _editModeEnabled = false;
  bool _showEditPasswordField = false;
  String? _editPasswordError;
  String? _currentBillLocalId;
  int? _editingRow;
  _ItemCellField? _editingField;
  TextEditingController? _cellEditController;

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

  final TextEditingController _editPasswordController =
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

    _selectedLocation = AppConfig.displayLocationName;
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

    if (session != null && session.location == _selectedLocation) {
      setState(() {
        _billNo = session.billNo;
        _billDate = session.billDate;
        _paymentMode = session.paymentMode;
        var customerName = session.customerName;
        if (customerName == 'CASH' && session.paymentMode == 'CASH') {
          customerName = '';
        }
        _customerNameController.text = customerName;
        _mobileController.text = session.mobile;
        _items
          ..clear()
          ..addAll(session.items);
        _billSaved = session.billSaved;
        _selectedIndex = null;
        _editModeEnabled = false;
        _currentBillLocalId = null;
      });
      return;
    }

    setState(() {
      _editModeEnabled = false;
      _currentBillLocalId = null;
    });

    await _loadBillNumber();
  }

  Future<void> _persistSession() async {
    await SessionService.saveBillSession(
      location: _selectedLocation,
      billNo: _billNo,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      billSaved: _billSaved,
    );
  }

  // ============================================================
  // LOAD BILL NUMBER (from this location's local DB only)
  // ============================================================

  Future<void> _loadBillNumber() async {
    var nextBillNo =
        await BillRepository.getNextBillNumber(_selectedLocation);

    if (!mounted) return;

    setState(() {
      _billNo = nextBillNo;
    });
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
          _addItem();
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

    _addItem();
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

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);

      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
      }

      if (_editingRow == index) {
        _editingRow = null;
        _editingField = null;
        _cellEditController?.dispose();
        _cellEditController = null;
      } else if (_editingRow != null && _editingRow! > index) {
        _editingRow = _editingRow! - 1;
      }

      _billSaved = false;
    });

    _persistSession();
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
    _editModeEnabled = false;
    _showEditPasswordField = false;
    _editPasswordError = null;
    _editPasswordController.clear();
    _currentBillLocalId = null;
    _editingRow = null;
    _editingField = null;
    _cellEditController?.dispose();
    _cellEditController = null;
  }

  void _onMobileDoubleTap() {
    if (_editModeEnabled) {
      return;
    }

    setState(() {
      _showEditPasswordField = true;
      _editPasswordError = null;
      _editPasswordController.clear();
    });
  }

  void _tryUnlockEditMode() {
    if (_editPasswordController.text != appPassword) {
      setState(() => _editPasswordError = 'Incorrect password');
      return;
    }

    setState(() {
      _editModeEnabled = true;
      _showEditPasswordField = false;
      _editPasswordError = null;
      _editPasswordController.clear();
    });
  }

  void _startCellEdit(int rowIndex, _ItemCellField field, String value) {
    _cellEditController?.dispose();
    _cellEditController = TextEditingController(text: value);

    setState(() {
      _editingRow = rowIndex;
      _editingField = field;
    });
  }

  void _commitCellEdit(int rowIndex, _ItemCellField field) {
    var text = _cellEditController?.text.trim() ?? '';
    _applyCellEdit(rowIndex, field, text);

    _cellEditController?.dispose();
    _cellEditController = null;

    setState(() {
      _editingRow = null;
      _editingField = null;
    });
  }

  void _applyCellEdit(int rowIndex, _ItemCellField field, String text) {
    var value = double.tryParse(text);
    if (value == null) {
      return;
    }

    var item = _items[rowIndex];

    switch (field) {
      case _ItemCellField.qty:
        if (value <= 0) return;
        item = item.copyWith(qty: value);
      case _ItemCellField.rate:
        if (value <= 0) return;
        item = item.copyWith(rate: value);
      case _ItemCellField.amount:
        var taxPct = item.totalTaxPct;
        var gross = taxPct == 0 ? value : value * (1 + taxPct / 100);
        if (item.qty <= 0) return;
        item = item.copyWith(rate: gross / item.qty);
      case _ItemCellField.grossAmt:
        if (item.qty <= 0) return;
        item = item.copyWith(rate: value / item.qty);
      case _ItemCellField.cgstPct:
        item = item.copyWith(cgstPct: value);
      case _ItemCellField.sgstPct:
        item = item.copyWith(sgstPct: value);
      case _ItemCellField.igstPct:
        item = item.copyWith(igstPct: value);
    }

    setState(() {
      _items[rowIndex] = item;
      _billSaved = false;
    });

    _persistSession();
  }

  String _cellEditValue(BillItem item, _ItemCellField field) {
    switch (field) {
      case _ItemCellField.qty:
        return _format(item.qty);
      case _ItemCellField.rate:
        return _format(item.rate);
      case _ItemCellField.amount:
        return _format(item.amount);
      case _ItemCellField.grossAmt:
        return _format(item.grossAmt);
      case _ItemCellField.cgstPct:
        return _format(item.cgstPct);
      case _ItemCellField.sgstPct:
        return _format(item.sgstPct);
      case _ItemCellField.igstPct:
        return _format(item.igstPct);
    }
  }

  // ============================================================
  // SAVE BILL
  // ============================================================

  Future<void> _saveBill() async {
    if (_busy) return;

    if (_items.isEmpty) {
      _showMessage('Add at least one item before saving');
      return;
    }

    setState(() => _busy = true);

    final bill = _buildCurrentBill();
    final result = await BillRepository.saveBill(
      bill,
      updateLocalId: _currentBillLocalId,
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() => _busy = false);
      _showMessage(result.error ?? 'Failed to save bill');
      return;
    }

    _currentBillLocalId = await LocalDb.instance.findLocalIdByBillNo(
          location: _selectedLocation,
          billNo: _billNo,
        ) ??
        _currentBillLocalId;

    final int savedBillNo = _billNo;

    try {
      await BillPrintService.saveReceiptToDesktop(bill);
    } catch (_) {
      // Desktop save is best-effort; bill is already persisted locally.
    }

    final defaultPrinter = await PrinterSettingsService.getDefaultPrinter();

    if (defaultPrinter == null || defaultPrinter.isEmpty) {
      if (!mounted) return;
      setState(() {
        _billSaved = true;
        _busy = false;
      });
      _showMessage(
        'No printer selected. Please choose one in Printer Settings.',
      );
    } else {
      try {
        await BillPrintService.printReceipt(
          bill,
          printerName: defaultPrinter,
        );
        if (!mounted) return;
        setState(() {
          _billSaved = true;
          _busy = false;
        });
        _showMessage('Bill $savedBillNo saved and printed');
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _billSaved = true;
          _busy = false;
        });
        _showMessage('Bill $savedBillNo saved (print failed: $e)');
      }
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

  void _openLedger() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalesLedgerScreen(location: _selectedLocation),
      ),
    );
  }

  void _openAbstract() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalesAbstractScreen(location: _selectedLocation),
      ),
    );
  }

  void _openPrinterSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrinterSettingsScreen(),
      ),
    );
  }

  SaleBill _buildCurrentBill() {
    return SaleBill(
      billNo: _billNo,
      location: _selectedLocation,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim(),
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

  // ============================================================
  // EXIT
  // ============================================================

  void _exitScreen() async {
    await _persistSession();
    await AppSessionService.onLogout();
    await AppConfig.clearLocation();
    await SessionService.clearLogin();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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

    final width = MediaQuery.sizeOf(context).width;
    final useSidebarLayout = width > _sidebarBreakpoint;
    final mobileBillLayout = width < _desktopBreakpoint;

    return _buildRootScaffold(
      context,
      useSidebarLayout: useSidebarLayout,
      mobileBillLayout: mobileBillLayout,
    );
  }

  Widget _buildRootScaffold(
    BuildContext context, {
    required bool useSidebarLayout,
    required bool mobileBillLayout,
  }) {
    final body = mobileBillLayout
        ? _buildMobileBody(context)
        : _buildDesktopBody();

    if (useSidebarLayout) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: _buildAppBar(
          mobileBillLayout: mobileBillLayout,
          useSidebarLayout: true,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sidebarOpen) ...[
              SizedBox(
                width: _sidebarWidth,
                child: _buildMenuPanel(
                  onClose: () => setState(() => _sidebarOpen = false),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
            ],
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      drawer: Drawer(
        child: _buildMenuPanel(
          onClose: () => Navigator.pop(context),
        ),
      ),
      appBar: _buildAppBar(
        mobileBillLayout: mobileBillLayout,
        useSidebarLayout: false,
      ),
      body: body,
    );
  }

  PreferredSizeWidget _buildAppBar({
    required bool mobileBillLayout,
    required bool useSidebarLayout,
  }) {
    if (mobileBillLayout) {
      return AppBar(
        title: const Text(
          'Sales Bill',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: !useSidebarLayout,
        leading: useSidebarLayout
            ? IconButton(
                icon: Icon(_sidebarOpen ? Icons.menu_open : Icons.menu),
                tooltip: _sidebarOpen ? 'Close menu' : 'Open menu',
                onPressed: () {
                  setState(() => _sidebarOpen = !_sidebarOpen);
                },
              )
            : null,
      );
    }

    return AppBar(
      toolbarHeight: 52,
      title: const SizedBox.shrink(),
      backgroundColor: const Color(0xFFD5D8D5),
      foregroundColor: Colors.black,
      elevation: 0,
      automaticallyImplyLeading: !useSidebarLayout,
      leading: useSidebarLayout
          ? IconButton(
              icon: Icon(_sidebarOpen ? Icons.menu_open : Icons.menu),
              tooltip: _sidebarOpen ? 'Close menu' : 'Open menu',
              onPressed: () {
                setState(() => _sidebarOpen = !_sidebarOpen);
              },
            )
          : null,
    );
  }

  Widget _buildDesktopBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Column(
        children: [
          _buildTopArea(),
          const SizedBox(height: 6),
          Expanded(child: _buildMainArea()),
        ],
      ),
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBillDetails(mobile: true),
          const SizedBox(height: 8),
          _buildCustomerDetails(),
          const SizedBox(height: 10),
          _buildRateQtyAmount(mobile: true),
          const SizedBox(height: 10),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.28,
            child: _buildItemTable(mobile: true),
          ),
          const SizedBox(height: 10),
          _buildTotals(pinToBottom: false),
        ],
      ),
    );
  }

  Widget _buildMenuPanel({required VoidCallback onClose}) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'REPORTS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.menu_book, size: 20),
                  title: const Text('LEDGER'),
                  onTap: () {
                    onClose();
                    _openLedger();
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 32, right: 16),
                  leading: const Icon(Icons.summarize_outlined, size: 20),
                  title: const Text('ABSTRACT'),
                  onTap: () {
                    onClose();
                    _openAbstract();
                  },
                ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('PRINTER SETTINGS'),
              onTap: () {
                onClose();
                _openPrinterSettings();
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('EXIT'),
              onTap: () {
                onClose();
                _exitScreen();
              },
            ),
          ],
        ),
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

  Widget _buildBillDetails({bool mobile = false}) {
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

          _buildButtons(mobile: mobile),
        ],
      ),
    );
  }

  // ============================================================
  // BUTTONS
  // ============================================================

  Widget _buildButtons({bool mobile = false}) {
    final buttonHeight = mobile ? 32.0 : 25.0;
    final fontSize = mobile ? 10.0 : 8.5;
    final horizontalPadding = mobile ? 10.0 : 7.0;

    Widget button(
        String text,
        VoidCallback onPressed,
        ) {
      return SizedBox(
        height: buttonHeight,

        child: ElevatedButton(
          onPressed: onPressed,

          style:
          ElevatedButton.styleFrom(
            backgroundColor:
            buttonColor,

            foregroundColor:
            Colors.white,

            padding:
            EdgeInsets
                .symmetric(
              horizontal: horizontalPadding,
            ),

            minimumSize:
            Size(0, buttonHeight),

            shape:
            RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(
                mobile ? 4 : 2,
              ),
            ),
          ),

          child: Text(
            text,
            style:
            TextStyle(
              fontSize: fontSize,
              fontWeight:
              FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: mobile ? 4 : 2,
      runSpacing: mobile ? 4 : 2,
      alignment: mobile ? WrapAlignment.center : WrapAlignment.start,
      children: [
        button('SAVE', _saveBill),
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
                child: GestureDetector(
                  onDoubleTap: _onMobileDoubleTap,
                  child: _smallTextField(
                    _mobileController,
                    number: true,
                  ),
                ),
              ),
            ],
          ),

          if (_showEditPasswordField && !_editModeEnabled) ...[
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 45,
                  child: Text(
                    'Password',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 27,
                        child: TextField(
                          controller: _editPasswordController,
                          obscureText: true,
                          autofocus: true,
                          onSubmitted: (_) => _tryUnlockEditMode(),
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                          ),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      if (_editPasswordError != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _editPasswordError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
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
    bool fullWidth = false,
  }) {
    return _buildEntryBox(
      label: label,
      fullWidth: fullWidth,
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

  Widget _buildRateQtyAmount({bool mobile = false}) {
    if (mobile) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _buildEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              fullWidth: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildEntryField(
              label: 'AMOUNT',
              controller: _amountController,
              readOnly: true,
              fullWidth: true,
            ),
          ),
        ],
      );
    }

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
    bool fullWidth = false,
  }) {
    return SizedBox(
      width: fullWidth ? double.infinity : _entryBoxWidth,
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
            width: fullWidth ? double.infinity : _entryBoxWidth,
            child: ClipRect(
              child: child,
            ),
          ),
        ],
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
  Widget _buildItemTable({bool mobile = false}) {
    final bool showTax = _items.isNotEmpty;
    const double mobileTableWidth = 624;

    Widget table = Container(
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

    if (!mobile) {
      return table;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: mobileTableWidth,
            height: constraints.maxHeight,
            child: table,
          ),
        );
      },
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
            _tableHeaderCell('IGST', 65),
          ],
          _tableDeleteHeaderCell(),
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

  Widget _tableDeleteHeaderCell() {
    return SizedBox(
      width: 34,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor, width: 0.6),
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
        _selectedIndex == index && !_editModeEnabled;

    Widget rowContent = Row(
      children: [
        _tableDataCell('${index + 1}', 55),
        _buildGridCell(index, _ItemCellField.qty, item, 65),
        _buildGridCell(index, _ItemCellField.rate, item, 75),
        _buildGridCell(index, _ItemCellField.amount, item, 95),
        _buildGridCell(
          index,
          _ItemCellField.grossAmt,
          item,
          95,
          last: !showTax,
        ),
        if (showTax) ...[
          _buildGridCell(index, _ItemCellField.cgstPct, item, 70),
          _buildGridCell(index, _ItemCellField.sgstPct, item, 70),
          _buildGridCell(
            index,
            _ItemCellField.igstPct,
            item,
            65,
            displayOverride: _format(item.igst),
            editOverride: _format(item.igstPct),
          ),
        ],
        _buildDeleteCell(index),
      ],
    );

    if (_editModeEnabled) {
      return Container(
        height: 34,
        color: backgroundColor,
        child: rowContent,
      );
    }

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

        child: rowContent,
      ),
    );
  }

  Widget _buildDeleteCell(int index) {
    return SizedBox(
      width: 34,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor, width: 0.6),
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.close, color: Colors.red, size: 16),
          tooltip: 'Remove item',
          onPressed: () => _removeItem(index),
        ),
      ),
    );
  }

  Widget _buildGridCell(
    int rowIndex,
    _ItemCellField field,
    BillItem item,
    int flex, {
    bool last = false,
    String? displayOverride,
    String? editOverride,
  }) {
    var displayText = displayOverride ?? _cellEditValue(item, field);
    var editText = editOverride ?? _cellEditValue(item, field);

    if (!_editModeEnabled) {
      return _tableDataCell(displayText, flex, last: last);
    }

    var isEditing =
        _editingRow == rowIndex && _editingField == field;

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
        child: isEditing
            ? TextField(
                controller: _cellEditController,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(fontSize: 10, height: 1),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _commitCellEdit(rowIndex, field),
                onEditingComplete: () => _commitCellEdit(rowIndex, field),
              )
            : GestureDetector(
                onTap: () => _startCellEdit(rowIndex, field, editText),
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  color: const Color(0xFFE8F8FF),
                  child: Text(
                    displayText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, height: 1),
                  ),
                ),
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

  Widget _buildTotals({bool pinToBottom = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pinToBottom) const Spacer(),
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
    _cellEditController?.dispose();
    _persistSession();

    _customerNameController.dispose();

    _mobileController.dispose();

    _editPasswordController.dispose();

    _rateController.dispose();

    _qtyController.dispose();

    _amountController.dispose();

    _rateFocus.dispose();

    _qtyFocus.dispose();

    super.dispose();
  }
}
