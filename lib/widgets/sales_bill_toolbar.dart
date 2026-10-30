import 'package:flutter/material.dart';
import 'package:sales/theme/app_theme.dart';

/// Layout tokens for the legacy Surabhi-style sales bill screen.
class SalesBillLayout {
  SalesBillLayout._();

  static const double actionButtonWidth = 150;
  static const double actionButtonHeight = 44;
  static const double actionButtonFontSize = 18;
  static const double actionButtonSpacing = 10;

  static const double entryFieldWidth = 150;
  static const double entryFieldHeight = 48;
  static const double entryFieldFontSize = 22;
  static const double entryFieldGap = 14;
  static const double entryLabelFontSize = 14;

  static const double billNoBoxWidth = 88;
  static const double billNoBoxHeight = 36;
  static const double billRowControlHeight = 36;

  static const Color billNoFill = Color(0xFF7FE8E8);
  static const Color focusFill = Color(0xFF7FE8E8);
  static const Color dateBoxFill = Color(0xFFF3F3F3);

  static double get inputRowWidth => entryFieldWidth * 3 + entryFieldGap * 2;
}

/// Large maroon / black action buttons for the bill screen (not shared app-wide).
class SalesBillToolbar extends StatelessWidget {
  final VoidCallback? onTodaySales;
  final VoidCallback? onNew;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSave;
  final bool busy;
  final bool saveEnabled;

  const SalesBillToolbar({
    super.key,
    required this.onTodaySales,
    required this.onNew,
    required this.onPrevious,
    required this.onNext,
    required this.onSave,
    this.busy = false,
    this.saveEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SalesBillLayout.actionButtonSpacing,
      runSpacing: SalesBillLayout.actionButtonSpacing,
      children: [
        _SalesBillToolbarButton(
          key: const Key('bill_today_sales_button'),
          label: 'TODAY SALES',
          onPressed: busy ? null : onTodaySales,
        ),
        _SalesBillToolbarButton(
          key: const Key('bill_new_button'),
          label: 'NEW',
          onPressed: busy ? null : onNew,
        ),
        _SalesBillToolbarButton(
          key: const Key('bill_previous_button'),
          label: 'PREVIOUS',
          onPressed: busy ? null : onPrevious,
        ),
        _SalesBillToolbarButton(
          key: const Key('bill_next_button'),
          label: 'NEXT',
          onPressed: busy ? null : onNext,
        ),
        _SalesBillToolbarButton(
          key: const Key('bill_save_sale_button'),
          label: 'SAVE SALE',
          onPressed: (busy || !saveEnabled) ? null : onSave,
          backgroundColor: AppColors.navy,
        ),
      ],
    );
  }
}

class _SalesBillToolbarButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;

  const _SalesBillToolbarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SalesBillLayout.actionButtonWidth,
      height: SalesBillLayout.actionButtonHeight,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.actionButton,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(
            SalesBillLayout.actionButtonWidth,
            SalesBillLayout.actionButtonHeight,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: const TextStyle(
            fontSize: SalesBillLayout.actionButtonFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}
