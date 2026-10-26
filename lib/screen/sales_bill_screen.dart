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
import 'package:intl/intl.dart';
import 'package:sales/screen/admin_day_bills_screen.dart';
import 'package:sales/screen/number%20to%20words.dart';
import 'login_screen.dart';
import 'sales_ledger_screen.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/services/gst_config_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';
import 'package:sales/widgets/sales_bill_focus_field.dart';
import 'package:sales/widgets/sales_bill_toolbar.dart';

class SalesBillScreen extends StatefulWidget {
  /// When true, navigation is provided by [StaffDashboardScreen].
  final bool embeddedInDashboard;

  /// When set (tests only), replaces the default [SalesLedgerScreen] route.
  @visibleForTesting
  final Widget Function(String location)? ledgerScreenBuilder;

  /// When set (tests only), skips async local DB bill-number load on open.
  @visibleForTesting
  final int? initialBillNo;

  /// When set (tests only), replaces the default save/print handler for 777.
  @visibleForTesting
  final Future<void> Function()? saveBillOverride;

  /// When false, bill tab is hidden inside [IndexedStack] — restore focus on return.
  final bool isSectionActive;

  const SalesBillScreen({
    super.key,
    this.embeddedInDashboard = false,
    this.isSectionActive = true,
    this.initialBillNo,
    this.ledgerScreenBuilder,
    this.saveBillOverride,
  });

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen> {
  // ============================================================
  // COLORS
  // ============================================================

  static const double _entryBoxWidth = SalesBillLayout.entryFieldWidth;
  static const double _entryBoxHeight = SalesBillLayout.entryFieldHeight;
  static const double _entryLabelSize = SalesBillLayout.entryLabelFontSize;
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
  bool _manualPushInProgress = false;
  String? _currentBillLocalId;
  String? _rateError;
  String? _qtyError;
  double _cgstPct = GstConfigService.defaultCgstPct;
  double _sgstPct = GstConfigService.defaultSgstPct;

  // ============================================================
  // BILL DATE
  // ============================================================

  DateTime _billDate = DateTime.now();

  // ============================================================
  // PAYMENT
  // ============================================================

  String _paymentMode = 'CASH';

  final List<String> _paymentModes = const ['CASH', 'CARD', 'UPI'];

  // ============================================================
  // CUSTOMER
  // ============================================================

  final TextEditingController _customerNameController = TextEditingController();

  final TextEditingController _mobileController = TextEditingController();

  // ============================================================
  // RATE / QTY
  // ============================================================

  final TextEditingController _rateController = TextEditingController(
    text: '0',
  );

  final TextEditingController _qtyController = TextEditingController(text: '0');

  final TextEditingController _amountController = TextEditingController(
    text: '0',
  );

  final FocusNode _rateFocus = FocusNode();

  final FocusNode _qtyFocus = FocusNode();

  final FocusNode _nameFocus = FocusNode();

  final FocusNode _mobileFocus = FocusNode();

  late final FocusNode _paymentFocus = FocusNode(onKeyEvent: _onPaymentKey);

  String _lastFocusField = 'payment';

  // ============================================================
  // AUTO FOCUS TIMERS — removed; field advance is Enter-only.
  // ============================================================

  // ============================================================
  // ITEMS
  // ============================================================

  final List<BillItem> _items = [];

  int? _selectedIndex;

  // Password-gated edit for line items in the excel table.
  bool _editUnlocked = false;
  bool _showPasswordField = false;
  String? _passwordError;
  final TextEditingController _passwordController = TextEditingController();
  int? _editingIndex;
  final TextEditingController _editRateController = TextEditingController();
  final TextEditingController _editQtyController = TextEditingController();

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _selectedLocation = AppConfig.displayLocationName;
    _rateController.text = '0';
    _qtyController.text = '0';

    _rateFocus.addListener(() => _onNumericFocus(_rateFocus, _rateController));
    _qtyFocus.addListener(() => _onNumericFocus(_qtyFocus, _qtyController));
    _nameFocus.addListener(() => _onFieldFocused('name'));
    _mobileFocus.addListener(() => _onFieldFocused('mobile'));
    _rateFocus.addListener(() {
      if (_rateFocus.hasFocus) _onFieldFocused('rate');
    });
    _qtyFocus.addListener(() {
      if (_qtyFocus.hasFocus) _onFieldFocused('qty');
    });
    _paymentFocus.addListener(() {
      if (_paymentFocus.hasFocus) {
        _onFieldFocused('payment');
        setState(() {});
      }
    });

    _manualPushInProgress = SyncService.instance.manualPushInProgress.value;
    SyncService.instance.manualPushInProgress.addListener(_onManualPushChanged);

    _loadGstRates();

    if (widget.initialBillNo != null) {
      _billNo = widget.initialBillNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSavedFocus();
      });
    } else {
      _restoreSessionOrLoadBill().then((_) {
        if (mounted) {
          _restoreSavedFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SalesBillScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSectionActive && !oldWidget.isSectionActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSavedFocus();
      });
    }
  }

  void _onNumericFocus(FocusNode node, TextEditingController controller) {
    if (!node.hasFocus) return;
    final text = controller.text.trim();
    if (text == '0' || text == '0.0' || text == '0.00') {
      controller.clear();
    }
  }

  void _onFieldFocused(String field) {
    _lastFocusField = field;
    SessionService.saveFocusField(field);
  }

  Future<void> _restoreSavedFocus() async {
    final saved = await SessionService.loadFocusField();
    final field = saved ?? _lastFocusField;
    switch (field) {
      case 'name':
        _focusName();
      case 'mobile':
        _focusMobile();
      case 'rate':
        _focusRate();
      case 'qty':
        _focusQty();
      case 'payment':
      default:
        _focusPayment();
    }
  }

  void _focusPayment() {
    if (!mounted) return;
    _paymentFocus.requestFocus();
  }

  void _focusName() {
    if (!mounted) return;
    _nameFocus.requestFocus();
  }

  void _focusMobile() {
    if (!mounted) return;
    _mobileFocus.requestFocus();
  }

  KeyEventResult _onPaymentKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _focusName();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _cyclePayment(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _cyclePayment(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _cyclePayment(int delta) {
    final current = _paymentModes.indexOf(_paymentMode);
    final index = current < 0 ? 0 : current;
    final next = (index + delta + _paymentModes.length) % _paymentModes.length;
    setState(() => _paymentMode = _paymentModes[next]);
  }

  void _onManualPushChanged() {
    if (!mounted) return;
    setState(() {
      _manualPushInProgress = SyncService.instance.manualPushInProgress.value;
    });
  }

  bool get _isEntryLocked => _busy || _manualPushInProgress;

  Future<void> _loadGstRates() async {
    final cgst = await GstConfigService.cgstPct();
    final sgst = await GstConfigService.sgstPct();
    if (!mounted) return;
    setState(() {
      _cgstPct = cgst;
      _sgstPct = sgst;
    });
  }

  Future<void> _syncNow() async {
    final result = await SyncService.instance.manualPush(_selectedLocation);

    if (!mounted) return;

    _showMessage(result.summaryMessage);
  }

  Future<void> _restoreSessionOrLoadBill() async {
    final session = await SessionService.loadBillSession();

    if (!mounted) return;

    if (session != null && session.location == _selectedLocation) {
      setState(() {
        _billNo = session.billNo;
        _billDate = session.billDate;
        _paymentMode = session.paymentMode == 'PHONE PEE'
            ? 'UPI'
            : session.paymentMode;
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
        _currentBillLocalId = null;
      });
      return;
    }

    setState(() {
      _currentBillLocalId = null;
    });

    await _loadBillNumber();
    if (!mounted) return;
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
    var nextBillNo = await BillRepository.getNextBillNumber(_selectedLocation);

    if (!mounted) return;

    setState(() {
      _billNo = nextBillNo;
    });
  }

  Future<void> _populateFromSavedBill(SaleBill bill) async {
    String? localId;
    try {
      localId = await LocalDb.instance.findLocalIdByBillNo(
        location: bill.location,
        billNo: bill.billNo,
      );
    } catch (_) {
      // Best-effort lookup for edit/save tracking.
    }

    if (!mounted) return;

    setState(() {
      _billNo = bill.billNo;
      _billDate = bill.billDate;
      _paymentMode = bill.paymentMode;
      _customerNameController.text = bill.customerName;
      _mobileController.text = bill.mobile;
      _items
        ..clear()
        ..addAll(bill.items.map((item) => item.copyWith()));
      _selectedIndex = null;
      _editUnlocked = false;
      _showPasswordField = false;
      _passwordError = null;
      _editingIndex = null;
      _billSaved = true;
      _currentBillLocalId = localId;
      _rateController.text = '0';
      _qtyController.text = '0';
    });

    await _persistSession();
  }

  Future<void> _goToPreviousBill() async {
    if (_busy) return;

    final previous = await BillRepository.getPreviousBill(
      location: _selectedLocation,
      beforeBillNo: _billNo,
    );

    if (!mounted) return;

    if (previous == null) {
      _showMessage('No previous bill');
      return;
    }

    await _populateFromSavedBill(previous);
  }

  Future<void> _goToNextBill() async {
    if (_busy) return;

    final next = await BillRepository.getNextBill(
      location: _selectedLocation,
      afterBillNo: _billNo,
    );

    if (!mounted) return;

    if (next != null) {
      await _populateFromSavedBill(next);
      return;
    }

    final nextBillNo = await BillRepository.getNextBillNumber(
      _selectedLocation,
    );
    if (!mounted) return;

    if (_billNo >= nextBillNo) {
      _showMessage('No next bill');
      return;
    }

    setState(() {
      _billNo = nextBillNo;
      _clearCurrentBill();
    });
    await _persistSession();
  }

  Future<void> _openTodaySales() async {
    final today = DateTime.now();
    final day =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final title = 'Today — ${DateFormat('dd MMM yyyy').format(today)}';

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminDayBillsScreen(
          day: day,
          title: title,
          location: _selectedLocation,
          adminFullEdit: false,
        ),
      ),
    );
  }

  Future<void> _confirmRemoveItem(int index) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove line?'),
        content: Text('Remove line ${index + 1} from this bill?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (remove == true) {
      _removeItem(index);
    }
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
  // RATE CHANGED — updates live amount display only (no auto-advance).
  // ============================================================

  void _rateChanged(String value) {
    setState(() {
      if (_rateError != null) {
        _rateError = null;
      }
    });
  }

  void _qtyChanged(String value) {
    setState(() {
      if (_qtyError != null) {
        _qtyError = null;
      }
    });
  }

  void _clearEntryErrors() {
    _rateError = null;
    _qtyError = null;
  }

  bool _validateRate({bool focusOnError = true}) {
    final rate = double.tryParse(_rateController.text);
    if (rate == null || rate <= 0) {
      setState(() => _rateError = 'Rate must be greater than 0');
      if (focusOnError) _focusRate();
      return false;
    }
    setState(() => _rateError = null);
    return true;
  }

  bool _validateQty({bool focusOnError = true}) {
    final qty = double.tryParse(_qtyController.text);
    if (qty == null || qty <= 0) {
      setState(() => _qtyError = 'Quantity must be greater than 0');
      if (focusOnError) _focusQty();
      return false;
    }
    setState(() => _qtyError = null);
    return true;
  }

  // ============================================================
  // RATE / QTY ENTER — 777 prints table bill; other rates go to qty
  // ============================================================

  static const String _printCode = '777';

  void _rateSubmitted() {
    final rateText = _rateController.text.trim();

    if (rateText == _printCode) {
      _rateController.text = '0';
      if (_items.isEmpty) {
        _showMessage('Add items before printing');
        return;
      }
      final save = widget.saveBillOverride ?? _saveBill;
      unawaited(save());
      return;
    }

    if (!_validateRate()) {
      return;
    }

    _focusQty();
  }

  void _qtySubmitted() {
    if (!_validateRate() || !_validateQty()) {
      return;
    }

    _addItem();
  }

  void _addItem() {
    if (!_validateRate() || !_validateQty()) {
      return;
    }

    final rate = double.parse(_rateController.text);
    final qty = double.parse(_qtyController.text);

    setState(() {
      _clearEntryErrors();
      _items.add(
        BillItem(
          qty: qty,
          rate: rate,
          cgstPct: _cgstPct,
          sgstPct: _sgstPct,
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

  void _onMobileDoubleTap() {
    if (_editUnlocked || _showPasswordField) {
      return;
    }

    setState(() {
      _showPasswordField = true;
      _passwordError = null;
      _passwordController.clear();
    });
  }

  void _tryUnlockEdit() {
    if (_passwordController.text == billEditPassword) {
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
    if (!_editUnlocked) {
      return;
    }

    setState(() {
      _editingIndex = index;
      _editRateController.text = _items[index].rate.toString();
      _editQtyController.text = _items[index].qty.toString();
    });
  }

  void _applyLineEdit() {
    final index = _editingIndex;
    if (index == null) {
      return;
    }

    final rate = double.tryParse(_editRateController.text.trim());
    final qty = double.tryParse(_editQtyController.text.trim());

    if (rate == null || rate <= 0 || qty == null || qty <= 0) {
      _showMessage('Enter valid rate and quantity');
      return;
    }

    setState(() {
      _items[index] = _items[index].copyWith(rate: rate, qty: qty);
      _editingIndex = null;
      _billSaved = false;
    });

    _persistSession();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);

      if (_selectedIndex == index) {
        _selectedIndex = null;
      } else if (_selectedIndex != null && _selectedIndex! > index) {
        _selectedIndex = _selectedIndex! - 1;
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
    _editUnlocked = false;
    _showPasswordField = false;
    _passwordError = null;
    _editingIndex = null;

    _billSaved = false;
    _currentBillLocalId = null;
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

    try {
      final bill = _buildCurrentBill();
      final result = await BillRepository.saveBill(
        bill,
        updateLocalId: _currentBillLocalId,
      );

      if (!mounted) return;

      if (!result.ok) {
        _showMessage(result.error ?? 'Failed to save bill');
        return;
      }

      try {
        _currentBillLocalId =
            await LocalDb.instance.findLocalIdByBillNo(
              location: _selectedLocation,
              billNo: _billNo,
            ) ??
            _currentBillLocalId;
      } catch (_) {
        // Bill is saved; local id lookup is best-effort.
      }

      final int savedBillNo = _billNo;

      final defaultPrinter =
          await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal) ??
          '';

      try {
        await BillPrintService.printReceipt(
          bill,
          printerName: defaultPrinter,
          type: PrinterType.thermal,
        );
        _showMessage('Bill $savedBillNo saved and printed');
      } catch (e) {
        _showMessage('Bill $savedBillNo saved (print failed: $e)');
      }

      if (!mounted) return;

      await _loadBillNumber();

      if (!mounted) return;

      setState(() {
        _billSaved = true;
        _clearCurrentBill();
      });

      await _persistSession();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPayment();
      });
    } catch (e) {
      if (mounted) {
        _showMessage('Save failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openLedger() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            widget.ledgerScreenBuilder?.call(_selectedLocation) ??
            SalesLedgerScreen(location: _selectedLocation),
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
    return _items.fold(0, (sum, item) => sum + item.qty);
  }

  // ============================================================
  // TOTAL TAXABLE AMOUNT
  // ============================================================

  double get _totalAmount {
    return _items.fold(0, (sum, item) => sum + item.amount);
  }

  // ============================================================
  // TOTAL CGST
  // ============================================================

  double get _totalCgst {
    return _items.fold(0, (sum, item) => sum + item.cgst);
  }

  // ============================================================
  // TOTAL SGST
  // ============================================================

  double get _totalSgst {
    return _items.fold(0, (sum, item) => sum + item.sgst);
  }

  // ============================================================
  // TOTAL IGST
  // ============================================================

  double get _totalIgst {
    return _items.fold(0, (sum, item) => sum + item.igst);
  }

  // ============================================================
  // GRAND TOTAL
  //
  // GST INCLUSIVE
  // ============================================================

  double get _grandTotal {
    return _items.fold(0, (sum, item) => sum + item.netAmt);
  }

  /// Sum of visible AMOUNT column (qty × rate / grossAmt).
  double get _displayAmountTotal {
    return _items.fold(0, (sum, item) => sum + item.grossAmt);
  }

  // ============================================================
  // CURRENT AMOUNT
  // ============================================================

  double get _currentAmount {
    final double rate = double.tryParse(_rateController.text) ?? 0;

    final double qty = double.tryParse(_qtyController.text) ?? 0;

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

  String _formatGrandDisplay(double value) {
    return value.toStringAsFixed(2);
  }

  String _formatPcs(double value) {
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

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    _updateAmountDisplay();

    final width = MediaQuery.sizeOf(context).width;
    final useSidebarLayout =
        !widget.embeddedInDashboard && width > _sidebarBreakpoint;
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

    if (widget.embeddedInDashboard) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _buildLockedBody(body),
      );
    }

    if (useSidebarLayout) {
      return Scaffold(
        backgroundColor: AppColors.background,
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
            Expanded(child: _buildLockedBody(body)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        child: _buildMenuPanel(onClose: () => Navigator.pop(context)),
      ),
      appBar: _buildAppBar(
        mobileBillLayout: mobileBillLayout,
        useSidebarLayout: false,
      ),
      body: _buildLockedBody(body),
    );
  }

  Widget _buildLockedBody(Widget child) {
    return Stack(
      children: [
        AbsorbPointer(absorbing: _isEntryLocked, child: child),
        if (_manualPushInProgress)
          Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Syncing bills to server...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar({
    required bool mobileBillLayout,
    required bool useSidebarLayout,
  }) {
    if (mobileBillLayout) {
      return sectionHeaderAppBar(
        'Sales Bill',
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
      backgroundColor: AppColors.headerBand,
      foregroundColor: AppColors.navy,
      iconTheme: const IconThemeData(color: AppColors.navy),
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
    return _buildBillMainLayout(compact: false);
  }

  Widget _buildMobileBody(BuildContext context) {
    return _buildBillMainLayout(compact: true);
  }

  Widget _buildBillMainLayout({required bool compact}) {
    final padding = compact
        ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
        : const EdgeInsets.fromLTRB(12, 10, 12, 10);
    final contentWidth = SalesBillLayout.inputRowWidth;

    return Padding(
      padding: padding,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SalesBillToolbar(
              onTodaySales: _openTodaySales,
              onPrevious: _goToPreviousBill,
              onNext: _goToNextBill,
              onSave: _saveBill,
              busy: _busy,
            ),
            const SizedBox(height: 10),
            if (compact) ...[
              _buildBillDetails(mobile: true),
              const SizedBox(height: 8),
              _buildCustomerDetails(compact: true),
            ] else
              _buildTopBoxesRow(),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: contentWidth,
                child: _buildRateQtyAmount(mobile: compact),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: contentWidth,
                  child: _buildItemTableSection(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBoxesRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final stack = maxW < 720;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBillDetails(),
              const SizedBox(height: 8),
              _buildCustomerDetails(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: _buildBillDetails()),
            const SizedBox(width: 10),
            Expanded(flex: 6, child: _buildCustomerDetails()),
          ],
        );
      },
    );
  }

  /// Staff POS menu — ledger + sync stay here for offline locations without
  /// an admin present. Abstract and printer settings are admin-dashboard only.
  Widget _buildMenuPanel({required VoidCallback onClose}) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book, size: 20),
              title: const Text('LEDGER'),
              onTap: () {
                onClose();
                _openLedger();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('SYNC NOW'),
              enabled: !_manualPushInProgress,
              onTap: _manualPushInProgress
                  ? null
                  : () {
                      onClose();
                      _syncNow();
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
  // BILL DETAILS
  // ============================================================

  Widget _buildBillDetails({bool mobile = false}) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),

      padding: const EdgeInsets.all(5),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,

        children: [
          Row(
            children: [
              const SizedBox(
                width: 58,
                child: Text('BILL NO:', style: TextStyle(fontSize: 10)),
              ),

              // ==================================================
              // FIXED BILL NUMBER
              // ==================================================
              Container(
                width: SalesBillLayout.billNoBoxWidth,
                height: SalesBillLayout.billNoBoxHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SalesBillLayout.billNoFill,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$_billNo',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: SizedBox(
                  height: SalesBillLayout.billRowControlHeight,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: DropdownButtonFormField<String>(
                      key: const Key('bill_payment_dropdown'),
                      value: _paymentMode,
                      focusNode: _paymentFocus,
                      isDense: true,
                      isExpanded: true,
                      decoration: salesBillFieldDecoration(
                        focused: _paymentFocus.hasFocus,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      style: const TextStyle(fontSize: 13, color: Colors.black),

                      items: _paymentModes.map((item) {
                        return DropdownMenuItem(
                          value: item,
                          child: Text(
                            item,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }).toList(),

                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setState(() {
                          _paymentMode = value;
                        });
                        _onFieldFocused('name');
                        _focusName();
                      },
                    ),
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
                child: Text('BILL DATE:', style: TextStyle(fontSize: 10)),
              ),

              InkWell(
                onTap: null,
                child: Container(
                  width: 120,
                  height: SalesBillLayout.billRowControlHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SalesBillLayout.dateBoxFill,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${_billDate.day.toString().padLeft(2, '0')}/'
                    '${_billDate.month.toString().padLeft(2, '0')}/'
                    '${_billDate.year}',
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ============================================================
  // CUSTOMER DETAILS
  // ============================================================

  Widget _buildCustomerDetails({bool compact = false}) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CUSTOMER DETAILS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildLabeledCustomerField(
            label: 'NAME',
            child: _customerTextField(
              _customerNameController,
              fieldKey: const Key('bill_name_field'),
              focusNode: _nameFocus,
              focusOrder: 2,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _focusMobile(),
            ),
          ),
          const SizedBox(height: 8),
          _buildLabeledCustomerField(
            label: 'MOBILE',
            child: GestureDetector(
              onDoubleTap: _onMobileDoubleTap,
              child: _customerTextField(
                _mobileController,
                number: true,
                fieldKey: const Key('bill_mobile_field'),
                focusNode: _mobileFocus,
                focusOrder: 3,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _focusRate(),
              ),
            ),
          ),
          if (_showPasswordField && !_editUnlocked) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(
                  width: 52,
                  child: Text('Password', style: TextStyle(fontSize: 10)),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const Key('bill_edit_password_field'),
                    controller: _passwordController,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => _tryUnlockEdit(),
                    style: const TextStyle(fontSize: 10),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 30,
                  child: ElevatedButton(
                    key: const Key('bill_edit_password_ok'),
                    onPressed: _tryUnlockEdit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('OK', style: TextStyle(fontSize: 10)),
                  ),
                ),
              ],
            ),
            if (_passwordError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _passwordError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 9),
                ),
              ),
          ],
          if (_editUnlocked)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Edit mode — tap a line to correct rate/qty.',
                style: TextStyle(fontSize: 9, color: AppColors.success),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLabeledCustomerField({
    required String label,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }

  Widget _customerTextField(
    TextEditingController controller, {
    bool number = false,
    Key? fieldKey,
    FocusNode? focusNode,
    double? focusOrder,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    Widget field = SizedBox(
      height: SalesBillLayout.entryFieldHeight,
      child: SalesBillFocusTextField(
        fieldKey: fieldKey,
        controller: controller,
        focusNode: focusNode,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        keyboardType: number ? TextInputType.phone : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        textAlign: TextAlign.left,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
    );
    if (focusOrder != null) {
      field = FocusTraversalOrder(
        order: NumericFocusOrder(focusOrder),
        child: field,
      );
    }
    return field;
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

  Widget _buildInlineEntryField({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    bool readOnly = false,
    bool blockTabTraversal = false,
    TextInputAction? textInputAction,
    Key? fieldKey,
    double? focusOrder,
  }) {
    Widget input = SizedBox(
      width: _entryBoxWidth,
      height: _entryBoxHeight,
      child: SalesBillFocusTextField(
        fieldKey: fieldKey,
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        blockTabTraversal: blockTabTraversal,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        inputFormatters: readOnly
            ? null
            : [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
        onChanged: onChanged,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
        style: const TextStyle(
          fontSize: SalesBillLayout.entryFieldFontSize,
          height: 1.1,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    if (focusOrder != null) {
      input = FocusTraversalOrder(
        order: NumericFocusOrder(focusOrder),
        child: input,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: _entryLabelSize,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 6),
        input,
      ],
    );
  }

  Widget _buildRateQtyAmount({bool mobile = false}) {
    final fields = mobile
        ? Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildInlineEntryField(
                label: 'rate',
                controller: _rateController,
                focusNode: _rateFocus,
                onChanged: _rateChanged,
                onSubmitted: _rateSubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.done,
                fieldKey: const Key('bill_rate_field'),
                focusOrder: 4,
              ),
              _buildInlineEntryField(
                label: 'qty',
                controller: _qtyController,
                focusNode: _qtyFocus,
                onChanged: _qtyChanged,
                onSubmitted: _qtySubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.done,
                fieldKey: const Key('bill_qty_field'),
                focusOrder: 5,
              ),
              _buildInlineEntryField(
                label: 'amount',
                controller: _amountController,
                readOnly: true,
                focusOrder: 6,
                fieldKey: const Key('bill_amount_field'),
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInlineEntryField(
                label: 'rate',
                controller: _rateController,
                focusNode: _rateFocus,
                onChanged: _rateChanged,
                onSubmitted: _rateSubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.done,
                fieldKey: const Key('bill_rate_field'),
                focusOrder: 4,
              ),
              const SizedBox(width: SalesBillLayout.entryFieldGap),
              _buildInlineEntryField(
                label: 'qty',
                controller: _qtyController,
                focusNode: _qtyFocus,
                onChanged: _qtyChanged,
                onSubmitted: _qtySubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.done,
                fieldKey: const Key('bill_qty_field'),
                focusOrder: 5,
              ),
              const SizedBox(width: SalesBillLayout.entryFieldGap),
              _buildInlineEntryField(
                label: 'amount',
                controller: _amountController,
                readOnly: true,
                focusOrder: 6,
                fieldKey: const Key('bill_amount_field'),
              ),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: mobile
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.start,
      children: [
        fields,
        if (_rateError != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _rateError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 10),
            ),
          ),
        ],
        if (_qtyError != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _qtyError!,
              style: const TextStyle(color: AppColors.danger, fontSize: 10),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // ITEM TABLE
  //
  // BEFORE ITEM (Enter on Qty adds first row):
  //
  // S.NO | RATE | QTY | AMOUNT | Total | CGST % | SGST % | IGST | X
  // ============================================================

  Widget _buildItemTableSection() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTableHeader(),
          Expanded(
            child: _items.isEmpty
                ? const ColoredBox(color: AppColors.background)
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      if (_editingIndex == index) {
                        return _buildEditRow(index);
                      }
                      return _buildTableRow(index);
                    },
                  ),
          ),
          _buildTableFooter(),
        ],
      ),
    );
  }

  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildTableHeader() {
    return Container(
      height: 36,
      color: AppColors.tableHeader,
      child: Row(
        children: [
          _tableHeaderCell('S.NO', 45),
          _tableHeaderCell('RATE', 80),
          _tableHeaderCell('QTY', 70),
          _tableHeaderCell('AMOUNT', 100, last: true),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text, int flex, {bool last = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildEditRow(int index) {
    return Container(
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Line ${index + 1}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 10),
          _buildEditLineField(label: 'Rate', controller: _editRateController),
          const SizedBox(width: 10),
          _buildEditLineField(label: 'Qty', controller: _editQtyController),
          const SizedBox(width: 10),
          SizedBox(
            height: _entryBoxHeight,
            child: ElevatedButton(
              key: const Key('bill_edit_line_ok'),
              onPressed: _applyLineEdit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, _entryBoxHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('OK', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditLineField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: _entryLabelSize,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _entryBoxWidth,
          height: _entryBoxHeight,
          child: SalesBillFocusTextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: SalesBillLayout.entryFieldFontSize,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildTableRow(int index) {
    final BillItem item = _items[index];
    final bool selected = _selectedIndex == index;

    return GestureDetector(
      key: Key('bill_table_row_$index'),
      onTap: () {
        if (_editUnlocked) {
          _startEditLine(index);
          return;
        }

        setState(() {
          _selectedIndex = selected ? null : index;
        });
      },
      onLongPress: () => _confirmRemoveItem(index),
      onSecondaryTap: () => _confirmRemoveItem(index),
      child: Container(
        height: 36,
        color: selected ? const Color(0xFFFFE5A0) : AppColors.background,
        child: Row(
          children: [
            _tableDataCell('${index + 1}', 45),
            _tableDataCell(_format(item.rate), 80),
            _tableDataCell(_format(item.qty), 70),
            _tableDataCell(_format(item.grossAmt), 100, last: true),
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
        height: 36,
        decoration: BoxDecoration(
          border: Border(
            right: last
                ? BorderSide.none
                : BorderSide(color: AppColors.border, width: 0.6),
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, height: 1),
        ),
      ),
    );
  }

  Widget _buildTableFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFooterAmountRow(
          labelLeft: 'Total',
          qtyLabel: '${_formatPcs(_totalQty)} (total pcs)',
          amountText: _format(_displayAmountTotal),
          bandColor: AppColors.tableHeader,
        ),
        _buildGrandFooterRow(),
      ],
    );
  }

  Widget _buildFooterAmountRow({
    required String labelLeft,
    required String qtyLabel,
    required String amountText,
    required Color bandColor,
  }) {
    return Container(
      color: bandColor,
      height: 38,
      child: Row(
        children: [
          _tableFooterCell(labelLeft, 45, align: Alignment.centerLeft),
          _tableFooterCell('', 80),
          _tableFooterCell(qtyLabel, 70),
          _tableFooterCell(
            amountText,
            100,
            last: true,
            fontWeight: FontWeight.w700,
          ),
        ],
      ),
    );
  }

  Widget _buildGrandFooterRow() {
    return Container(
      color: AppColors.headerBand,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 45 + 80 + 70,
            child: Text(
              amountInWords(_grandTotal),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: 0.15,
                color: AppColors.navy,
              ),
            ),
          ),
          Expanded(
            flex: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'GRAND',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                Text(
                  _formatGrandDisplay(_grandTotal),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableFooterCell(
    String text,
    int flex, {
    bool last = false,
    Alignment align = Alignment.center,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 38,
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border, width: 0.6),
            right: last
                ? BorderSide.none
                : BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: align == Alignment.centerLeft
              ? TextAlign.left
              : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: fontWeight,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    SyncService.instance.manualPushInProgress.removeListener(
      _onManualPushChanged,
    );
    _persistSession();

    _customerNameController.dispose();

    _mobileController.dispose();

    _passwordController.dispose();
    _editRateController.dispose();
    _editQtyController.dispose();

    _rateController.dispose();

    _qtyController.dispose();

    _amountController.dispose();

    _rateFocus.dispose();

    _qtyFocus.dispose();

    _nameFocus.dispose();

    _mobileFocus.dispose();

    _paymentFocus.dispose();

    super.dispose();
  }
}
