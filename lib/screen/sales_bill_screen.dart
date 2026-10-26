
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'sales_ledger_screen.dart';
import 'package:sales/services/printer_settings_service.dart';
import 'package:sales/services/gst_config_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/compact_layout.dart';

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

  static const Color billNoColor = Color(0xFF7FE8E8);

  /// Bill screen typography — local only; other screens stay on [AppTextSizes].
  static const double _entryFontSize = 24;
  static const double _normalFontSize = 18;
  static const double _gridFontSize = 10;
  static const double _gridMinFontSize = 8;

  static const double _topButtonWidth = 150;
  static const double _topButtonHeight = 44;
  static const double _billLabelColWidth = 96;
  static const double _billNoBoxWidth = 90;
  static const double _upiBoxWidth = 130;
  static const double _billDateBoxWidth = 130;
  static const double _compactFieldHeight = 40;
  static const double _customerBoxWidth = 220;
  static const double _customerBoxHeight = 36;
  static const double _numericBoxWidth = 150;
  static const double _entryColumnGap = 12;
  static const double _entryBoxHeight = 52;
  static const double _entryFieldVerticalPadding = 14;
  static const double _customerFieldVerticalPadding = 9;
  static const double _topAreaGap = 8;
  static const double _actionButtonGap = 12;
  static const double _framesGap = 12;
  static const double _framePadding = 8;
  static const double _tableHeaderHeight = 26;
  static const double _tableRowHeight = 22;
  static const double _editRowHeight = 68;
  static const double _gridFooterTotalRowHeight = 28;
  static const double _gridFooterGrandRowHeight = 48;
  static const double _gridFooterHeight =
      _gridFooterTotalRowHeight + _gridFooterGrandRowHeight;
  static const double _grandTotalLabelFontSize = 20;
  static const double _grandTotalValueFontSize = 28;
  static const double _grandTotalWordsFontSize = 13;
  static const double _deleteColWidth = 48;
  static const double _entryBlockWidth =
      (_numericBoxWidth * 3) + (_entryColumnGap * 2);
  static const double _gridTotalWidth = _entryBlockWidth + _deleteColWidth;
  static const double _gridVisibleItemRows = 10;
  static const double _gridBodyHeight = _tableRowHeight * _gridVisibleItemRows;
  static const double _gridHScrollbarStripHeight = 12;
  static const double _gridBodyScrollZoneHeight =
      _gridBodyHeight + _gridHScrollbarStripHeight;
  static const double _gridFrameHeight =
      _tableHeaderHeight + _gridBodyScrollZoneHeight + _gridFooterHeight;
  static const double _desktopChromeEstimate = 268;
  static const double _entryValidationSlack = 28;
  static const double _gridMinScrollHeight = _gridFrameHeight;
  static const double _gridColWidth = 116;
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

  final List<String> _paymentModes = const [
    'CASH',
    'CARD',
    'UPI',
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

  final FocusNode _nameFocus = FocusNode();

  final FocusNode _mobileFocus = FocusNode();

  final FocusNode _paymentFocus = FocusNode();
  final FocusNode _saveSaleFocus = FocusNode();

  final ScrollController _gridHeaderHScrollController = ScrollController();
  final ScrollController _gridHScrollController = ScrollController();
  final ScrollController _gridFooterHScrollController = ScrollController();
  final ScrollController _gridVScrollController = ScrollController();
  final ScrollController _gridDeleteVScrollController = ScrollController();
  bool _syncingGridScroll = false;

  String _lastFocusField = 'name';

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
    _paymentFocus.addListener(_onPaymentFocusChanged);
    _rateFocus.addListener(() => _onEntryFocusChanged(_rateFocus));
    _qtyFocus.addListener(() => _onEntryFocusChanged(_qtyFocus));
    _gridHScrollController.addListener(_syncHeaderScrollFromBody);
    _gridVScrollController.addListener(_syncDeleteScrollFromGrid);
    _gridDeleteVScrollController.addListener(_syncGridScrollFromDelete);

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
      case 'mobile':
        _focusMobile();
      case 'rate':
        _focusRate();
      case 'qty':
        _focusQty();
      case 'name':
      default:
        _focusName();
    }
  }

  void _focusName() {
    if (!mounted) return;
    _nameFocus.requestFocus();
  }

  void _focusMobile() {
    if (!mounted) return;
    _mobileFocus.requestFocus();
  }

  void _onPaymentFocusChanged() {
    if (_paymentFocus.hasFocus) {
      _onFieldFocused('payment');
    }
    if (mounted) setState(() {});
  }

  void _onEntryFocusChanged(FocusNode node) {
    if (mounted) setState(() {});
  }

  void _syncDeleteScrollFromGrid() {
    if (_syncingGridScroll) return;
    if (!_gridDeleteVScrollController.hasClients ||
        !_gridVScrollController.hasClients) {
      return;
    }
    _syncingGridScroll = true;
    _gridDeleteVScrollController.jumpTo(_gridVScrollController.offset);
    _syncingGridScroll = false;
  }

  void _syncGridScrollFromDelete() {
    if (_syncingGridScroll) return;
    if (!_gridDeleteVScrollController.hasClients ||
        !_gridVScrollController.hasClients) {
      return;
    }
    _syncingGridScroll = true;
    _gridVScrollController.jumpTo(_gridDeleteVScrollController.offset);
    _syncingGridScroll = false;
  }

  void _syncHeaderScrollFromBody() {
    if (!_gridHScrollController.hasClients) return;
    final offset = _gridHScrollController.offset;
    void jump(ScrollController controller) {
      if (!controller.hasClients) return;
      if (controller.offset != offset) {
        controller.jumpTo(offset);
      }
    }

    jump(_gridHeaderHScrollController);
    jump(_gridFooterHScrollController);
  }

  void _onManualPushChanged() {
    if (!mounted) return;
    setState(() {
      _manualPushInProgress =
          SyncService.instance.manualPushInProgress.value;
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
    final result =
        await SyncService.instance.manualPush(_selectedLocation);

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
    var nextBillNo =
        await BillRepository.getNextBillNumber(_selectedLocation);

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

    final nextBillNo =
        await BillRepository.getNextBillNumber(_selectedLocation);
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

  Widget _buildTopActionButton({
    required String label,
    required VoidCallback? onPressed,
    Key? buttonKey,
    FocusNode? focusNode,
    Color backgroundColor = AppColors.actionButton,
    Color foregroundColor = Colors.white,
  }) {
    return SizedBox(
      width: _topButtonWidth,
      height: _topButtonHeight,
      child: ElevatedButton(
        key: buttonKey,
        focusNode: focusNode,
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: const Size(_topButtonWidth, _topButtonHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: _normalFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildBillNavButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return _buildTopActionButton(
      label: label,
      onPressed: onPressed,
    );
  }

  int _gridDataColumnCount(bool showTax) => showTax ? 8 : 4;

  double get _gridViewportWidth => _entryBlockWidth;

  double get _primaryGridColWidth => _gridViewportWidth / 4;

  double _leftGridScrollWidth(bool showTax) {
    final extraCols = math.max(0, _gridDataColumnCount(showTax) - 4);
    return _gridViewportWidth + extraCols * _gridColWidth;
  }

  List<Widget> _layoutGridCells(
    bool showTax,
    List<Widget> cells,
  ) {
    final primary = _primaryGridColWidth;
    return List.generate(
      cells.length,
      (index) => SizedBox(
        width: index < 4 ? primary : _gridColWidth,
        child: cells[index],
      ),
    );
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

  Future<void> _confirmRemoveItem(int index) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('Remove this line?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (remove == true && mounted) {
      _removeItem(index);
    }
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
        _currentBillLocalId = await LocalDb.instance.findLocalIdByBillNo(
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
        if (mounted) _focusRate();
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
        builder: (_) => widget.ledgerScreenBuilder?.call(_selectedLocation) ??
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

  String _formatQtyOrPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  void _updateAmountDisplay() {
    final text = _format(_currentAmount);
    if (_amountController.text != text) {
      _amountController.text = text;
    }
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
        : _buildDesktopBody(
            context: context,
            showMenuButton: false,
            useSidebarLayout: useSidebarLayout,
          );

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
        child: _buildMenuPanel(
          onClose: () => Navigator.pop(context),
        ),
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
        AbsorbPointer(
          absorbing: _isEntryLocked,
          child: child,
        ),
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

  double _gridFontSizeForWidth(double width) => _gridFontSize;

  bool _gridTextFits(
    String text,
    double fontSize,
    FontWeight fontWeight,
    double maxWidth,
    int maxLines,
    ui.TextDirection textDirection,
  ) {
    if (maxWidth <= 0 || !maxWidth.isFinite) {
      return true;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.1,
        ),
      ),
      textDirection: textDirection,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }

  double _gridCellFontSize(
    String text,
    double fontSize,
    FontWeight fontWeight,
    double maxWidth,
    int maxLines,
    ui.TextDirection textDirection,
  ) {
    if (_gridTextFits(
      text,
      fontSize,
      fontWeight,
      maxWidth,
      maxLines,
      textDirection,
    )) {
      return fontSize;
    }
    for (var size = fontSize - 0.5; size >= _gridMinFontSize; size -= 0.5) {
      if (_gridTextFits(
        text,
        size,
        fontWeight,
        maxWidth,
        maxLines,
        textDirection,
      )) {
        return size;
      }
    }
    return _gridMinFontSize;
  }

  Widget _gridCellText(
    String text, {
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
    int maxLines = 2,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final textDirection = Directionality.of(context);
        final resolvedSize = _gridCellFontSize(
          text,
          fontSize,
          fontWeight,
          maxWidth,
          maxLines,
          textDirection,
        );
        return Text(
          text,
          maxLines: maxLines,
          softWrap: true,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: resolvedSize,
            fontWeight: fontWeight,
            height: 1.1,
            color: const Color(0xFF000000),
          ),
        );
      },
    );
  }

  Widget _buildDesktopBody({
    required BuildContext context,
    required bool showMenuButton,
    required bool useSidebarLayout,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridFontSize = _gridFontSizeForWidth(constraints.maxWidth);
        final minColumnHeight = _desktopChromeEstimate +
            _gridMinScrollHeight +
            _entryValidationSlack;
        final fitsFixedLayout = constraints.maxHeight >= minColumnHeight;
        final usePageScroll = !fitsFixedLayout;

        Widget columnChild() {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopArea(
                includeEntryRow: true,
                gridFontSize: gridFontSize,
                showMenuButton: showMenuButton,
                useSidebarLayout: useSidebarLayout,
                menuContext: context,
              ),
              const SizedBox(height: 4),
              if (usePageScroll)
                SizedBox(
                  height: _gridFrameHeight,
                  child: _buildDesktopGridZone(
                    gridFontSize: gridFontSize,
                  ),
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: _gridTotalWidth,
                              child: _buildDesktopGridZone(
                                gridFontSize: gridFontSize,
                                expandVertically: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ],
          );
        }

        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: usePageScroll
                ? SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: columnChild(),
                    ),
                  )
                : columnChild(),
          ),
        );
      },
    );
  }

  Color _paymentFillColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'CASH':
        return Colors.black;
      case 'CARD':
        return AppColors.accentBlue;
      case 'UPI':
      default:
        return Colors.white;
    }
  }

  Color _paymentTextColor(String mode) {
    switch (mode.toUpperCase()) {
      case 'CASH':
      case 'CARD':
        return Colors.white;
      case 'UPI':
      default:
        return Colors.black;
    }
  }

  Widget _buildSaveSaleButton() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(5),
      child: _buildTopActionButton(
        label: 'SAVE SALE',
        buttonKey: const Key('save_sale_bar_button'),
        focusNode: _saveSaleFocus,
        onPressed: _saveBill,
        backgroundColor: AppColors.navy,
      ),
    );
  }

  Widget _buildMobileBody(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTopArea(),
            const SizedBox(height: _topAreaGap),
            _buildItemTableSection(mobile: true),
          ],
        ),
      ),
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

  Widget _buildTopArea({
    bool includeEntryRow = false,
    double gridFontSize = _gridFontSize,
    bool showMenuButton = false,
    bool useSidebarLayout = false,
    BuildContext? menuContext,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: _actionButtonGap,
            runSpacing: _actionButtonGap,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showMenuButton && menuContext != null)
                IconButton(
                  icon: Icon(
                    useSidebarLayout && _sidebarOpen
                        ? Icons.menu_open
                        : Icons.menu,
                  ),
                  tooltip: useSidebarLayout && _sidebarOpen
                      ? 'Close menu'
                      : 'Open menu',
                  onPressed: () {
                    if (useSidebarLayout) {
                      setState(() => _sidebarOpen = !_sidebarOpen);
                    } else {
                      Scaffold.maybeOf(menuContext)?.openDrawer();
                    }
                  },
                ),
              Focus(
                skipTraversal: true,
                child: _buildBillNavButton(
                  label: 'PREVIOUS',
                  onPressed: _goToPreviousBill,
                ),
              ),
              Focus(
                skipTraversal: true,
                child: _buildBillNavButton(
                  label: 'NEXT',
                  onPressed: _goToNextBill,
                ),
              ),
              _buildSaveSaleButton(),
            ],
          ),
          const SizedBox(height: _topAreaGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final bill = Focus(
                skipTraversal: true,
                child: _buildBillDetails(),
              );
              final customer = Focus(
                skipTraversal: true,
                child: _buildCustomerDetails(),
              );
              const minRowWidth = 520.0;
              if (constraints.maxWidth < minRowWidth) {
                return Wrap(
                  spacing: _topAreaGap,
                  runSpacing: _topAreaGap,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    bill,
                    customer,
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bill,
                    const SizedBox(width: _framesGap),
                    customer,
                  ],
                ),
              );
            },
          ),
          if (includeEntryRow) ...[
            const SizedBox(height: _topAreaGap),
            _buildAlignedEntryRow(gridFontSize: gridFontSize),
          ],
        ],
      ),
    );
  }

  Widget _buildBillDetails() {
    const labelStyle = TextStyle(
      fontSize: _normalFontSize,
      color: Colors.black,
      fontWeight: FontWeight.w600,
    );
    const valueStyle = TextStyle(
      fontSize: _normalFontSize,
      color: Colors.black,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      padding: const EdgeInsets.all(_framePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: _billLabelColWidth,
                child: Text('BILL NO:', style: labelStyle),
              ),
              const SizedBox(width: 8),
              Container(
                width: _billNoBoxWidth,
                height: _compactFieldHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: billNoColor,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$_billNo',
                    style: valueStyle.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: _upiBoxWidth,
                height: _compactFieldHeight,
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(6),
                  child: DropdownButtonFormField<String>(
                    key: const Key('bill_payment_dropdown'),
                    focusNode: _paymentFocus,
                    initialValue: _paymentMode,
                    isDense: true,
                    isExpanded: true,
                    alignment: AlignmentDirectional.centerStart,
                    decoration: _highlightedInputDecoration(
                      focused: _paymentFocus.hasFocus,
                      fillColor: _paymentFocus.hasFocus
                          ? billNoColor
                          : _paymentFillColor(_paymentMode),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: _paymentFocus.hasFocus
                          ? Colors.black
                          : _paymentTextColor(_paymentMode),
                    ),
                    style: TextStyle(
                      fontSize: _entryFontSize,
                      color: _paymentFocus.hasFocus
                          ? Colors.black
                          : _paymentTextColor(_paymentMode),
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                    dropdownColor: Colors.white,
                    selectedItemBuilder: (context) {
                      return _paymentModes
                          .map(
                            (mode) => Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  mode,
                                  style: TextStyle(
                                    fontSize: _entryFontSize,
                                    color: _paymentFocus.hasFocus
                                        ? Colors.black
                                        : _paymentTextColor(_paymentMode),
                                    fontWeight: FontWeight.w600,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false);
                    },
                    items: _paymentModes.map((item) {
                      return DropdownMenuItem(
                        value: item,
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: _entryFontSize,
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
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
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: _billLabelColWidth,
                child: Text('BILL DATE:', style: labelStyle),
              ),
              const SizedBox(width: 8),
              Container(
                key: const Key('bill_date_display'),
                width: _billDateBoxWidth,
                height: _compactFieldHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F3F3),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_billDate.day.toString().padLeft(2, '0')}/'
                  '${_billDate.month.toString().padLeft(2, '0')}/'
                  '${_billDate.year}',
                  style: valueStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDetails() {
    const labelStyle = TextStyle(
      fontSize: _normalFontSize,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(_framePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CUSTOMER DETAILS',
            style: TextStyle(
              fontSize: _normalFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: _billLabelColWidth,
                  child: Text('NAME', style: labelStyle),
                ),
                SizedBox(
                  width: _customerBoxWidth,
                  height: _customerBoxHeight,
                  child: _smallTextField(
                    _customerNameController,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _focusMobile(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: _billLabelColWidth,
                  child: Text('MOBILE', style: labelStyle),
                ),
                SizedBox(
                  width: _customerBoxWidth,
                  height: _customerBoxHeight,
                  child: GestureDetector(
                    onDoubleTap: _onMobileDoubleTap,
                    child: _smallTextField(
                      _mobileController,
                      number: true,
                      fieldKey: const Key('bill_mobile_field'),
                      focusNode: _mobileFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _focusRate(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showPasswordField && !_editUnlocked) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: _billLabelColWidth + _customerBoxWidth,
              child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'PASSWORD',
                    style: TextStyle(fontSize: _normalFontSize),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: _entryBoxHeight,
                    child: TextField(
                      key: const Key('bill_edit_password_field'),
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: true,
                      onSubmitted: (_) => _tryUnlockEdit(),
                      style: const TextStyle(fontSize: _normalFontSize),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: _entryBoxHeight,
                  child: ElevatedButton(
                    key: const Key('bill_edit_password_ok'),
                    onPressed: _tryUnlockEdit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, _entryBoxHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontSize: _normalFontSize),
                    ),
                  ),
                ),
              ],
            ),
            ),
            if (_passwordError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _passwordError!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: _normalFontSize,
                  ),
                ),
              ),
          ],
          if (_editUnlocked)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'EDIT MODE — TAP A LINE TO CORRECT RATE/QTY.',
                style: TextStyle(
                  fontSize: _normalFontSize,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallTextField(
    TextEditingController controller, {
    bool number = false,
    Key? fieldKey,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      keyboardType: number ? TextInputType.phone : TextInputType.text,
      inputFormatters: number
          ? [
              FilteringTextInputFormatter.digitsOnly,
            ]
          : null,
      style: const TextStyle(
        fontSize: _normalFontSize,
        height: 1,
        color: Colors.black,
      ),
      textAlignVertical: TextAlignVertical.center,
      decoration: _customerFieldDecoration(),
    );
  }

  InputDecoration _entryDecoration() {
    return const InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(),
      disabledBorder: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _entryFieldVerticalPadding,
      ),
      alignLabelWithHint: true,
    );
  }

  InputDecoration _customerFieldDecoration() {
    return const InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _customerFieldVerticalPadding,
      ),
      alignLabelWithHint: true,
    );
  }

  InputDecoration _highlightedInputDecoration({
    required bool focused,
    Color? fillColor,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final borderColor = focused ? const Color(0xFF006064) : AppColors.border;
    final borderWidth = focused ? 2.0 : 1.0;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: borderColor, width: borderWidth),
    );
    return InputDecoration(
      isDense: false,
      filled: true,
      fillColor: focused ? billNoColor : (fillColor ?? Colors.white),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: _entryFieldVerticalPadding,
          ),
      alignLabelWithHint: true,
    );
  }

  Widget _buildStackedEntryField({
    required String label,
    required TextEditingController controller,
    double labelFontSize = _normalFontSize,
    double valueFontSize = _entryFontSize,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    bool readOnly = false,
    TextInputAction? textInputAction,
    Key? fieldKey,
    double width = _numericBoxWidth,
    NumericFocusOrder? traversalOrder,
  }) {
    final focused = focusNode?.hasFocus ?? false;
    Widget field = TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      showCursor: !readOnly,
      enableInteractiveSelection: !readOnly,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: readOnly
          ? null
          : [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      decoration: _highlightedInputDecoration(focused: focused),
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        fontSize: valueFontSize,
        height: 1,
        color: Colors.black,
      ),
    );

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: width,
          height: _entryBoxHeight,
          child: ClipRect(child: field),
        ),
      ],
    );

    if (traversalOrder == null) {
      return column;
    }

    return FocusTraversalOrder(order: traversalOrder, child: column);
  }

  Widget _buildAmountDisplayField() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'AMOUNT',
          style: TextStyle(
            fontSize: _normalFontSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _numericBoxWidth,
          height: _entryBoxHeight,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            child: TextField(
              key: const Key('bill_amount_field'),
              controller: _amountController,
              readOnly: true,
              showCursor: false,
              enableInteractiveSelection: false,
              textAlign: TextAlign.center,
              decoration: _entryDecoration(),
              style: const TextStyle(
                fontSize: _entryFontSize,
                height: 1,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlignedEntryRow({
    bool mobile = false,
    double gridFontSize = _gridFontSize,
  }) {
    if (mobile) {
      return _buildEntryRowFallbackMobile();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final message = _rateError ?? _qtyError;
        final maxWidth = constraints.maxWidth;
        final errorWidth = maxWidth.isFinite
            ? math.max(160.0, maxWidth - _entryBlockWidth - _entryColumnGap)
            : 280.0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_rate_field'),
              traversalOrder: const NumericFocusOrder(3),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_qty_field'),
              traversalOrder: const NumericFocusOrder(4),
            ),
            const SizedBox(width: _entryColumnGap),
            _buildAmountDisplayField(),
            if (message != null) ...[
              const SizedBox(width: _entryColumnGap),
              SizedBox(
                width: errorWidth,
                height: _entryBoxHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      key: const Key('entry_validation_message'),
                      message,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: _normalFontSize,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEntryRowFallbackMobile() {
    final message = _rateError ?? _qtyError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: _entryColumnGap,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: _rateSubmitted,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_rate_field'),
            ),
            _buildStackedEntryField(
              label: 'QTY',
              controller: _qtyController,
              focusNode: _qtyFocus,
              onChanged: _qtyChanged,
              onSubmitted: _qtySubmitted,
              textInputAction: TextInputAction.done,
              fieldKey: const Key('bill_qty_field'),
            ),
            _buildAmountDisplayField(),
            if (message != null)
              SizedBox(
                width: 220,
                height: _entryBoxHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      message,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: _normalFontSize,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemTableSection({bool mobile = false}) {
    final frame = _buildGridFrame(
      showTax: _items.isNotEmpty,
      gridFontSize: _gridFontSize,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAlignedEntryRow(mobile: mobile),
        const SizedBox(height: _topAreaGap),
        if (mobile)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: frame,
          )
        else
          frame,
      ],
    );
  }

  Widget _buildDesktopGridZone({
    required double gridFontSize,
    bool expandVertically = false,
  }) {
    final showTax = _items.isNotEmpty;
    final frame = _buildGridFrame(
      showTax: showTax,
      gridFontSize: gridFontSize,
      expandVertically: expandVertically,
    );
    if (expandVertically) {
      return frame;
    }
    return Align(
      alignment: Alignment.topLeft,
      child: frame,
    );
  }

  Widget _buildGridBodyRow({
    required bool showTax,
    required double gridFontSize,
    required double scrollWidth,
    required double listBodyHeight,
  }) {
    final bodyHeight = math.max(0.0, listBodyHeight);
    final bodyScrollZoneHeight = bodyHeight + _gridHScrollbarStripHeight;

    final horizontalBody = SizedBox(
      width: scrollWidth,
      height: bodyHeight,
      child: _buildItemRowsList(showTax, gridFontSize, scrollWidth),
    );

    final horizontalBodyScroller = SizedBox(
      height: bodyScrollZoneHeight,
      child: Scrollbar(
        controller: _gridHScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const Key('grid_horizontal_scroll'),
          controller: _gridHScrollController,
          scrollDirection: Axis.horizontal,
          child: horizontalBody,
        ),
      ),
    );

    return ColoredBox(
      color: AppColors.background,
      child: SizedBox(
        height: bodyScrollZoneHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _gridViewportWidth,
              child: horizontalBodyScroller,
            ),
            SizedBox(
              width: _deleteColWidth,
              height: bodyScrollZoneHeight,
              child: ColoredBox(
                color: AppColors.cardWhite,
                child: Column(
                  children: [
                    SizedBox(
                      height: bodyHeight,
                      child: _buildDeleteRowsList(),
                    ),
                    const SizedBox(height: _gridHScrollbarStripHeight),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridFrameChrome(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }

  Widget _buildGridFrame({
    required bool showTax,
    required double gridFontSize,
    bool expandVertically = false,
  }) {
    final scrollWidth = _leftGridScrollWidth(showTax);

    final horizontalHeader = SizedBox(
      width: scrollWidth,
      child: _buildTableHeader(showTax, gridFontSize, scrollWidth),
    );

    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _gridViewportWidth,
          child: SingleChildScrollView(
            controller: _gridHeaderHScrollController,
            scrollDirection: Axis.horizontal,
            child: horizontalHeader,
          ),
        ),
        _tableDeleteHeaderCell(),
      ],
    );

    final footer = _buildFixedGridFooter(gridFontSize);

    final frameColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headerRow,
        if (expandVertically)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final listBodyHeight =
                    constraints.maxHeight - _gridHScrollbarStripHeight;
                return _buildGridBodyRow(
                  showTax: showTax,
                  gridFontSize: gridFontSize,
                  scrollWidth: scrollWidth,
                  listBodyHeight: listBodyHeight,
                );
              },
            ),
          )
        else
          _buildGridBodyRow(
            showTax: showTax,
            gridFontSize: gridFontSize,
            scrollWidth: scrollWidth,
            listBodyHeight: _gridBodyHeight,
          ),
        footer,
      ],
    );

    return SizedBox(
      width: _gridTotalWidth,
      height: expandVertically ? null : _gridFrameHeight,
      child: _gridFrameChrome(frameColumn),
    );
  }

  Widget _buildItemRowsList(
    bool showTax,
    double gridFontSize,
    double scrollWidth,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      child: ClipRect(
        child: ListView.builder(
          controller: _gridVScrollController,
          padding: EdgeInsets.zero,
          itemCount: _items.length,
          itemBuilder: (context, index) {
            if (_editingIndex == index) {
              return SizedBox(
                width: scrollWidth,
                child: _buildEditRow(index),
              );
            }
            return _buildTableRow(
              index,
              showTax,
              gridFontSize,
              scrollWidth,
            );
          },
        ),
      ),
    );
  }

  Widget _buildDeleteRowsList() {
    return ListView.builder(
      controller: _gridDeleteVScrollController,
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        if (_editingIndex == index) {
          return const SizedBox(
            height: _editRowHeight,
            child: ColoredBox(
              color: Color(0xFFFFF8E1),
              child: SizedBox.shrink(),
            ),
          );
        }
        return _buildDeleteCell(index);
      },
    );
  }

  Widget _buildTableHeader(
    bool showTax,
    double gridFontSize,
    double scrollWidth,
  ) {
    final headerCells = <Widget>[
      _tableHeaderCell('S.NO', gridFontSize),
      _tableHeaderCell('RATE', gridFontSize),
      _tableHeaderCell('QTY', gridFontSize),
      _tableHeaderCell('AMOUNT', gridFontSize, last: !showTax),
      if (showTax) ...[
        _tableHeaderCell('TOTAL', gridFontSize),
        _tableHeaderCell('CGST %', gridFontSize),
        _tableHeaderCell('SGST %', gridFontSize),
        _tableHeaderCell('IGST', gridFontSize, last: true),
      ],
    ];

    return SizedBox(
      width: scrollWidth,
      height: _tableHeaderHeight,
      child: ColoredBox(
        color: AppColors.tableHeader,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _layoutGridCells(showTax, headerCells),
        ),
      ),
    );
  }

  Widget _tableHeaderCell(
    String text,
    double fontSize, {
    bool last = false,
  }) {
    return Container(
      height: _tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          right: last
              ? BorderSide.none
              : BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      alignment: Alignment.center,
      child: _gridCellText(
        text.toUpperCase(),
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _tableDeleteHeaderCell() {
    return Container(
      width: _deleteColWidth,
      height: _tableHeaderHeight,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
    );
  }

  Widget _buildEditRow(int index) {
    return Container(
      height: _editRowHeight,
      color: const Color(0xFFFFF8E1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'LINE ${index + 1}',
            style: const TextStyle(
              fontSize: _normalFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'RATE',
            controller: _editRateController,
          ),
          const SizedBox(width: 10),
          _buildEditLineField(
            label: 'QTY',
            controller: _editQtyController,
          ),
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
              child: const Text(
                'OK',
                style: TextStyle(fontSize: _normalFontSize),
              ),
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
            fontSize: _normalFontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: _numericBoxWidth,
          height: _entryBoxHeight,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: _entryFontSize, height: 1),
            decoration: _entryDecoration(),
          ),
        ),
      ],
    );
  }

  Widget _buildTableRow(
    int index,
    bool showTax,
    double gridFontSize,
    double scrollWidth,
  ) {
    final BillItem item = _items[index];
    final bool selected = _selectedIndex == index;

    final dataCells = <Widget>[
      _tableDataCell('${index + 1}', gridFontSize),
      _tableDataCell(
        _format(item.rate),
        gridFontSize,
      ),
      _tableDataCell(
        _formatQtyOrPct(item.qty),
        gridFontSize,
      ),
      _tableDataCell(
        _format(item.amount),
        gridFontSize,
        last: !showTax,
      ),
      if (showTax) ...[
        _tableDataCell(
          _format(item.grossAmt),
          gridFontSize,
        ),
        _tableDataCell(
          _formatQtyOrPct(item.cgstPct),
          gridFontSize,
        ),
        _tableDataCell(
          _formatQtyOrPct(item.sgstPct),
          gridFontSize,
        ),
        _tableDataCell(
          _format(item.igst),
          gridFontSize,
          last: true,
        ),
      ],
    ];

    return GestureDetector(
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
      child: SizedBox(
        width: scrollWidth,
        height: _tableRowHeight,
        child: ColoredBox(
          color: selected ? const Color(0xFFFFE5A0) : AppColors.background,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _layoutGridCells(showTax, dataCells),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteCell(int index) {
    return SizedBox(
      width: _deleteColWidth,
      child: Container(
        height: _tableRowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: Focus(
          skipTraversal: true,
          child: IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 22, height: 22),
            icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
            tooltip: 'Remove item',
            onPressed: () => _removeItem(index),
          ),
        ),
      ),
    );
  }

  Widget _tableDataCell(
    String text,
    double fontSize, {
    bool last = false,
  }) {
    return Container(
      height: _tableRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          right: last
              ? BorderSide.none
              : BorderSide(color: AppColors.border, width: 0.6),
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      alignment: Alignment.center,
      child: _gridCellText(
        text,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _footerLabelCell(
    String text, {
    bool last = false,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    return Container(
      height: _gridFooterTotalRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        border: Border(
          right: last
              ? BorderSide.none
              : BorderSide(color: AppColors.border, width: 0.6),
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _normalFontSize,
            fontWeight: fontWeight,
            color: AppColors.navy,
          ),
        ),
      ),
    );
  }

  Widget _buildFixedGridFooter(double gridFontSize) {
    final showTax = _items.isNotEmpty;
    final scrollWidth = _leftGridScrollWidth(showTax);
    final words = amountInWords(_grandTotal).toUpperCase();
    final qtyLabel = '${_formatQtyOrPct(_totalQty)} (total pcs)';
    final primary = _primaryGridColWidth;
    final grossSum = _items.fold<double>(0, (sum, item) => sum + item.grossAmt);

    final totalCells = <Widget>[
      _footerLabelCell('Total'),
      _footerLabelCell(''),
      _footerLabelCell(qtyLabel),
      _footerLabelCell(
        _format(_totalAmount),
        last: !showTax,
      ),
      if (showTax) ...[
        _footerLabelCell(_format(grossSum)),
        _footerLabelCell(_format(_totalCgst)),
        _footerLabelCell(_format(_totalSgst)),
        _footerLabelCell(_format(_totalIgst), last: true),
      ],
    ];

    return SizedBox(
      width: _gridTotalWidth,
      height: _gridFooterHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _gridFooterTotalRowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: _gridViewportWidth,
                  child: SingleChildScrollView(
                    controller: _gridFooterHScrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: scrollWidth,
                      height: _gridFooterTotalRowHeight,
                      child: Row(
                        children: _layoutGridCells(showTax, totalCells),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: _deleteColWidth,
                  height: _gridFooterTotalRowHeight,
                  decoration: BoxDecoration(
                    color: AppColors.headerBand,
                    border: Border(
                      left: BorderSide(color: AppColors.border, width: 0.6),
                      bottom: BorderSide(color: AppColors.border, width: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: _gridTotalWidth,
            height: _gridFooterGrandRowHeight,
            decoration: BoxDecoration(
              color: AppColors.headerBand,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: primary,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text(
                      'GRAND TOTAL',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: _grandTotalLabelFontSize,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: primary * 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        key: const Key('grand_total_words'),
                        words,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: _grandTotalWordsFontSize,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: primary,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          _format(_grandTotal),
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: _grandTotalValueFontSize,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _deleteColWidth),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    SyncService.instance.manualPushInProgress
        .removeListener(_onManualPushChanged);
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
    _saveSaleFocus.dispose();

    _gridHeaderHScrollController.dispose();
    _gridHScrollController.dispose();
    _gridFooterHScrollController.dispose();
    _gridVScrollController.dispose();
    _gridDeleteVScrollController.dispose();

    super.dispose();
  }
}
