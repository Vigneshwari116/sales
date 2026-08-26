import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sales/screen/number%20to%20words.dart';
import 'bill_item.dart';
import 'login_screen.dart';

class SalesBillScreen extends StatefulWidget {
  const SalesBillScreen({super.key});

  @override
  State<SalesBillScreen> createState() => _SalesBillScreenState();
}

class _SalesBillScreenState extends State<SalesBillScreen> {
  // ---------------------------------------------------------------------------
  // ORIGINAL SALES BILL COLOURS
  // ---------------------------------------------------------------------------

  static const Color _greenBg = Color(0xFFA8FFA8);
  static const Color _red = Color(0xFF9E1B0B);
  static const Color _cyan = Color(0xFF62D8E0);
  static const Color _border = Color(0xFF808080);
  static const Color _header = Color(0xFFFFF6B5);

  // ---------------------------------------------------------------------------
  // BILL DATA
  // ---------------------------------------------------------------------------

  int _billNo = 23255;
  DateTime _billDate = DateTime.now();

  String _paymentMode = 'CASH';

  final List<String> _paymentModes = <String>[
    'CASH',
    'PHONE PEE',
    'CARD',
  ];

  String _customerName = 'CASH';

  final List<String> _customerNames = <String>[
    'CASH',
    'CREDIT',
  ];

  final TextEditingController _mobileController =
  TextEditingController();

  final TextEditingController _rateController =
  TextEditingController(text: '0');

  final TextEditingController _qtyController =
  TextEditingController(text: '1');

  String _printer = 'TVS-E RP 3230 on Ne00:';

  final List<String> _printers = <String>[
    'TVS-E RP 3230 on Ne00:',
    'Microsoft Print to PDF',
    'EPSON LX-310 on Ne01:',
  ];

  // ---------------------------------------------------------------------------
  // ITEMS
  // ---------------------------------------------------------------------------

  final List<BillItem> _items = <BillItem>[];

  int? _selectedRow;

  // ---------------------------------------------------------------------------
  // CALCULATIONS
  // ---------------------------------------------------------------------------

  double get _previewRate {
    return double.tryParse(_rateController.text) ?? 0;
  }

  double get _previewQty {
    return double.tryParse(_qtyController.text) ?? 0;
  }

  double get _amountPreview {
    return _previewRate * _previewQty;
  }

  double get _totalQty {
    return _items.fold<double>(
      0,
          (double total, BillItem item) => total + item.qty,
    );
  }

  double get _totalAmt {
    return _items.fold<double>(
      0,
          (double total, BillItem item) => total + item.taxableAmt,
    );
  }

  double get _totalCgst {
    return _items.fold<double>(
      0,
          (double total, BillItem item) => total + item.cgst,
    );
  }

  double get _totalSgst {
    return _items.fold<double>(
      0,
          (double total, BillItem item) => total + item.sgst,
    );
  }

  double get _totalIgst {
    return _items.fold<double>(
      0,
          (double total, BillItem item) => total + item.igst,
    );
  }

