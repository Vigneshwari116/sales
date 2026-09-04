import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sales/config/location_codes.dart';
import 'package:sales/screen/admin_cross_abstract_screen.dart';
import 'package:sales/screen/admin_location_grid_screen.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/sales_ledger_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/csv_import_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/services/sync_gate_service.dart';
import 'package:sales/services/sync_service.dart';
import 'package:sales/config/app_config.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/collapsible_sidebar.dart';
import 'package:sales/widgets/compact_layout.dart';

enum _AdminSection {
  dashboard,
  abstract,
  ledger,
  sync,
}

/// Admin shell with collapsible navy sidebar (icon-only or icon + label row).
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
  _AdminSection _selectedSection = _AdminSection.dashboard;
  String _ledgerLocation = displayNameForLocationCode('win1');
  bool _sidebarExpanded = false;
  int _refreshGeneration = 0;

  int get _selectedIndex => _selectedSection.index;

  void _selectSection(_AdminSection section) {
    setState(() {
      _selectedSection = section;
      if (section == _AdminSection.ledger ||
          section == _AdminSection.dashboard) {
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
        return AdminLocationGridScreen(
          key: ValueKey('admin_grid_$_refreshGeneration'),
          refreshGeneration: _refreshGeneration,
        );
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
                        child: Text(branchLabelForLocationCode(code)),
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
        return _AdminSyncPanel(
          onSyncComplete: () => setState(() => _refreshGeneration++),
        );
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
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          CollapsibleSidebar(
            key: const Key('admin_collapsible_sidebar'),
            expanded: _sidebarExpanded,
            onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            header: _sidebarExpanded
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: AppTextSizes.appBarTitle,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'All locations',
                          style: TextStyle(
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
                key: const Key('admin_nav_logout'),
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

class _AdminSyncPanel extends StatefulWidget {
  final VoidCallback? onSyncComplete;

  const _AdminSyncPanel({this.onSyncComplete});

  @override
  State<_AdminSyncPanel> createState() => _AdminSyncPanelState();
}

class _AdminSyncPanelState extends State<_AdminSyncPanel> {
  String _selectedLocationCode = 'win1';
  bool _syncing = false;
  bool _importing = false;
  String? _message;
  bool? _lastSyncOk;

  bool get _busy => _syncing || _importing;

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

    if (result.ok) {
      widget.onSyncComplete?.call();
    }
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: false,
    );

    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }

    final filePath = picked.files.single.path;
    if (filePath == null || filePath.isEmpty) {
      setState(() {
        _message = 'Could not read the selected CSV file';
        _lastSyncOk = false;
      });
      return;
    }

    setState(() {
      _importing = true;
      _message = null;
      _lastSyncOk = null;
    });

    final result = await CsvImportService.importFile(
      locationCode: _selectedLocationCode,
      filePath: filePath,
    );

    if (!mounted) return;

    setState(() {
      _importing = false;
      _lastSyncOk = result.ok;
      if (result.ok) {
        final skippedSuffix = result.skippedCount > 0
            ? ' (${result.skippedCount} row(s) skipped)'
            : '';
        _message =
            'Imported ${result.importedCount} bill(s) for ${branchLabelForLocationCode(_selectedLocationCode)}$skippedSuffix';
      } else {
        _message = result.error ?? 'CSV import failed';
      }
    });

    if (result.ok) {
      widget.onSyncComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: sectionHeaderAppBar('SYNC'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedLocationCode,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: allLocationCodes
                        .map(
                          (code) => DropdownMenuItem(
                            value: code,
                            child: Text(branchLabelForLocationCode(code)),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _selectedLocationCode = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('admin_sync_now_button'),
                    onPressed: _busy ? null : _syncLocation,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(_syncing ? 'SYNCING...' : 'SYNC LOCATION'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('admin_import_csv_button'),
                    onPressed: _busy ? null : _importCsv,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_importing ? 'IMPORTING...' : 'IMPORT CSV'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import a location sales report CSV, then use DATE RANGE in Abstract or Ledger to view the uploaded bills.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTextSizes.listSubtitle,
                      color: Colors.grey.shade700,
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
