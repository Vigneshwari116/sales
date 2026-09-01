
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sales/config/app_config.dart';
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

class SalesBillScreen extends StatefulWidget {
  /// When true, navigation is provided by [StaffDashboardScreen].
  final bool embeddedInDashboard;

  /// When set (tests only), replaces the default [SalesLedgerScreen] route.
  @visibleForTesting
  final Widget Function(String location)? ledgerScreenBuilder;

  /// When set (tests only), skips async local DB bill-number load on open.
  @visibleForTesting
  final int? initialBillNo;

  const SalesBillScreen({
    super.key,
    this.embeddedInDashboard = false,
    this.initialBillNo,
    this.ledgerScreenBuilder,
  });

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen> {
  // ============================================================
  // COLORS
  // ============================================================

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
  // AUTO FOCUS TIMERS — removed; field advance is Enter-only.
  // ============================================================

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

    _manualPushInProgress = SyncService.instance.manualPushInProgress.value;
    SyncService.instance.manualPushInProgress.addListener(_onManualPushChanged);

    _loadGstRates();

    if (widget.initialBillNo != null) {
      _billNo = widget.initialBillNo!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusRate();
      });
    } else {
      _restoreSessionOrLoadBill().then((_) {
        if (mounted) {
          _focusRate();
        }
      });
    }
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
  // RATE ENTER
  // ============================================================

  void _rateSubmitted() {
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

    final defaultPrinter = await PrinterSettingsService.getDefaultPrinter(
      PrinterType.thermal,
    );

    if (defaultPrinter == null || defaultPrinter.isEmpty) {
      if (!mounted) return;
      setState(() {
        _billSaved = true;
        _busy = false;
      });
      _showMessage(
        'No thermal printer selected. Please choose one in Printer Settings.',
      );
    } else {
      try {
        await BillPrintService.printReceipt(
          bill,
          printerName: defaultPrinter,
          type: PrinterType.thermal,
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
      return AppBar(
        title: const Text(
          'Sales Bill',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.headerBand,
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
      backgroundColor: AppColors.headerBand,
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
          color: AppColors.border,
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
                      AppColors.border,
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
            backgroundColor: AppColors.navy,

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
        border: Border.all(color: AppColors.border),
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
    return TextField(
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

        style: const TextStyle(
          fontSize: AppTextSizes.fieldText,
        ),

        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
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
    bool blockTabTraversal = false,
    TextInputAction? textInputAction,
    Key? fieldKey,
  }) {
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
      decoration: _entryDecoration(),
      style: const TextStyle(fontSize: 15, height: 1),
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

    return _buildEntryBox(
      label: label,
      fullWidth: fullWidth,
      child: field,
    );
  }

  Widget _buildRateQtyAmount({bool mobile = false}) {
    final fields = mobile
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildEntryField(
                  label: 'RATE',
                  controller: _rateController,
                  focusNode: _rateFocus,
                  onChanged: _rateChanged,
                  onSubmitted: _rateSubmitted,
                  blockTabTraversal: true,
                  textInputAction: TextInputAction.next,
                  fieldKey: const Key('bill_rate_field'),
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
                  blockTabTraversal: true,
                  textInputAction: TextInputAction.done,
                  fieldKey: const Key('bill_qty_field'),
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
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildEntryField(
                label: 'RATE',
                controller: _rateController,
                focusNode: _rateFocus,
                onChanged: _rateChanged,
                onSubmitted: _rateSubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.next,
                fieldKey: const Key('bill_rate_field'),
              ),
              const SizedBox(width: 12),
              _buildEntryField(
                label: 'QTY',
                controller: _qtyController,
                focusNode: _qtyFocus,
                onChanged: _qtyChanged,
                onSubmitted: _qtySubmitted,
                blockTabTraversal: true,
                textInputAction: TextInputAction.done,
                fieldKey: const Key('bill_qty_field'),
              ),
              const SizedBox(width: 12),
              _buildEntryField(
                label: 'AMOUNT',
                controller: _amountController,
                readOnly: true,
              ),
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          mobile ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
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
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildTableHeader(showTax),
          Expanded(
            child: _items.isEmpty
                ? ColoredBox(color: AppColors.background)
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
      color: AppColors.tableHeader,
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
                : BorderSide(color: AppColors.border, width: 0.6),
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
            bottom: BorderSide(color: AppColors.border, width: 0.6),
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

    final bool selected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = selected ? null : index;
        });
      },
      child: Container(
        height: 34,
        color: selected ? const Color(0xFFFFE5A0) : AppColors.background,
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
            _buildDeleteCell(index),
          ],
        ),
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
            bottom: BorderSide(color: AppColors.border, width: 0.6),
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.close, color: AppColors.danger, size: 16),
          tooltip: 'Remove item',
          onPressed: () => _removeItem(index),
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
                : BorderSide(color: AppColors.border, width: 0.6),
            bottom: BorderSide(color: AppColors.border, width: 0.6),
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
    SyncService.instance.manualPushInProgress
        .removeListener(_onManualPushChanged);
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