  double get _grandTotal {
    return _totalAmt +
        _totalCgst +
        _totalSgst +
        _totalIgst;
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  String get _dateText {
    return '${_billDate.day.toString().padLeft(2, '0')}/'
        '${_billDate.month.toString().padLeft(2, '0')}/'
        '${_billDate.year}';
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // The original Sales Bill is a landscape desktop screen.
    SystemChrome.setPreferredOrientations(
      const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _rateController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ADD / UPDATE
  // ---------------------------------------------------------------------------

  void _addItem() {
    final double? rate = double.tryParse(_rateController.text);
    final double? qty = double.tryParse(_qtyController.text);

    if (rate == null || qty == null || rate <= 0 || qty <= 0) {
      _showMessage('Enter a valid Rate and Qty');
      return;
    }

    setState(() {
      if (_selectedRow != null) {
        _items[_selectedRow!] = _items[_selectedRow!].copyWith(
          rate: rate,
          qty: qty,
        );

        _selectedRow = null;
      } else {
        _items.add(
          BillItem(
            qty: qty,
            rate: rate,
          ),
        );
      }

      _rateController.text = '0';
      _qtyController.text = '1';
    });
  }

  // ---------------------------------------------------------------------------
  // MODIFY
  // ---------------------------------------------------------------------------

  void _modifySelected() {
    if (_selectedRow == null) {
      _showMessage('Select a row first');
      return;
    }

    final BillItem item = _items[_selectedRow!];

    setState(() {
      _rateController.text = _format(item.rate);
      _qtyController.text = _format(item.qty);
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE ITEM
  // ---------------------------------------------------------------------------

  void _deleteSelectedItem() {
    if (_selectedRow == null) {
      _showMessage('Select a row first');
      return;
    }

    setState(() {
      _items.removeAt(_selectedRow!);
      _selectedRow = null;
    });
  }

  // ---------------------------------------------------------------------------
  // NEW BILL
  // ---------------------------------------------------------------------------

  void _newBill() {
    setState(() {
      _billNo++;
      _billDate = DateTime.now();

      _paymentMode = 'CASH';
      _customerName = 'CASH';

      _mobileController.clear();

      _rateController.text = '0';
      _qtyController.text = '1';

      _items.clear();
      _selectedRow = null;
    });
  }

  // ---------------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------------

  void _saveBill() {
    if (_items.isEmpty) {
      _showMessage('Add at least one item');
      return;
    }

    _showMessage(
      'Bill $_billNo saved - Grand Total ${_format(_grandTotal)}',
    );
  }

  // ---------------------------------------------------------------------------
  // TOP BUTTON ACTIONS
  // ---------------------------------------------------------------------------

  void _printBill() {
    _showMessage('Printing Bill No $_billNo');
  }

  void _nextBill() {
    _showMessage('Next Bill');
  }

  void _previousBill() {
    _showMessage('Previous Bill');
  }

  void _editBill() {
    _showMessage('Edit Bill');
  }

  void _deleteBill() {
    _showMessage('Delete Bill $_billNo');
  }

  void _exitScreen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE PICKER
  // ---------------------------------------------------------------------------

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _billDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _billDate = picked;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // MESSAGE
  // ---------------------------------------------------------------------------

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
              BuildContext context,
              BoxConstraints constraints,
              ) {
            return Column(
              children: <Widget>[
                _buildTopArea(),
                const SizedBox(height: 2),
                Expanded(
                  child: _buildMainArea(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // TOP AREA
  // ===========================================================================

  Widget _buildTopArea() {
    return SizedBox(
      height: 67,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // -------------------------------------------------------------------
          // BILL DETAILS
          // -------------------------------------------------------------------

          SizedBox(
            width: 245,
            child: Padding(
              padding: const EdgeInsets.only(
                left: 5,
                top: 2,
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 67,
                        child: Text(
                          'BILL NO:',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _smallValueBox(
                        text: '$_billNo',
                        width: 72,
                        background: _cyan,
                      ),
                      const SizedBox(width: 3),
                      SizedBox(
                        width: 86,
                        height: 18,
                        child: _smallDropdown(
                          value: _paymentMode,
                          items: _paymentModes,
                          onChanged: (String? value) {
                            if (value != null) {
                              setState(() {
                                _paymentMode = value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 67,
                        child: Text(
                          'BILL DATE:',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _pickDate,
                        child: _smallValueBox(
                          text: _dateText,
                          width: 95,
                          background: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // CUSTOMER DETAILS
          // -------------------------------------------------------------------

          Expanded(
            child: Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Buttons
                    _topButton('PRINT', _printBill),
                    _topButton('NEW', _newBill),
                    _topButton('NEXT', _nextBill),
                    _topButton('PREVIOUS', _previousBill),
                    _topButton('SAVE', _saveBill),
                    _topButton('EDIT', _editBill),
                    _topButton('DELETE', _deleteBill),
                    _topButton('EXIT', _exitScreen),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 55,
                      child: Text(
                        'Name',
                        style: TextStyle(fontSize: 9),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 18,
                        child: _smallDropdown(
                          value: _customerName,
                          items: _customerNames,
                          onChanged: (String? value) {
                            if (value != null) {
                              setState(() {
                                _customerName = value;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const SizedBox(
                      width: 42,
                      child: Text(
                        'MOBILE',
                        style: TextStyle(fontSize: 9),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 18,
                        child: _smallTextField(
                          controller: _mobileController,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    const Spacer(),
                    SizedBox(
                      width: 180,
                      height: 18,
                      child: _smallDropdown(
                        value: _printer,
                        items: _printers,
                        onChanged: (String? value) {
                          if (value != null) {
                            setState(() {
                              _printer = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MAIN AREA
  // ===========================================================================

  Widget _buildMainArea() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---------------------------------------------------------------------
        // LEFT SIDE - ENTRY + GRID
        // ---------------------------------------------------------------------

        Expanded(
          flex: 62,
          child: Column(
            children: <Widget>[
              _buildEntryArea(),
              const SizedBox(height: 2),
              Expanded(
                child: _buildItemGrid(),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // ---------------------------------------------------------------------
        // RIGHT SIDE - MODIFY / DELETE / TOTALS
        // ---------------------------------------------------------------------

        Expanded(
          flex: 38,
          child: _buildRightPanel(),
        ),
      ],
    );
  }

  // ===========================================================================
  // RATE / QTY / AMOUNT
  // ===========================================================================

  Widget _buildEntryArea() {
    return SizedBox(
      height: 65,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(width: 108),

          // RATE
          Expanded(
            child: _largeInput(
              label: 'RATE',
              controller: _rateController,
              alignRight: true,
              onChanged: () {
                setState(() {});
              },
              onSubmitted: _addItem,
            ),
          ),

          const SizedBox(width: 10),

          // QTY
          Expanded(
            child: _largeInput(
              label: 'QTY',
              controller: _qtyController,
              alignRight: true,
              onChanged: () {
                setState(() {});
              },
              onSubmitted: _addItem,
            ),
          ),

          const SizedBox(width: 10),

          // AMOUNT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'AMOUNT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: _border,
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 5),
                  child: Text(
                    _format(_amountPreview),
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ===========================================================================
  // ITEM GRID
  // ===========================================================================

  Widget _buildItemGrid() {
    return Container(
      margin: const EdgeInsets.only(
        left: 7,
        bottom: 3,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: _border,
          width: 1,
        ),
      ),
      child: Column(
        children: <Widget>[
          // Header
          SizedBox(
            height: 20,
            child: Row(
              children: <Widget>[
                _gridHeaderCell(
                  'S.no',
                  flex: 8,
                ),
                _gridHeaderCell(
                  'Qty',
                  flex: 12,
                ),
                _gridHeaderCell(
                  'RATE',
                  flex: 18,
                ),
                _gridHeaderCell(
                  'AMOUNT',
                  flex: 26,
                ),
                _gridHeaderCell(
                  't amt',
                  flex: 16,
                ),
              ],
            ),
          ),

          // Rows
          Expanded(
            child: _items.isEmpty
                ? const SizedBox()
                : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _items.length,
              itemBuilder: (
                  BuildContext context,
                  int index,
                  ) {
                return _buildGridRow(
                  index,
                  _items[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridRow(
      int index,
      BillItem item,
      ) {
    final bool selected = _selectedRow == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRow = index;
        });
      },
      child: Container(
        height: 20,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFFF80)
              : _greenBg,
          border: const Border(
            bottom: BorderSide(
              color: Color(0xFFB0B0B0),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            _gridDataCell(
              '${index + 1}',
              flex: 8,
              selected: selected,
            ),
            _gridDataCell(
              _format(item.qty),
              flex: 12,
              selected: selected,
            ),
            _gridDataCell(
              _format(item.rate),
              flex: 18,
              selected: selected,
            ),
            _gridDataCell(
              _format(item.amount),
              flex: 26,
              selected: selected,
            ),
            _gridDataCell(
              _format(item.taxableAmt),
              flex: 16,
              selected: selected,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // RIGHT SIDE
  // ===========================================================================

  Widget _buildRightPanel() {
    return Column(
      children: <Widget>[
        // MODIFY
        Row(
          children: <Widget>[
            const Spacer(),
            _actionButton(
              'MODIFY',
              _modifySelected,
              width: 62,
            ),
            const SizedBox(width: 3),
          ],
        ),

        const SizedBox(height: 2),

        // DELETE
        Row(
          children: <Widget>[
            const Spacer(),
            _actionButton(
              'DELETE',
              _deleteSelectedItem,
              width: 62,
            ),
            const SizedBox(width: 3),
          ],
        ),

        const SizedBox(height: 10),

        // TOTAL QUANTITY
        _totalBox(
          label: '',
          value: _format(_totalQty),
          large: false,
        ),

        const SizedBox(height: 4),

        // TOTAL AMOUNT
        _totalBox(
          label: 'Total Amt',
          value: _format(_totalAmt),
        ),

        const SizedBox(height: 2),

        // CGST
        _totalBox(
          label: 'CGST',
          value: _format(_totalCgst),
        ),

        const SizedBox(height: 2),

        // SGST
        _totalBox(
          label: 'SGST',
          value: _format(_totalSgst),
        ),

        const SizedBox(height: 2),

        // IGST
        _totalBox(
          label: 'IGST',
          value: _format(_totalIgst),
        ),

        const SizedBox(height: 10),

        // GRAND TOTAL
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            const Expanded(
              flex: 30,
              child: Text(
                'Grand Total',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Expanded(
              flex: 70,
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: _border,
                    width: 1,
                  ),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _format(_grandTotal),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),

        const SizedBox(height: 8),

        // AMOUNT IN WORDS
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(
              right: 8,
              bottom: 3,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: _border,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 3,
            ),
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: Text(
                amountInWords(_grandTotal),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SMALL TOP BUTTON
  // ===========================================================================

  Widget _topButton(
      String text,
      VoidCallback onPressed,
      ) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      height: 20,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _red,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MODIFY / DELETE BUTTON
  // ===========================================================================

  Widget _actionButton(
      String text,
      VoidCallback onPressed, {
        double width = 62,
      }) {
    return SizedBox(
      width: width,
      height: 18,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _red,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TOTAL BOX
  // ===========================================================================

  Widget _totalBox({
    required String label,
    required String value,
    bool large = false,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 34,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 9,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          flex: 32,
          child: Container(
            height: large ? 25 : 17,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: _border,
                width: 1,
              ),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              value,
              style: TextStyle(
                fontSize: large ? 16 : 9,
              ),
            ),
          ),
        ),
        const Spacer(flex: 34),
      ],
    );
  }

  // ===========================================================================
  // LARGE INPUT
  // ===========================================================================

  Widget _largeInput({
    required String label,
    required TextEditingController controller,
    required bool alignRight,
    required VoidCallback onChanged,
    required VoidCallback onSubmitted,
  }) {
    return Column(
      children: <Widget>[
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _border,
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            textAlign:
            alignRight ? TextAlign.right : TextAlign.left,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d*\.?\d*'),
              ),
            ],
            style: const TextStyle(
              fontSize: 16,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 5,
              ),
              isDense: true,
            ),
            onChanged: (_) {
              onChanged();
            },
            onSubmitted: (_) {
              onSubmitted();
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // GRID HEADER CELL
  // ===========================================================================

  Widget _gridHeaderCell(
      String text, {
        required int flex,
      }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _header,
          border: Border(
            right: BorderSide(
              color: _border,
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // GRID DATA CELL
  // ===========================================================================

  Widget _gridDataCell(
      String text, {
        required int flex,
        required bool selected,
      }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFFF80)
              : _greenBg,
          border: Border(
            right: BorderSide(
              color: _border,
              width: 0.5,
            ),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 8,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SMALL VALUE BOX
  // ===========================================================================

  Widget _smallValueBox({
    required String text,
    required double width,
    required Color background,
  }) {
    return Container(
      width: width,
      height: 18,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: _border,
          width: 1,
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 8,
        ),
      ),
    );
  }

  // ===========================================================================
  // SMALL TEXT FIELD
  // ===========================================================================

  Widget _smallTextField({
    required TextEditingController controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _border,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          fontSize: 8,
        ),
        keyboardType: TextInputType.phone,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 3,
            vertical: 2,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SMALL DROPDOWN
  // ===========================================================================

  Widget _smallDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          iconSize: 12,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 8,
          ),
          items: items.map(
                (String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8,
                  ),
                ),
              );
            },
          ).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}