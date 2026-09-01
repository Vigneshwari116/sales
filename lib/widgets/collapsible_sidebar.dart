import 'package:flutter/material.dart';
import 'package:sales/theme/app_theme.dart';

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

/// Compact navy rail: icon-only when collapsed; icon + label when expanded.
class CollapsibleSidebar extends StatelessWidget {
  static const double expandedWidth = 168;
  static const double collapsedWidth = 52;

  final bool expanded;
  final VoidCallback onToggle;
  final List<SidebarNavItem> items;
  final Widget? header;
  final Widget? footer;

  const CollapsibleSidebar({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.items,
    this.header,
    this.footer,
    @Deprecated('Sidebar always uses drawerNavy') Color? backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: expanded ? expandedWidth : collapsedWidth,
      color: AppColors.drawerNavy,
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Only show labels once the rail is wide enough — avoids overflow
            // mid-animation when expanded flips before width finishes tweening.
            final showLabels = constraints.maxWidth >= expandedWidth - 4;
            return Column(
              children: [
                _buildToggleRow(),
                if (header != null && showLabels) header!,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final item in items) _buildNavItem(item, showLabels),
                    ],
                  ),
                ),
                if (footer != null) footer!,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildToggleRow() {
    return SizedBox(
      height: 40,
      child: IconButton(
        key: const Key('sidebar_hamburger_toggle'),
        tooltip: expanded ? 'Collapse menu' : 'Expand menu',
        onPressed: onToggle,
        color: Colors.white,
        iconSize: 20,
        icon: Icon(expanded ? Icons.menu_open : Icons.menu),
      ),
    );
  }

  Widget _buildNavItem(SidebarNavItem item, bool showLabels) {
    final content = Material(
      color: item.selected ? AppColors.drawerActive : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: showLabels ? 10 : 0,
            vertical: 8,
          ),
          child: Row(
            mainAxisAlignment:
                showLabels ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 18, color: Colors.white),
              if (showLabels) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final padded = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: content,
    );

    if (showLabels) {
      return KeyedSubtree(key: item.key, child: padded);
    }

    return KeyedSubtree(
      key: item.key,
      child: Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 400),
        child: padded,
      ),
    );
  }
}
