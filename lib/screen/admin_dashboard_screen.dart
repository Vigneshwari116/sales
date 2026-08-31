import 'package:flutter/material.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/screen/credential_settings_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/printer_settings_screen.dart';
import 'package:sales/screen/sales_abstract_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_service.dart';

enum _AdminSection {
  abstract,
  ledger,
  printers,
  sync,
  security,
}

/// Admin shell with [NavigationRail] on wide layouts and a drawer on narrow.
class AdminDashboardScreen extends StatefulWidget {
  /// When set (tests only), replaces the default [SalesLedgerScreen] body.
  @visibleForTesting
  final Widget Function(String location)? ledgerScreenBuilder;

  const AdminDashboardScreen({
    super.key,
    this.ledgerScreenBuilder,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const Color _background = Color(0xFFC5F6C5);
  static const double _railBreakpoint = 700;

  _AdminSection _selectedSection = _AdminSection.abstract;

  String get _location => AppConfig.displayLocationName;

  int get _selectedIndex => _selectedSection.index;

  void _selectSection(_AdminSection section) {
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

  Widget _sectionLabel(_AdminSection section) {
    switch (section) {
      case _AdminSection.abstract:
        return const Text('ABSTRACT');
      case _AdminSection.ledger:
        return const Text('LEDGER');
      case _AdminSection.printers:
        return const Text('PRINTERS');
      case _AdminSection.sync:
        return const Text('SYNC');
      case _AdminSection.security:
        return const Text('SECURITY');
    }
  }

  IconData _sectionIcon(_AdminSection section) {
    switch (section) {
      case _AdminSection.abstract:
        return Icons.summarize_outlined;
      case _AdminSection.ledger:
        return Icons.menu_book_outlined;
      case _AdminSection.printers:
        return Icons.print_outlined;
      case _AdminSection.sync:
        return Icons.cloud_upload_outlined;
      case _AdminSection.security:
        return Icons.security_outlined;
    }
  }

  Widget _buildNavigationList({VoidCallback? onNavigate}) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: const BoxDecoration(color: Color(0xFFD5D8D5)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text(
                'Admin',
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
        for (final section in _AdminSection.values)
          ListTile(
            key: Key('admin_nav_${section.name}'),
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
          key: const Key('admin_nav_logout'),
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
        SalesAbstractScreen(location: _location),
        widget.ledgerScreenBuilder?.call(_location) ??
            SalesLedgerScreen(location: _location),
        const PrinterSettingsScreen(),
        _AdminSyncPanel(location: _location),
        const CredentialSettingsScreen(),
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
              key: const Key('admin_navigation_rail'),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                _selectSection(_AdminSection.values[index]);
              },
              labelType: width > 900
                  ? NavigationRailLabelType.all
                  : NavigationRailLabelType.selected,
              backgroundColor: Colors.white,
              leading: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  children: [
                    const Icon(Icons.admin_panel_settings, size: 28),
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
                      key: const Key('admin_rail_logout'),
                      tooltip: 'Logout',
                      icon: const Icon(Icons.logout),
                      onPressed: _logout,
                    ),
                  ),
                ),
              ),
              destinations: [
                for (final section in _AdminSection.values)
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
      key: const Key('admin_dashboard_drawer_shell'),
      backgroundColor: _background,
      drawer: Drawer(child: _buildNavigationList()),
      appBar: AppBar(
        title: _sectionLabel(_selectedSection),
        backgroundColor: const Color(0xFFD5D8D5),
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                _location,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: _buildSectionBody(),
    );
  }
}

class _AdminSyncPanel extends StatefulWidget {
  final String location;

  const _AdminSyncPanel({required this.location});

  @override
  State<_AdminSyncPanel> createState() => _AdminSyncPanelState();
}

class _AdminSyncPanelState extends State<_AdminSyncPanel> {
  static const Color _background = Color(0xFFC5F6C5);

  bool _syncing = false;
  String? _message;

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _message = null;
    });

    final result = await SyncService.instance.manualPush(widget.location);

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
        backgroundColor: const Color(0xFFD5D8D5),
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
                    'Push pending bills for ${widget.location} to the server.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      key: const Key('admin_sync_now_button'),
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
