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
import 'package:sales/widgets/collapsible_sidebar.dart';

enum _AdminSection {
  dashboard,
  abstract,
  ledger,
  sync,
}

/// Admin shell with collapsible green sidebar (icon-only or icon + label row).
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

  _AdminSection _selectedSection = _AdminSection.dashboard;
  String _ledgerLocation = displayNameForLocationCode('win1');
  bool _sidebarExpanded = true;
  int _refreshGeneration = 0;

  int get _selectedIndex => _selectedSection.index;

  void _selectSection(_AdminSection section) {
    setState(() {
      _selectedSection = section;
      if (section == _AdminSection.ledger) {
        _refreshGeneration++;
      }
    });
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

  String _sectionLabel(_AdminSection section) {
    switch (section) {
      case _AdminSection.dashboard:
        return 'DASHBOARD';
      case _AdminSection.abstract:
        return 'ABSTRACT';
      case _AdminSection.ledger:
        return 'LEDGER';
      case _AdminSection.sync:
        return 'SYNC';
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
                value: _ledgerLocation,
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
                  setState(() {
                    _ledgerLocation = value;
                    _refreshGeneration++;
                  });
                },
              ),
            ),
            Expanded(
              child: widget.ledgerScreenBuilder?.call(_ledgerLocation) ??
                  SalesLedgerScreen(
                    location: _ledgerLocation,
                    embeddedInDashboard: true,
                    readOnly: true,
                    adminFullEdit: true,
                    refreshGeneration: _refreshGeneration,
                  ),
            ),
          ],
        );
      case _AdminSection.sync:
        return const _AdminSyncPanel();
    }
  }

  List<SidebarNavItem> _navItems() {
    return [
      for (final section in _AdminSection.values)
        SidebarNavItem(
          key: Key('admin_nav_${section.name}'),
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
      key: const Key('admin_dashboard_shell'),
      backgroundColor: _background,
      body: Row(
        children: [
          CollapsibleSidebar(
            key: const Key('admin_collapsible_sidebar'),
            expanded: _sidebarExpanded,
            onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            backgroundColor: _background,
            header: _sidebarExpanded
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'All locations',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : null,
            footer: Tooltip(
              message: 'LOGOUT',
              child: IconButton(
                key: const Key('admin_nav_logout'),
                tooltip: _sidebarExpanded ? null : 'LOGOUT',
                onPressed: _logout,
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

class _AdminSyncPanel extends StatefulWidget {
  const _AdminSyncPanel();

  @override
  State<_AdminSyncPanel> createState() => _AdminSyncPanelState();
}

class _AdminSyncPanelState extends State<_AdminSyncPanel> {
  static const Color _background = Color(0xFFC5F6C5);
  static const Color _navSurface = Color(0xFFE8F5E8);

  final _cgstCtrl = TextEditingController(
    text: GstConfigService.defaultCgstPct.toString(),
  );
  final _sgstCtrl = TextEditingController(
    text: GstConfigService.defaultSgstPct.toString(),
  );

  String _selectedLocationCode = 'win1';
  bool _savingGst = false;
  bool _syncing = false;
  String? _message;
  bool? _lastSyncOk;

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
      _savingGst = true;
      _message = null;
      _lastSyncOk = null;
    });

    final result = await SalesApi.updateGstConfig(
      locationCode: _selectedLocationCode,
      cgstPct: cgst,
      sgstPct: sgst,
    );

    if (!mounted) return;

    setState(() {
      _savingGst = false;
      _message = result.ok
          ? 'GST config saved — staff will receive on next sync'
          : (result.error ?? 'Could not save GST config');
      _lastSyncOk = result.ok;
    });
  }

  Future<void> _syncLocation() async {
    final allowed = await SyncGateService.confirmSync(context);
    if (!allowed || !mounted) return;

    setState(() {
      _syncing = true;
      _message = null;
      _lastSyncOk = null;
    });

    final location = displayNameForLocationCode(_selectedLocationCode);
    final result = await SyncService.instance.manualSync(location);

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
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text(
          'SYNC & GST CONFIG',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: _navSurface,
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
                    onChanged: (_savingGst || _syncing)
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedLocationCode = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cgstCtrl,
                    enabled: !_savingGst && !_syncing,
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
                    enabled: !_savingGst && !_syncing,
                    decoration: const InputDecoration(
                      labelText: 'SGST %',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: (_savingGst || _syncing) ? null : _saveGstConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C1C1C),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_savingGst ? 'SAVING...' : 'SAVE GST CONFIG'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('admin_sync_now_button'),
                    onPressed: (_savingGst || _syncing) ? null : _syncLocation,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_syncing ? 'SYNCING...' : 'SYNC LOCATION'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _lastSyncOk == false
                            ? const Color(0xFF9C1C1C)
                            : const Color(0xFF155724),
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
