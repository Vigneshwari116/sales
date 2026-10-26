
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:surabhi/config/app_config.dart';
import 'package:surabhi/config/local_credentials.dart';
import 'package:surabhi/db/local_db.dart';
import 'package:surabhi/models/sale_bill.dart';
import 'package:surabhi/repositories/abstract_repository.dart';
import 'package:surabhi/repositories/bill_repository.dart';
import 'package:surabhi/services/app_session_service.dart';
import 'package:surabhi/services/bill_print_exception.dart';
import 'package:surabhi/services/bill_print_service.dart';
import 'package:surabhi/screen/staff_thermal_printer_screen.dart';
import 'package:surabhi/services/session_service.dart';

import 'bill_item.dart';
import 'package:surabhi/screen/sale_groups.dart';
import 'package:surabhi/screen/number%20to%20words.dart';
import 'login_screen.dart';
import 'sales_ledger_screen.dart';
import 'package:surabhi/services/printer_settings_service.dart';
import 'package:surabhi/services/gst_config_service.dart';
import 'package:surabhi/theme/app_theme.dart';
import 'package:surabhi/services/print_log_service.dart';
import 'package:surabhi/utils/bill_gst_totals.dart';
import 'package:surabhi/utils/money_format.dart';
import 'package:surabhi/utils/qty_format.dart';
import 'package:surabhi/utils/system_clock.dart';
import 'package:surabhi/widgets/compact_layout.dart';

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

  /// When set (tests only), skips thermal print after save.
  @visibleForTesting
  final Future<void> Function(SaleBill bill, int savedBillNo)?
      printAfterSaveOverride;

  /// When false, bill tab is hidden inside [IndexedStack] — restore focus on return.
  final bool isSectionActive;

  /// How often to re-check the calendar day while the screen is open.
  final Duration calendarCheckInterval;

  const SalesBillScreen({
    super.key,
    this.embeddedInDashboard = false,
    this.isSectionActive = true,
    this.initialBillNo,
    this.ledgerScreenBuilder,
    this.saveBillOverride,
    this.printAfterSaveOverride,
    this.calendarCheckInterval = const Duration(seconds: 30),
  });

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen>
    with WidgetsBindingObserver {
  // ============================================================
  // COLORS
  // ============================================================

  static const Color billNoColor = Color(0xFF7FE8E8);

  /// Bill screen typography — local only; other screens stay on [AppTextSizes].
  static const double _entryFontSize = 24;
  static const double _normalFontSize = 18;
  static const double _gridFontSize = 10;
  static const double _gridMinFontSize = 8;
  static const double _grandTotalAmountFontSize = 24;
  static const double _amountInWordsFontSize = 14;
  static const double _todayCardLabelFontSize = 16;
  static const double _todayCardValueFontSize = 18;

  static const double _topButtonWidth = 150;
  static const double _topButtonHeight = 44;
  static const double _billLabelColWidth = 96;
  static const double _billNoBoxWidth = 90;
  static const double _upiBoxWidth = 130;
  static const double _billDateBoxWidth = 130;
  static const double _compactFieldHeight = 40;
  static const double _customerBoxWidth = 220;
  static const double _customerBoxHeight = 36;
  static const double _groupBoxWidth = 240;
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
      _groupBoxWidth + (_entryColumnGap * 3) + (_numericBoxWidth * 3);
  static const double _gridTotalWidth = _entryBlockWidth + _deleteColWidth;
  static const double _gridVisibleItemRows = 10;
  static const double _gridBodyHeight = _tableRowHeight * _gridVisibleItemRows;
  static const double _gridHScrollbarStripHeight = 12;
  static const double _gridBodyScrollZoneHeight =
      _gridBodyHeight + _gridHScrollbarStripHeight;
  static const double _gridFrameHeight =
      _tableHeaderHeight + _gridBodyScrollZoneHeight + _gridFooterHeight;
  static const double _bottomBarHeight = 44;
  static const double _desktopChromeEstimate = 268;
  static const double _entryValidationSlack = 28;
  static const double _gridMinScrollHeight = _gridFrameHeight;
  static const double _todaySalesFrameWidth = 268;
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
  String? _currentBillLocalId;
  String? _rateError;
  String? _qtyError;
  double _cgstPct = GstConfigService.defaultCgstPct;
  double _sgstPct = GstConfigService.defaultSgstPct;

  // ============================================================
  // BILL DATE
  // ============================================================

  DateTime _billDate = SystemClock.now();
  Timer? _calendarDayTimer;
  DateTime? _todaySalesLoadedDay;

  // ============================================================
  // PAYMENT
  // ============================================================

  String _paymentMode = 'UPI';

  final List<String> _paymentModes = const [
    'UPI',
    'CASH',
    'CARD',
  ];

  String? _selectedParticular = kSaleGroups.first;
  String? _particularError;

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

  final FocusNode _groupFocus = FocusNode();
  final FocusNode _paymentFocus = FocusNode();
  final FocusNode _saveSaleFocus = FocusNode();

  final ScrollController _gridHeaderHScrollController = ScrollController();
  final ScrollController _gridHScrollController = ScrollController();
  final ScrollController _gridVScrollController = ScrollController();
  final ScrollController _gridDeleteVScrollController = ScrollController();
  bool _syncingGridScroll = false;

  String _lastFocusField = 'payment';

  double _todayAmount = 0;
  double _todayGst = 0;
  double _todayGrandTotal = 0;
  double _todayPcs = 0;
  bool _todaySalesPanelVisible = false;

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
  void didUpdateWidget(covariant SalesBillScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSectionActive && !oldWidget.isSectionActive) {
      unawaited(() async {
        await _refreshBillNumberFromDatabase();
        if (_items.isEmpty && !_billSaved) {
          await _loadBillNumber();
        } else if (!_billSaved) {
          await _alignDraftBillNoIfTaken();
        }
        await _onCalendarDayTick();
      }());
    }
    if (widget.isSectionActive && !oldWidget.isSectionActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreSavedFocus();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calendarDayTimer = Timer.periodic(
      widget.calendarCheckInterval,
      (_) => unawaited(_onCalendarDayTick()),
    );

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
    _groupFocus.addListener(() {
      if (_groupFocus.hasFocus) _onFieldFocused('group');
      _onEntryFocusChanged(_groupFocus);
    });

    _paymentFocus.addListener(_onPaymentFocusChanged);
    _rateFocus.addListener(() => _onEntryFocusChanged(_rateFocus, _rateController));
    _qtyFocus.addListener(() => _onEntryFocusChanged(_qtyFocus, _qtyController));
    _gridHScrollController.addListener(_syncHeaderScrollFromBody);
    _gridVScrollController.addListener(_syncDeleteScrollFromGrid);
    _gridDeleteVScrollController.addListener(_syncGridScrollFromDelete);


    _loadGstRates();

    if (widget.initialBillNo != null) {
      _billNo = widget.initialBillNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPayment();
      });
    } else {
      _restoreSessionOrLoadBill().then((_) {
        if (mounted) {
          _focusPayment();
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshBillNumberFromDatabase());
    });
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
        _focusName();
      case 'group':
        _focusGroup();
      case 'payment':
      default:
        _focusPayment();
    }
  }

  void _focusPayment() {
    if (!mounted) return;
    _paymentFocus.requestFocus();
  }

  void _onPaymentFocusChanged() {
    if (_paymentFocus.hasFocus) {
      _onFieldFocused('payment');
    }
    if (mounted) setState(() {});
  }

  void _onEntryFocusChanged(FocusNode node, [TextEditingController? controller]) {
    if (node.hasFocus && controller != null) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
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

  InputDecoration _highlightedInputDecoration({
    required bool focused,
    Color? fillColor,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final borderColor =
        focused ? const Color(0xFF006064) : AppColors.border;
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

  BoxDecoration _highlightedBoxDecoration({required bool focused}) {
    return BoxDecoration(
      color: focused ? billNoColor : Colors.white,
      border: Border.all(
        color: focused ? const Color(0xFF006064) : AppColors.border,
        width: focused ? 2 : 1,
      ),
      borderRadius: BorderRadius.circular(4),
    );
  }

  void _syncHeaderScrollFromBody() {
    if (!_gridHeaderHScrollController.hasClients ||
        !_gridHScrollController.hasClients) {
      return;
    }
    if (_gridHeaderHScrollController.offset != _gridHScrollController.offset) {
      _gridHeaderHScrollController.jumpTo(_gridHScrollController.offset);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onCalendarDayTick());
    }
  }

  DateTime _now() => SystemClock.now();

  Future<bool> _syncUnsavedBillDateToToday() async {
    if (_billSaved) {
      return false;
    }
    final now = _now();
    if (isSameCalendarDay(_billDate, now)) {
      return false;
    }
    _billDate = now;
    await _persistSession();
    return true;
  }

  Future<void> _onCalendarDayTick() async {
    if (!mounted) return;

    var changed = false;
    if (await _syncUnsavedBillDateToToday()) {
      changed = true;
    }

    final now = _now();
    if (_todaySalesPanelVisible &&
        (_todaySalesLoadedDay == null ||
            !isSameCalendarDay(_todaySalesLoadedDay!, now))) {
      await _refreshTodaySales();
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  bool get _isEntryLocked => _busy;

  Future<void> _loadGstRates() async {
    final cgst = await GstConfigService.cgstPct();
    final sgst = await GstConfigService.sgstPct();
    if (!mounted) return;
    setState(() {
      _cgstPct = cgst;
      _sgstPct = sgst;
    });
  }

  Future<void> _refreshBillNumberFromDatabase() async {
    try {
      await LocalDb.instance.refreshNextBillNoFromBills(_selectedLocation);
    } catch (_) {
      // Best-effort; screen can still load from session.
    }
  }

  Future<void> _restoreSessionOrLoadBill() async {
    final session = await SessionService.loadBillSession();

    if (!mounted) return;

    if (session != null && session.location == _selectedLocation) {
      setState(() {
        _billNo = session.billNo;
        final sessionDate = session.billDate;
        if (!session.billSaved &&
            !isSameCalendarDay(sessionDate, _now())) {
          _billDate = _now();
        } else {
          _billDate = sessionDate;
        }
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

      if (!session.billSaved) {
        await _alignDraftBillNoIfTaken();
      }
      await _refreshBillNumberFromDatabase();
      return;
    }

    setState(() {
      _currentBillLocalId = null;
      if (!_billSaved) {
        _billDate = _now();
      }
    });

    await _loadBillNumber();
    if (!mounted) return;
  }

  Future<void> _alignDraftBillNoIfTaken() async {
    try {
      final taken = await LocalDb.instance.getBillByNumber(
        location: _selectedLocation,
        billNo: _billNo,
      );
      if (taken == null || !mounted) {
        return;
      }
      final next = await LocalDb.instance.peekNextBillNoFromBills(
        _selectedLocation,
      );
      if (!mounted) {
        return;
      }
      setState(() => _billNo = next);
    } catch (_) {
      // Keep current bill number on lookup failure.
    }
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
    await _refreshBillNumberFromDatabase();
    final nextBillNo =
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
    Color backgroundColor = AppColors.actionButton,
    Color foregroundColor = Colors.white,
  }) {
    return SizedBox(
      width: _topButtonWidth,
      height: _topButtonHeight,
      child: ElevatedButton(
        key: buttonKey,
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

  int _gridDataColumnCount(bool showTax) => showTax ? 9 : 6;

  double get _gridViewportWidth => _entryBlockWidth;

  double get _primaryGridColWidth => _gridViewportWidth / 5;

  double _leftGridScrollWidth(bool showTax) {
    final extraCols = math.max(0, _gridDataColumnCount(showTax) - 5);
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
        width: index < 5 ? primary : _gridColWidth,
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

  void _focusGroup() {
    if (!mounted) return;
    _groupFocus.requestFocus();
  }

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
    _particularError = null;
  }

  bool _validateParticular({bool focusOnError = true}) {
    final selected = _selectedParticular?.trim() ?? '';
    if (selected.isEmpty) {
      setState(() => _particularError = 'Select a group');
      if (focusOnError) {
        _focusGroup();
      }
      return false;
    }
    setState(() => _particularError = null);
    return true;
  }

  bool _validateRate({bool focusOnError = true}) {
    final text = _rateController.text.trim();
    if (text.isEmpty) {
      setState(() => _rateError = 'Rate must be greater than 0');
      if (focusOnError) _focusRate();
      return false;
    }
    final rate = double.tryParse(text);
    if (rate == null || rate <= 0) {
      setState(() => _rateError = 'Rate must be greater than 0');
      if (focusOnError) _focusRate();
      return false;
    }
    setState(() => _rateError = null);
    return true;
  }

  bool _validateQty({bool focusOnError = true}) {
    final text = _qtyController.text.trim();
    if (text.isEmpty) {
      setState(() => _qtyError = 'Quantity must be greater than 0');
      if (focusOnError) _focusQty();
      return false;
    }
    final qty = double.tryParse(text);
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

  Future<void> _rateSubmitted() async {
    final rateText = _rateController.text.trim();

    if (rateText == _printCode) {
      await _handlePrintCodeSubmit();
      return;
    }

    _focusQty();
  }

  Future<void> _handlePrintCodeSubmit() async {
    if (_busy) {
      developer.log(
        'Print code $_printCode ignored: save/print already in progress',
        name: 'SalesBill.print777',
      );
      unawaited(
        PrintLogService.append('777 ignored: save/print already in progress'),
      );
      return;
    }

    developer.log(
      'Print code $_printCode detected',
      name: 'SalesBill.print777',
    );
    unawaited(PrintLogService.append('777 detected'));

    _rateController.text = '0';
    if (_items.isEmpty) {
      _showMessage('Add items before printing');
      return;
    }

    developer.log('Print code $_printCode: save starting', name: 'SalesBill.print777');
    unawaited(PrintLogService.append('777 save start billNo=$_billNo'));
    try {
      if (widget.saveBillOverride != null) {
        setState(() => _busy = true);
        try {
          await widget.saveBillOverride!();
        } finally {
          if (mounted) {
            setState(() => _busy = false);
          }
        }
      } else {
        await _saveBill();
      }
      developer.log('Print code $_printCode: save finished', name: 'SalesBill.print777');
      unawaited(PrintLogService.append('777 save end billNo=$_billNo'));
    } catch (e, stackTrace) {
      developer.log(
        'Print code $_printCode: save failed: $e',
        name: 'SalesBill.print777',
        error: e,
        stackTrace: stackTrace,
      );
      unawaited(PrintLogService.append('777 save error: $e\n$stackTrace'));
      if (mounted) {
        _showMessage('Save failed: $e');
      }
    }
  }

  void _qtySubmitted() {
    _updateAmountDisplay();
    if (!_validateParticular() || !_validateRate() || !_validateQty()) {
      return;
    }
    _addItem();
  }

  void _addItem() {
    if (!_validateParticular() ||
        !_validateRate() ||
        !_validateQty()) {
      return;
    }

    final rate = double.parse(_rateController.text);
    final qty = double.parse(_qtyController.text);
    final particular = _selectedParticular!.trim();

    setState(() {
      _clearEntryErrors();
      _items.add(
        BillItem(
          particular: particular,
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
      _amountController.text = '0';
    });

    _persistSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusGroup();
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
    _billDate = _now();

    _paymentMode = 'UPI';
    _selectedParticular = kSaleGroups.first;

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
    if (_busy) {
      developer.log('Save skipped: already busy', name: 'SalesBill.print777');
      return;
    }

    if (_items.isEmpty) {
      _showMessage('Add at least one item before saving');
      return;
    }

    setState(() => _busy = true);
    developer.log('Save bill starting', name: 'SalesBill.print777');

    final timings = SaveStepTimings(billNo: _billNo, scope: 'ui');
    await PrintLogService.append('save ui start billNo=$_billNo');

    try {
      if (await _syncUnsavedBillDateToToday() && mounted) {
        setState(() {});
      }

      final bill = await timings.timeAsync(
        'build_bill',
        () async => _buildCurrentBill(),
      );
      final result = await timings.timeAsync(
        'repository_save',
        () => BillRepository.saveBill(
          bill,
          updateLocalId: _currentBillLocalId,
        ),
      );

      if (!mounted) return;

      if (!result.ok) {
        _showMessage(result.error ?? 'Failed to save bill');
        return;
      }

      if (result.data != null && result.data != _billNo) {
        setState(() => _billNo = result.data!);
      }

      await timings.timeAsync('local_id_lookup', () async {
        try {
          _currentBillLocalId = await LocalDb.instance.findLocalIdByBillNo(
                location: _selectedLocation,
                billNo: _billNo,
              ) ??
              _currentBillLocalId;
        } catch (_) {
          // Bill is saved; local id lookup is best-effort.
        }
      });

      final int savedBillNo = _billNo;
      await timings.timeAsync(
        'print_receipt',
        () => _printBillAfterSave(bill, savedBillNo),
      );
      developer.log(
        'Save bill finished (bill $savedBillNo)',
        name: 'SalesBill.print777',
      );

      if (!mounted) return;

      await timings.timeAsync('load_bill_number', () => _loadBillNumber());

      if (!mounted) return;

      setState(() {
        _billSaved = true;
        _clearCurrentBill();
      });

      await timings.timeAsync('persist_session', () => _persistSession());
      if (_todaySalesPanelVisible) {
        await timings.timeAsync('refresh_today_sales', () => _refreshTodaySales());
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusPayment();
      });
    } catch (e, stackTrace) {
      developer.log(
        'Save bill failed: $e',
        name: 'SalesBill.print777',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showMessage('Save failed: $e');
      }
    } finally {
      await timings.finish();
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
    final totals = _billGstTotals;
    return SaleBill(
      billNo: _billNo,
      location: _selectedLocation,
      billDate: _billDate,
      paymentMode: _paymentMode,
      customerName: _customerNameController.text.trim(),
      mobile: _mobileController.text.trim(),
      items: List<BillItem>.from(_items),
      totalQty: totals.totalQty,
      totalAmount: totals.totalAmount,
      totalCgst: totals.totalCgst,
      totalSgst: totals.totalSgst,
      totalIgst: totals.totalIgst,
      grandTotal: totals.grandTotal,
    );
  }

  BillGstTotals get _billGstTotals => computeBillGstTotalsFromItems(_items);

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

  double get _totalQty => _billGstTotals.totalQty;

  double get _totalAmount => _billGstTotals.totalAmount;

  double get _totalCgst => _billGstTotals.totalCgst;

  double get _totalSgst => _billGstTotals.totalSgst;

  double get _totalIgst => _billGstTotals.totalIgst;

  double get _grandTotal => _billGstTotals.grandTotal;

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

  String _formatAmount(double value) => formatMoneyAmount(value);

  String _formatQtyOrPct(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  // ============================================================
  // PRINT (thermal only — no PDF save or preview)
  // ============================================================

  Future<void> _printBillAfterSave(SaleBill bill, int savedBillNo) async {
    if (widget.printAfterSaveOverride != null) {
      await widget.printAfterSaveOverride!(bill, savedBillNo);
      if (!mounted) return;
      _showMessage('Bill $savedBillNo saved');
      return;
    }

    final savedPrinter =
        await PrinterSettingsService.getDefaultPrinter(PrinterType.thermal) ??
            '';

    developer.log(
      'Print starting for bill $savedBillNo (printer: ${savedPrinter.isEmpty ? '(none)' : savedPrinter})',
      name: 'SalesBill.print777',
    );

    try {
      await BillPrintService.printReceipt(
        bill,
        printerName: savedPrinter,
        type: PrinterType.thermal,
      );
      if (!mounted) return;
      developer.log(
        'Print finished for bill $savedBillNo',
        name: 'SalesBill.print777',
      );
      _showMessage('Bill $savedBillNo saved and printed');
    } on BillPrintException catch (e) {
      developer.log(
        'Print failed for bill $savedBillNo: ${e.message}',
        name: 'SalesBill.print777',
        error: e,
      );
      if (!mounted) return;
      await _showPrinterNotConfiguredDialog();
      _showMessage('Print failed: ${e.message}');
    } catch (e, stackTrace) {
      developer.log(
        'Print failed for bill $savedBillNo: $e',
        name: 'SalesBill.print777',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      await _showPrinterNotConfiguredDialog();
      _showMessage('Print failed: $e');
    }
  }

  Future<void> _showPrinterNotConfiguredDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(
          'Printer not found. Choose the thermal printer in Printer settings',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StaffThermalPrinterScreen(),
                ),
              );
            },
            child: const Text('Printer settings'),
          ),
        ],
      ),
    );
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
    final hideDesktopTitleBar = !mobileBillLayout;
    final body = mobileBillLayout
        ? _buildMobileBody(context)
        : _buildDesktopBody(
            context: context,
            showMenuButton: hideDesktopTitleBar && !widget.embeddedInDashboard,
            useSidebarLayout: useSidebarLayout,
          );

    if (widget.embeddedInDashboard) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: hideDesktopTitleBar
            ? null
            : sectionHeaderAppBar('SALES BILL'),
        body: _buildLockedBody(body),
      );
    }

    if (useSidebarLayout) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: hideDesktopTitleBar
            ? null
            : _buildAppBar(
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
      appBar: hideDesktopTitleBar
          ? null
          : _buildAppBar(
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

    return sectionHeaderAppBar(
      'SALES BILL',
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

        final content = FocusTraversalGroup(
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

        return content;
      },
    );
  }

  Future<void> _refreshTodaySales() async {
    try {
      final today = _now();
      _todaySalesLoadedDay = DateTime(today.year, today.month, today.day);
      final summary = await AbstractRepository.getSummaryForDateRange(
        location: _selectedLocation,
        fromDate: today,
        toDate: today,
      );
      if (!mounted) return;
      setState(() {
        _todayAmount = summary.totalSaleAmount;
        _todayGst = summary.totalGst;
        _todayGrandTotal = summary.totalSaleAmount + summary.totalGst;
        _todayPcs = summary.totalPcs;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todayAmount = 0;
        _todayGst = 0;
        _todayGrandTotal = 0;
        _todayPcs = 0;
      });
    }
  }

  Future<void> _onTodaySalesPressed() async {
    final show = !_todaySalesPanelVisible;
    setState(() => _todaySalesPanelVisible = show);
    if (show) {
      await _refreshTodaySales();
    }
  }

  Widget _buildTodaySalesButton() {
    final pressed = _todaySalesPanelVisible;
    return SizedBox(
      width: _topButtonWidth,
      height: _topButtonHeight,
      child: ElevatedButton(
        key: const Key('today_sales_button'),
        onPressed: _busy ? null : _onTodaySalesPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: pressed
              ? AppColors.navy
              : AppColors.actionButton,
          foregroundColor: Colors.white,
          elevation: pressed ? 4 : 0,
          shadowColor: Colors.black45,
          padding: EdgeInsets.zero,
          minimumSize: const Size(_topButtonWidth, _topButtonHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: _normalFontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text('TODAY SALES'),
      ),
    );
  }

  Widget _buildTodaySalesMetricCard({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: _todayCardLabelFontSize,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: _todayCardValueFontSize,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySalesPanel() {
    final title =
        'TODAY SALES - ${DateFormat('dd MMM yyyy').format(_now())}';
    return Container(
      key: const Key('today_sales_panel'),
      width: _todaySalesFrameWidth,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(_framePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            key: const Key('today_sales_panel_title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: _normalFontSize,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildTodaySalesMetricCard(
                  label: 'AMOUNT',
                  value: _formatAmount(_todayAmount),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTodaySalesMetricCard(
                  label: 'GST',
                  value: _formatAmount(_todayGst),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildTodaySalesMetricCard(
                  label: 'PCS',
                  value: formatPcs(_todayPcs),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTodaySalesMetricCard(
                  label: 'TOTAL SALES',
                  value: _formatAmount(_todayGrandTotal),
                ),
              ),
            ],
          ),
        ],
      ),
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
      order: const NumericFocusOrder(6),
      child: SizedBox(
        width: _topButtonWidth,
        height: _topButtonHeight,
        child: ElevatedButton(
          key: const Key('save_sale_bar_button'),
          focusNode: _saveSaleFocus,
          onPressed: _busy ? null : _saveBill,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(_topButtonWidth, _topButtonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: _normalFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          child: const Text('SAVE SALE'),
        ),
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
                child: _buildTodaySalesButton(),
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
                    if (_todaySalesPanelVisible) ...[
                      _buildTodaySalesPanel(),
                    ],
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
                    if (_todaySalesPanelVisible) ...[
                      const SizedBox(width: _framesGap),
                      _buildTodaySalesPanel(),
                    ],
                  ],
                ),
              );
            },
          ),
          if (includeEntryRow) ...[
            const SizedBox(height: _topAreaGap),
            _buildAlignedEntryRow(
              showTax: _items.isNotEmpty,
              gridFontSize: gridFontSize,
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BILL DETAILS
  // ============================================================

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
                  order: const NumericFocusOrder(1),
                  child: DropdownButtonFormField<String>(
                    key: const Key('bill_payment_dropdown'),
                    focusNode: _paymentFocus,
                    value: _paymentMode,
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
                        vertical: 8,
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
                    ),
                    dropdownColor: Colors.white,
                    selectedItemBuilder: (context) {
                      return _paymentModes
                          .map(
                            (mode) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                mode,
                                style: TextStyle(
                                  fontSize: _entryFontSize,
                                  color: _paymentFocus.hasFocus
                                      ? Colors.black
                                      : _paymentTextColor(_paymentMode),
                                  fontWeight: FontWeight.w600,
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
                      _focusGroup();
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
                  key: const Key('bill_date_display'),
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

  // ============================================================
  // CUSTOMER DETAILS
  // ============================================================

  Widget _buildCustomerDetails() {
    const labelStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );

    return Container(
      width: _customerBoxWidth + (_framePadding * 2),
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
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          FocusTraversalOrder(
            order: const NumericFocusOrder(7),
            child: Row(
              children: [
                const SizedBox(width: 56, child: Text('NAME', style: labelStyle)),
                Expanded(
                  child: SizedBox(
                    height: _customerBoxHeight,
                    child: _smallTextField(
                      _customerNameController,
                      focusNode: _nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _focusMobile(),
                      compact: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          FocusTraversalOrder(
            order: const NumericFocusOrder(8),
            child: Row(
              children: [
                const SizedBox(
                  width: 56,
                  child: Text('MOBILE', style: labelStyle),
                ),
                Expanded(
                  child: SizedBox(
                    height: _customerBoxHeight,
                    child: GestureDetector(
                      onDoubleTap: _onMobileDoubleTap,
                      child: _smallTextField(
                        _mobileController,
                        number: true,
                        fieldKey: const Key('bill_mobile_field'),
                        focusNode: _mobileFocus,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => _focusGroup(),
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showPasswordField && !_editUnlocked) ...[
            const SizedBox(height: 6),
            Row(
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

  Widget _buildLabeledCustomerField({
    required String label,
    required Widget child,
    required double fieldWidth,
    NumericFocusOrder? traversalOrder,
  }) {
    final field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: _normalFontSize,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: fieldWidth,
          height: _customerBoxHeight,
          child: child,
        ),
      ],
    );

    if (traversalOrder == null) {
      return field;
    }

    return FocusTraversalOrder(order: traversalOrder, child: field);
  }

  // ============================================================
  // SMALL TEXT FIELD
  // ============================================================

  Widget _smallTextField(
      TextEditingController controller, {
        bool number = false,
        bool compact = false,
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

        keyboardType: number
            ? TextInputType.phone
            : TextInputType.text,

        inputFormatters: number
            ? [
          FilteringTextInputFormatter
              .digitsOnly,
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

  // ============================================================
  // RATE / QTY / AMOUNT
  // ============================================================

  void _updateAmountDisplay() {
    final text = _formatAmount(_currentAmount);
    if (_amountController.text != text) {
      _amountController.text = text;
    }
  }

  InputDecoration _entryDecoration() {
    return InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(),
      focusedBorder: const OutlineInputBorder(),
      disabledBorder: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _entryFieldVerticalPadding,
      ),
      alignLabelWithHint: true,
    );
  }

  InputDecoration _customerFieldDecoration() {
    return InputDecoration(
      isDense: false,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: _customerFieldVerticalPadding,
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
    bool blockTabTraversal = false,
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
      onEditingComplete: onSubmitted,
      decoration: _highlightedInputDecoration(focused: focused),
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(
        fontSize: valueFontSize,
        height: 1,
        color: Colors.black,
      ),
    );

    if (blockTabTraversal) {
      field = Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.tab) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: field,
      );
    }

    if (readOnly && onSubmitted != null) {
      field = Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            onSubmitted();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: field,
      );
    }

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

  Widget _buildStackedGroupDropdown({
    double labelFontSize = _normalFontSize,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'GROUP',
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        FocusTraversalOrder(
          order: const NumericFocusOrder(2),
          child: SizedBox(
            width: _groupBoxWidth,
            height: _entryBoxHeight,
            child: _buildItemMasterDropdown(),
          ),
        ),
      ],
    );
  }

  Widget _buildItemMasterDropdown() {
    final focused = _groupFocus.hasFocus;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          _focusRate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        height: _entryBoxHeight,
        decoration: _highlightedBoxDecoration(focused: focused),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('bill_group_dropdown'),
            focusNode: _groupFocus,
            value: _selectedParticular,
            isExpanded: true,
            itemHeight: _entryBoxHeight,
            alignment: AlignmentDirectional.centerStart,
            dropdownColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            style: const TextStyle(
              fontSize: _entryFontSize,
              color: Colors.black,
              height: 1,
            ),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 28),
            items: kSaleGroups
                .map(
                  (name) => DropdownMenuItem(
                    value: name,
                    child: Text(
                      name,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: _entryFontSize,
                        color: Colors.black,
                        height: 1,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              setState(() {
                _selectedParticular = value;
                _particularError = null;
              });
              _focusRate();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAlignedEntryRow({
    required bool showTax,
    bool mobile = false,
    double gridFontSize = _gridFontSize,
  }) {
    if (mobile) {
      return _buildEntryRowFallbackMobile();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStackedGroupDropdown(),
            const SizedBox(width: _entryColumnGap),
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: () => unawaited(_rateSubmitted()),
              textInputAction: TextInputAction.next,
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
          ],
        ),
        ..._entryRowErrors(),
      ],
    );
  }

  Widget _buildEntryRowFallbackMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: _entryColumnGap,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _buildStackedGroupDropdown(),
            _buildStackedEntryField(
              label: 'RATE',
              controller: _rateController,
              focusNode: _rateFocus,
              onChanged: _rateChanged,
              onSubmitted: () => unawaited(_rateSubmitted()),
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
          ],
        ),
        ..._entryRowErrors(),
      ],
    );
  }

  List<Widget> _entryRowErrors() {
    return [
      if (_rateError != null) ...[
        const SizedBox(height: 4),
        Text(
          _rateError!,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: _normalFontSize,
          ),
        ),
      ],
      if (_qtyError != null) ...[
        const SizedBox(height: 4),
        Text(
          _qtyError!,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: _normalFontSize,
          ),
        ),
      ],
      if (_particularError != null) ...[
        const SizedBox(height: 4),
        Text(
          _particularError!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.danger,
            fontSize: AppTextSizes.listSubtitle,
          ),
        ),
      ],
    ];
  }

  // ============================================================
  // ITEM TABLE
  //
  // BEFORE ITEM (Enter on Qty adds first row):
  //
  // S.NO | RATE | QTY | AMOUNT | Total | CGST % | SGST % | IGST | X
  // ============================================================

  Widget _buildItemTableSection({bool mobile = false}) {
    final showTax = _items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAlignedEntryRow(showTax: showTax, mobile: mobile),
        const SizedBox(height: _topAreaGap),
        _buildGridFrame(showTax: showTax, gridFontSize: _gridFontSize),
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
    final bodyScrollZoneHeight =
        listBodyHeight + _gridHScrollbarStripHeight;

    final horizontalBody = SizedBox(
      width: scrollWidth,
      height: listBodyHeight,
      child: _buildItemRowsList(showTax, gridFontSize, scrollWidth),
    );

    final horizontalBodyScroller = SizedBox(
      height: bodyScrollZoneHeight,
      child: Scrollbar(
        controller: _gridHScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
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
                      height: listBodyHeight,
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
          return SizedBox(
            height: _editRowHeight,
            child: ColoredBox(
              color: const Color(0xFFFFF8E1),
              child: const SizedBox.shrink(),
            ),
          );
        }
        return _buildDeleteCell(index);
      },
    );
  }

  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildTableHeader(
    bool showTax,
    double gridFontSize,
    double scrollWidth,
  ) {
    final headerCells = [
      _tableHeaderCell('S.NO', gridFontSize),
      _tableHeaderCell('GROUP', gridFontSize),
      _tableHeaderCell('RATE', gridFontSize),
      _tableHeaderCell('QTY', gridFontSize),
      _tableHeaderCell('AMOUNT', gridFontSize),
      _tableHeaderCell('TOTAL', gridFontSize, last: !showTax),
      if (showTax) ...[
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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildTableRow(
    int index,
    bool showTax,
    double gridFontSize,
    double scrollWidth,
  ) {
    final BillItem item = _items[index];

    final bool selected = _selectedIndex == index;

    final dataCells = [
      _tableDataCell('${index + 1}', gridFontSize),
      _tableDataCell(
        item.particular.trim().toUpperCase(),
        gridFontSize,
      ),
      _tableDataCell(
        _formatAmount(item.rate),
        gridFontSize,
      ),
      _tableDataCell(
        _formatQtyOrPct(item.qty),
        gridFontSize,
      ),
      _tableDataCell(
        _formatAmount(item.amount),
        gridFontSize,
      ),
      _tableDataCell(
        _formatAmount(item.grossAmt),
        gridFontSize,
        last: !showTax,
      ),
      if (showTax) ...[
        _tableDataCell(
          _formatQtyOrPct(item.cgstPct),
          gridFontSize,
        ),
        _tableDataCell(
          _formatQtyOrPct(item.sgstPct),
          gridFontSize,
        ),
        _tableDataCell(
          _formatAmount(item.igst),
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
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            icon: const Icon(Icons.close, color: AppColors.danger, size: 18),
            tooltip: 'Remove item',
            onPressed: () => _removeItem(index),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TABLE DATA CELL
  // ============================================================

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

  // ============================================================
  // GRID FOOTER (Total + Grand total rows)
  // ============================================================

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
    final words = amountInWords(_grandTotal).toUpperCase();
    final qtyLabel = '${formatPcs(_totalQty)} (total pcs)';
    final primary = _primaryGridColWidth;

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
                  child: Row(
                    children: [
                      SizedBox(
                        width: primary,
                        child: _footerLabelCell('Total', last: false),
                      ),
                      SizedBox(width: primary, child: _footerLabelCell('')),
                      SizedBox(width: primary, child: _footerLabelCell('')),
                      SizedBox(
                        width: primary,
                        child: _footerLabelCell(qtyLabel),
                      ),
                      SizedBox(
                        width: primary,
                        child: _footerLabelCell(
                          _formatAmount(_totalAmount),
                          last: true,
                        ),
                      ),
                    ],
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
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'GRAND TOTAL',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontSize: _grandTotalLabelFontSize,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: primary * 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
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
                          _formatAmount(_grandTotal),
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
                SizedBox(width: _deleteColWidth),
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
    _calendarDayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
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

    _groupFocus.dispose();
    _paymentFocus.dispose();
    _saveSaleFocus.dispose();

    _gridHeaderHScrollController.dispose();
    _gridHScrollController.dispose();
    _gridVScrollController.dispose();
    _gridDeleteVScrollController.dispose();

    super.dispose();
  }
}
