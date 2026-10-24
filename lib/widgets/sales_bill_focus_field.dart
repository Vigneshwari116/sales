import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/sales_bill_toolbar.dart';

/// White fill by default, cyan when focused — bill screen only.
InputDecoration salesBillFieldDecoration({
  required bool focused,
  bool readOnly = false,
  EdgeInsetsGeometry? contentPadding,
}) {
  final fill = focused && !readOnly
      ? SalesBillLayout.focusFill
      : Colors.white;

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border, width: 1.2),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
  );
}

/// Rebuilds when [focusNode] gains or loses focus so fill colour updates.
class SalesBillFocusTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final TextStyle? style;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;
  final Key? fieldKey;
  final bool blockTabTraversal;

  const SalesBillFocusTextField({
    super.key,
    this.fieldKey,
    required this.controller,
    this.focusNode,
    this.readOnly = false,
    this.keyboardType,
    this.inputFormatters,
    this.textAlign = TextAlign.center,
    this.style,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.decoration,
    this.blockTabTraversal = false,
  });

  @override
  State<SalesBillFocusTextField> createState() =>
      _SalesBillFocusTextFieldState();
}

class _SalesBillFocusTextFieldState extends State<SalesBillFocusTextField> {
  FocusNode? _ownedFocusNode;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
    _effectiveFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SalesBillFocusTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _ownedFocusNode?.removeListener(_onFocusChange);
      if (widget.focusNode == null && _ownedFocusNode == null) {
        _ownedFocusNode = FocusNode();
      }
      _effectiveFocusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final decoration = widget.decoration ??
        salesBillFieldDecoration(
          focused: _effectiveFocusNode.hasFocus,
          readOnly: widget.readOnly,
        );

    Widget field = TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _effectiveFocusNode,
      readOnly: widget.readOnly,
      showCursor: !widget.readOnly,
      enableInteractiveSelection: !widget.readOnly,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
      decoration: decoration,
    );

    if (widget.blockTabTraversal) {
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

    return field;
  }
}
