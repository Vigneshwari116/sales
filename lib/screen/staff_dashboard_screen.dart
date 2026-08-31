import 'package:flutter/material.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/sales_abstract_screen.dart';
import 'package:sales/screen/sales_bill_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/screen/staff_thermal_printer_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';

enum _StaffSection {
  bill,
  abstract,
  ledger,
  printer,
  sync,
}

/// Staff shell with icon-only [NavigationRail] on wide layouts.
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
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _navSurface = Color(0xFFE8F5E8);
  static const double _railBreakpoint = 700;

  _StaffSection _selectedSection = _StaffSection.bill;

  String get _location => AppConfig.displayLocationName;

  int get _selectedIndex => _selectedSection.index;

  void _selectSection(_StaffSection section) {
    setState(() => _selectedSection = section);
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

  Widget _sectionLabel(_StaffSection section) {
    switch (section) {
      case _StaffSection.bill:
        return const Text('BILL');
      case _StaffSection.abstract:
        return const Text('ABSTRACT');
      case _StaffSection.ledger:
        return const Text('LEDGER');
      case _StaffSection.printer:
        return const Text('PRINTER');
      case _StaffSection.sync:
        return const Text('SYNC');
    }
  }

  IconData _sectionIcon(_StaffSection section) {
    switch (section) {
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

  Widget _buildNavigationList({VoidCallback? onNavigate}) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: _navSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Sales',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _location,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        for (final section in _StaffSection.values)
          ListTile(
            key: Key('staff_nav_${section.name}'),
            leading: Icon(_sectionIcon(section)),
            title: _sectionLabel(section),
            selected: _selectedSection == section,
            onTap: () {
              onNavigate?.call();
              _selectSection(section);
            },
          ),
        const Divider(),
        ListTile(
          key: const Key('staff_nav_logout'),
          leading: const Icon(Icons.logout),
          title: const Text('LOGOUT'),
          onTap: () {
            onNavigate?.call();
            _logout();
          },
        ),
      ],
    );
  }

  Widget _buildSectionBody() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        SalesBillScreen(
          embeddedInDashboard: true,
          ledgerScreenBuilder: widget.ledgerScreenBuilder,
        ),
        SalesAbstractScreen(location: _location),
        widget.ledgerScreenBuilder?.call(_location) ??
            SalesLedgerScreen(
              location: _location,
              embeddedInDashboard: true,
            ),
        const StaffThermalPrinterScreen(),
        _StaffSyncPanel(location: _location),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width > _railBreakpoint;

    if (useRail) {
      return Scaffold(
        backgroundColor: _background,
        body: Row(
          children: [
            NavigationRail(
              key: const Key('staff_navigation_rail'),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                _selectSection(_StaffSection.values[index]);
              },
              labelType: width > 900
                  ? NavigationRailLabelType.all
                  : NavigationRailLabelType.selected,
              backgroundColor: _navSurface,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  children: [
                    const Icon(Icons.storefront, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      _location,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      key: const Key('staff_rail_logout'),
                      tooltip: 'Logout',
                      icon: const Icon(Icons.logout),
                      onPressed: _logout,
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final section in _StaffSection.values)
                  NavigationRailDestination(
                    icon: Icon(_sectionIcon(section)),
                    label: _sectionLabel(section),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: _buildSectionBody()),
          ],
        ),
      );
    }

    return Scaffold(
      key: const Key('staff_dashboard_drawer_shell'),
      backgroundColor: _background,
      drawer: Drawer(
        backgroundColor: _background,
        child: _buildNavigationList(),
      ),
      appBar: AppBar(
        title: _sectionLabel(_selectedSection),
        backgroundColor: _navSurface,
        foregroundColor: Colors.black,
      ),
      body: _buildSectionBody(),
    );
  }
}

class _StaffSyncPanel extends StatefulWidget {
  final String location;

  const _StaffSyncPanel({required this.location});

  @override
  State<_StaffSyncPanel> createState() => _StaffSyncPanelState();
}

class _StaffSyncPanelState extends State<_StaffSyncPanel> {
  static const Color _background = Color(0xFFC5F6C5);

  bool _syncing = false;
  String? _message;

  Future<void> _syncNow() async {
    final allowed = await SyncGateService.confirmSync(context);
    if (!allowed || !mounted) return;

    setState(() {
      _syncing = true;
      _message = null;
    });

    final result = await SyncService.instance.manualSync(widget.location);

    if (!mounted) return;

    setState(() {
      _syncing = false;
      _message = result.summaryMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SYNC',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFE8F5E8),
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
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
                  Text(
                    'Push pending bills and pull admin updates for ${widget.location}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
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
                        backgroundColor: const Color(0xFF9C1C1C),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
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
