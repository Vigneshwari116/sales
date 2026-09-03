import 'package:flutter/material.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/sales_abstract_screen.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/screen/staff_sales_dashboard_screen.dart';
import 'package:sales/screen/staff_thermal_printer_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/collapsible_sidebar.dart';
import 'package:sales/widgets/compact_layout.dart';

enum _StaffSection {
  dashboard,
  bill,
  abstract,
  ledger,
  printer,
  sync,
}

/// Staff shell with collapsible navy sidebar (icon-only or icon + label row).
class StaffDashboardScreen extends StatefulWidget {
  @visibleForTesting
  final Widget Function(String location)? ledgerScreenBuilder;

  const StaffDashboardScreen({
    super.key,
    this.ledgerScreenBuilder,
  });

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  _StaffSection _selectedSection = _StaffSection.bill;
  bool _sidebarExpanded = false;
  int _refreshGeneration = 0;

  String get _location => AppConfig.displayLocationName;

  int get _selectedIndex => _selectedSection.index;

  void _selectSection(_StaffSection section) {
    setState(() {
      _selectedSection = section;
      if (_isLocalDataSection(section)) {
        _refreshGeneration++;
      }
    });
  }

  bool _isLocalDataSection(_StaffSection section) {
    return section == _StaffSection.dashboard ||
        section == _StaffSection.abstract ||
        section == _StaffSection.ledger;
  }

  Future<void> _logout() async {
    await AppSessionService.onLogout();
    await AppConfig.clearLocation();
    await SessionService.clearLogin();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String _sectionLabel(_StaffSection section) {
    switch (section) {
      case _StaffSection.dashboard:
        return 'DASHBOARD';
      case _StaffSection.bill:
        return 'BILL';
      case _StaffSection.abstract:
        return 'ABSTRACT';
      case _StaffSection.ledger:
        return 'LEDGER';
      case _StaffSection.printer:
        return 'PRINTER';
      case _StaffSection.sync:
        return 'SYNC';
    }
  }

  IconData _sectionIcon(_StaffSection section) {
    switch (section) {
      case _StaffSection.dashboard:
        return Icons.dashboard_outlined;
      case _StaffSection.bill:
        return Icons.receipt_long_outlined;
      case _StaffSection.abstract:
        return Icons.summarize_outlined;
      case _StaffSection.ledger:
        return Icons.menu_book_outlined;
      case _StaffSection.printer:
        return Icons.print_outlined;
      case _StaffSection.sync:
        return Icons.cloud_upload_outlined;
    }
  }

  Widget _buildSectionBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        StaffSalesDashboardScreen(
          location: _location,
          refreshGeneration: _refreshGeneration,
        ),
        SalesBillScreen(
          embeddedInDashboard: true,
          isSectionActive: _selectedSection == _StaffSection.bill,
          ledgerScreenBuilder: widget.ledgerScreenBuilder,
        ),
        SalesAbstractScreen(
          location: _location,
          refreshGeneration: _refreshGeneration,
        ),
        widget.ledgerScreenBuilder?.call(_location) ??
            SalesLedgerScreen(
              location: _location,
              embeddedInDashboard: true,
              refreshGeneration: _refreshGeneration,
            ),
        const StaffThermalPrinterScreen(),
        const _StaffSyncPanel(),
      ],
    );
  }

  List<SidebarNavItem> _navItems() {
    return [
      for (final section in _StaffSection.values)
        SidebarNavItem(
          key: Key('staff_nav_${section.name}'),
          icon: _sectionIcon(section),
          label: _sectionLabel(section),
          selected: _selectedSection == section,
          onTap: () => _selectSection(section),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('staff_dashboard_shell'),
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          CollapsibleSidebar(
            key: const Key('staff_collapsible_sidebar'),
            expanded: _sidebarExpanded,
            onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            header: _sidebarExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sales',
                          style: TextStyle(
                            fontSize: AppTextSizes.appBarTitle,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _location,
                          style: const TextStyle(
                            fontSize: AppTextSizes.listSubtitle,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            footer: Tooltip(
              message: 'LOGOUT',
              child: IconButton(
                key: const Key('staff_nav_logout'),
                tooltip: _sidebarExpanded ? null : 'LOGOUT',
                onPressed: _logout,
                color: Colors.white,
                icon: const Icon(Icons.logout),
              ),
            ),
            items: _navItems(),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildSectionBody()),
        ],
      ),
    );
  }
}

class _StaffSyncPanel extends StatefulWidget {
  const _StaffSyncPanel();

  @override
  State<_StaffSyncPanel> createState() => _StaffSyncPanelState();
}

class _StaffSyncPanelState extends State<_StaffSyncPanel> {
  bool _syncing = false;
  String? _message;
  bool? _lastSyncOk;

  Future<void> _syncNow() async {
    final allowed = await SyncGateService.confirmSync(context);
    if (!allowed || !mounted) return;

    setState(() {
      _syncing = true;
      _message = null;
      _lastSyncOk = null;
    });

    final result = await SyncService.instance.manualSync(
      AppConfig.displayLocationName,
    );

    if (!mounted) return;

    setState(() {
      _syncing = false;
      _message = result.summaryMessage;
      _lastSyncOk = result.ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar(
        'SYNC',
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Push pending bills and pull admin updates.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppTextSizes.fieldText),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      key: const Key('staff_sync_now_button'),
                      onPressed: _syncing ? null : _syncNow,
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_syncing ? 'SYNCING...' : 'SYNC NOW'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSizes.sectionHeader,
                        fontWeight: FontWeight.w600,
                        color: _lastSyncOk == false
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
