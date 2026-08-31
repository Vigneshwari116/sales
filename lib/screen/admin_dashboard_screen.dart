import 'package:flutter/material.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/screen/admin_cross_abstract_screen.dart';
import 'package:sales/screen/admin_location_grid_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/api/sales_api.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/services/gst_config_service.dart';

enum _AdminSection {
  dashboard,
  abstract,
  ledger,
  sync,
}

/// Admin shell with [NavigationRail] on wide layouts and a drawer on narrow.
class AdminDashboardScreen extends StatefulWidget {
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
  static const Color _navSurface = Color(0xFFE8F5E8);
  static const double _railBreakpoint = 700;

  _AdminSection _selectedSection = _AdminSection.dashboard;
  String _ledgerLocation = displayNameForLocationCode('win1');

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
      case _AdminSection.dashboard:
        return const Text('DASHBOARD');
      case _AdminSection.abstract:
        return const Text('ABSTRACT');
      case _AdminSection.ledger:
        return const Text('LEDGER');
      case _AdminSection.sync:
        return const Text('SYNC');
    }
  }

  IconData _sectionIcon(_AdminSection section) {
    switch (section) {
      case _AdminSection.dashboard:
        return Icons.dashboard_outlined;
      case _AdminSection.abstract:
        return Icons.summarize_outlined;
      case _AdminSection.ledger:
        return Icons.menu_book_outlined;
      case _AdminSection.sync:
        return Icons.cloud_upload_outlined;
    }
  }

  Widget _buildNavigationList({VoidCallback? onNavigate}) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const DrawerHeader(
          decoration: BoxDecoration(color: _navSurface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Admin',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'All locations',
                style: TextStyle(fontSize: 13),
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
    switch (_selectedSection) {
      case _AdminSection.dashboard:
        return const AdminLocationGridScreen();
      case _AdminSection.abstract:
        return const AdminCrossAbstractScreen();
      case _AdminSection.ledger:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _ledgerLocation,
                decoration: const InputDecoration(
                  labelText: 'Ledger location',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: allLocationCodes
                    .map(
                      (code) => DropdownMenuItem(
                        value: displayNameForLocationCode(code),
                        child: Text(displayNameForLocationCode(code)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _ledgerLocation = value);
                },
              ),
            ),
            Expanded(
              child: widget.ledgerScreenBuilder?.call(_ledgerLocation) ??
                  SalesLedgerScreen(
                    location: _ledgerLocation,
                    embeddedInDashboard: true,
                    readOnly: true,
                  ),
            ),
          ],
        );
      case _AdminSection.sync:
        return const _AdminSyncPanel();
    }
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
              backgroundColor: _navSurface,
              leading: const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Column(
                  children: [
                    Icon(Icons.admin_panel_settings, size: 28),
                    SizedBox(height: 4),
                    Text(
                      'Admin',
                      style: TextStyle(
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

class _AdminSyncPanel extends StatefulWidget {
  const _AdminSyncPanel();

  @override
  State<_AdminSyncPanel> createState() => _AdminSyncPanelState();
}

class _AdminSyncPanelState extends State<_AdminSyncPanel> {
  static const Color _background = Color(0xFFC5F6C5);

  final _cgstCtrl = TextEditingController(
    text: GstConfigService.defaultCgstPct.toString(),
  );
  final _sgstCtrl = TextEditingController(
    text: GstConfigService.defaultSgstPct.toString(),
  );

  String _selectedLocationCode = 'win1';
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _cgstCtrl.dispose();
    _sgstCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveGstConfig() async {
    final cgst = double.tryParse(_cgstCtrl.text.trim());
    final sgst = double.tryParse(_sgstCtrl.text.trim());

    if (cgst == null || sgst == null) {
      setState(() => _message = 'Enter valid GST percentages');
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    final result = await SalesApi.updateGstConfig(
      locationCode: _selectedLocationCode,
      cgstPct: cgst,
      sgstPct: sgst,
    );

    if (!mounted) return;

    setState(() {
      _saving = false;
      _message = result.ok
          ? 'GST config saved — staff will receive on next sync'
          : (result.error ?? 'Could not save GST config');
    });
  }

  Future<void> _syncLocation() async {
    final allowed = await SyncGateService.confirmSync(context);
    if (!allowed || !mounted) return;

    setState(() {
      _saving = true;
      _message = null;
    });

    final location = displayNameForLocationCode(_selectedLocationCode);
    final result = await SyncService.instance.manualSync(location);

    if (!mounted) return;

    setState(() {
      _saving = false;
      _message = result.summaryMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SYNC & GST CONFIG',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFFE8F5E8),
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedLocationCode,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                    items: allLocationCodes
                        .map(
                          (code) => DropdownMenuItem(
                            value: code,
                            child: Text(displayNameForLocationCode(code)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedLocationCode = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cgstCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CGST %',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sgstCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SGST %',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saving ? null : _saveGstConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C1C1C),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_saving ? 'SAVING...' : 'SAVE GST CONFIG'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('admin_sync_now_button'),
                    onPressed: _saving ? null : _syncLocation,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('SYNC LOCATION'),
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
