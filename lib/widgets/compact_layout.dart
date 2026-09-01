import 'package:flutter/material.dart';

/// Compact date field — input-sized height, no oversized full-bleed row.
class CompactDateField extends StatelessWidget {
  static const Color border = Color(0xFF888888);

  final String label;
  final String valueText;
  final VoidCallback onTap;

  const CompactDateField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$label: $valueText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centers [child] and clamps width for dashboard/abstract content panels.
class CenteredContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const CenteredContent({
    super.key,
    required this.child,
    this.maxWidth = 720,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
