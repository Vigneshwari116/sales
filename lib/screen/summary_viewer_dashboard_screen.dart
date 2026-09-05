import 'package:flutter/material.dart';
import 'package:sales/screen/login_screen.dart';
import 'package:sales/screen/summary_abstract_screen.dart';
import 'package:sales/screen/summary_dashboard_screen.dart';
import 'package:sales/services/app_session_service.dart';
import 'package:sales/services/session_service.dart';
import 'package:sales/theme/app_theme.dart';
import 'package:sales/widgets/collapsible_sidebar.dart';

enum _SummarySection {
  dashboard,
  abstract,
}

/// Lightweight shell for RKSM login — dashboard and abstract only.
class SummaryViewerDashboardScreen extends StatefulWidget {
  const SummaryViewerDashboardScreen({super.key});

  @override
  State<SummaryViewerDashboardScreen> createState() =>
      _SummaryViewerDashboardScreenState();
}

class _SummaryViewerDashboardScreenState
    extends State<SummaryViewerDashboardScreen> {
  _SummarySection _selectedSection = _SummarySection.dashboard;
  bool _sidebarExpanded = false;
  int _refreshGeneration = 0;

  Future<void> _logout() async {
    await AppSessionService.onLogout();
    await SessionService.clearLogin();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _buildSectionBody() {
    switch (_selectedSection) {
      case _SummarySection.dashboard:
        return SummaryDashboardScreen(refreshGeneration: _refreshGeneration);
      case _SummarySection.abstract:
        return SummaryAbstractScreen(refreshGeneration: _refreshGeneration);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('summary_viewer_dashboard_shell'),
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          CollapsibleSidebar(
            expanded: _sidebarExpanded,
            onToggle: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
            header: _sidebarExpanded
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RKSM',
                          style: TextStyle(
                            fontSize: AppTextSizes.appBarTitle,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Sales summary',
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
                tooltip: _sidebarExpanded ? null : 'LOGOUT',
                onPressed: _logout,
                color: Colors.white,
                icon: const Icon(Icons.logout),
              ),
            ),
            items: [
              SidebarNavItem(
                key: const Key('summary_nav_dashboard'),
                icon: Icons.dashboard_outlined,
                label: 'DASHBOARD',
                selected: _selectedSection == _SummarySection.dashboard,
                onTap: () => setState(() {
                  _selectedSection = _SummarySection.dashboard;
                  _refreshGeneration++;
                }),
              ),
              SidebarNavItem(
                key: const Key('summary_nav_abstract'),
                icon: Icons.summarize_outlined,
                label: 'ABSTRACT',
                selected: _selectedSection == _SummarySection.abstract,
                onTap: () => setState(() {
                  _selectedSection = _SummarySection.abstract;
                  _refreshGeneration++;
                }),
              ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildSectionBody()),
        ],
      ),
    );
  }
}
