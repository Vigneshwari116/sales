import 'package:flutter/material.dart';

class SidebarNavItem {
  final Key? key;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SidebarNavItem({
    this.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

/// Icon-only when collapsed; icon + label on one row when expanded.
class CollapsibleSidebar extends StatelessWidget {
  static const Color defaultBackground = Color(0xFFC5F6C5);
  static const double expandedWidth = 200;
  static const double collapsedWidth = 56;

  final bool expanded;
  final VoidCallback onToggle;
  final List<SidebarNavItem> items;
  final Widget? header;
  final Widget? footer;
  final Color backgroundColor;

  const CollapsibleSidebar({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.items,
    this.header,
    this.footer,
    this.backgroundColor = defaultBackground,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: expanded ? expandedWidth : collapsedWidth,
      color: backgroundColor,
      child: Column(
        children: [
          _buildToggleRow(),
          if (header != null) header!,
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in items) _buildNavItem(item),
              ],
            ),
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }

  Widget _buildToggleRow() {
    return SizedBox(
      height: 48,
      child: IconButton(
        key: const Key('sidebar_hamburger_toggle'),
        tooltip: expanded ? 'Collapse menu' : 'Expand menu',
        onPressed: onToggle,
        icon: Icon(expanded ? Icons.menu_open : Icons.menu),
      ),
    );
  }

  Widget _buildNavItem(SidebarNavItem item) {
    final content = Material(
      color: item.selected ? const Color(0xFFB8E8B8) : Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 8,
            vertical: 10,
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 22),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (expanded) {
      return KeyedSubtree(key: item.key, child: content);
    }

    return KeyedSubtree(
      key: item.key,
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 400),
        child: content,
      ),
    );
  }
}
