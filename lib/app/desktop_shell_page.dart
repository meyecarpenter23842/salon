import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/offline_update_summary.dart';
import '../core/providers/repository_providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../features/appointments/presentation/pages/appointments_page.dart';
import '../features/customers/presentation/pages/customers_page.dart';
import '../features/employees/presentation/pages/employees_page.dart';
import '../features/invoices/presentation/pages/invoices_page.dart';
import '../features/overview/presentation/pages/overview_page.dart';
import '../features/overview/presentation/pages/staff_workstation_page.dart';
import '../features/reports/presentation/pages/reports_page.dart';
import '../features/sales/presentation/pages/sales_page.dart';
import '../features/services/presentation/pages/services_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import 'navigation/desktop_navigation.dart';

const _sidebarCollapsedPreferenceKey = 'salon_sidebar_collapsed';

final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}';
});

String _todayLabel() {
  final now = DateTime.now();
  const viDays = [
    '',
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${viDays[now.weekday]}, ${DateFormat("dd/MM/yyyy").format(now)}';
}

class DesktopShellPage extends ConsumerStatefulWidget {
  const DesktopShellPage({super.key});

  @override
  ConsumerState<DesktopShellPage> createState() => _DesktopShellPageState();
}

class _DesktopShellPageState extends ConsumerState<DesktopShellPage> {
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSidebarPreference());
  }

  Future<void> _loadSidebarPreference() async {
    final preferences = await SharedPreferences.getInstance();
    final collapsed = preferences.getBool(_sidebarCollapsedPreferenceKey);
    if (!mounted || collapsed == null) return;
    setState(() => _sidebarCollapsed = collapsed);
  }

  void _toggleSidebar() {
    final collapsed = !_sidebarCollapsed;
    setState(() => _sidebarCollapsed = collapsed);
    unawaited(_persistSidebarPreference(collapsed));
  }

  Future<void> _persistSidebarPreference(bool collapsed) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_sidebarCollapsedPreferenceKey, collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final selectedSection = ref.watch(desktopSectionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final forceCompactNavigation = constraints.maxWidth < 1080;
        final collapsed = forceCompactNavigation || _sidebarCollapsed;

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                _DesktopSidebar(
                  selectedSection: selectedSection,
                  collapsed: collapsed,
                  canToggle: !forceCompactNavigation,
                  onToggle: _toggleSidebar,
                  onOpenStaffWorkstation: _openStaffWorkstation,
                ),
                Expanded(
                  child: _DesktopWorkspace(
                    selectedSection: selectedSection,
                    onOpenStaffWorkstation: _openStaffWorkstation,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openStaffWorkstation() async {
    if (!kReleaseMode) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => const StaffWorkstationPage(),
      );
      return;
    }

    try {
      await Process.start(
        Platform.resolvedExecutable,
        const ['--staff-window'],
        mode: ProcessStartMode.detached,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã mở Bàn nhân viên riêng.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không mở được Bàn nhân viên: $error')),
      );
    }
  }
}

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({
    required this.selectedSection,
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
    required this.onOpenStaffWorkstation,
  });

  final DesktopSection selectedSection;
  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;
  final VoidCallback onOpenStaffWorkstation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = collapsed
        ? AppDimens.navigationSidebarCollapsedWidth
        : AppDimens.navigationSidebarWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      color: AppColors.navigationSidebarSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.navigationSidebarBorder),
          ),
        ),
        child: Column(
          children: [
            _SidebarBrand(
              collapsed: collapsed,
              canToggle: canToggle,
              onToggle: onToggle,
            ),
            Expanded(
              child: ListView(
                primary: false,
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 8 : 10,
                  10,
                  collapsed ? 8 : 10,
                  12,
                ),
                children: [
                  for (final group in const [
                    DesktopNavigationGroup.operations,
                    DesktopNavigationGroup.management,
                    DesktopNavigationGroup.insights,
                  ]) ...[
                    _SidebarGroupLabel(group: group, collapsed: collapsed),
                    for (final item in desktopNavigationItems.where(
                      (item) => item.group == group,
                    ))
                      _SidebarItem(
                        icon: item.section.icon,
                        label: item.section.label,
                        selected: item.section == selectedSection,
                        collapsed: collapsed,
                        onTap: () {
                          ref.read(desktopSectionProvider.notifier).state =
                              item.section;
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            _SidebarFooter(
              selectedSection: selectedSection,
              collapsed: collapsed,
              canToggle: canToggle,
              onToggle: onToggle,
              onOpenStaffWorkstation: onOpenStaffWorkstation,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
  });

  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.navigationSidebarBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          const _SalonMark(),
          if (!collapsed) ...[
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hair Spa Manager',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Salon operations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.45,
                    ),
                  ),
                ],
              ),
            ),
            if (canToggle)
              IconButton(
                onPressed: onToggle,
                tooltip: 'Thu gọn menu',
                icon: const Icon(Icons.keyboard_double_arrow_left_rounded),
                iconSize: 18,
                color: AppColors.textMuted,
              ),
          ],
        ],
      ),
    );
  }
}

class _SalonMark extends StatelessWidget {
  const _SalonMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.shellAccentSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.navigationSidebarBorder),
      ),
      child: Icon(
        Icons.content_cut_rounded,
        size: 19,
        color: AppColors.copper,
      ),
    );
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  const _SidebarGroupLabel({required this.group, required this.collapsed});

  final DesktopNavigationGroup group;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) return const SizedBox(height: 4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
      child: Text(
        group.label.toUpperCase(),
        style: TextStyle(
          color: AppColors.textMuted.withValues(alpha: 0.72),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.05,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        hoverColor: AppColors.navigationSidebarHover,
        child: Ink(
          height: AppDimens.navigationItemHeight,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.navigationSidebarActive
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: AppColors.navigationSidebarIndicator,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 19,
                      color: selected
                          ? AppColors.copper
                          : AppColors.navigationSidebarText,
                    ),
                    if (!collapsed) ...[
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppColors.navigationSidebarTextActive
                                : AppColors.navigationSidebarText,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: collapsed ? Tooltip(message: label, child: content) : content,
    );
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter({
    required this.selectedSection,
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
    required this.onOpenStaffWorkstation,
  });

  final DesktopSection selectedSection;
  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;
  final VoidCallback onOpenStaffWorkstation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(_appVersionProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 8 : 10,
        10,
        collapsed ? 8 : 10,
        10,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.navigationSidebarBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SidebarAction(
            icon: Icons.storefront_outlined,
            label: 'Bàn nhân viên',
            collapsed: collapsed,
            onTap: onOpenStaffWorkstation,
          ),
          _SidebarItem(
            icon: DesktopSection.settings.icon,
            label: DesktopSection.settings.label,
            selected: selectedSection == DesktopSection.settings,
            collapsed: collapsed,
            onTap: () {
              ref.read(desktopSectionProvider.notifier).state =
                  DesktopSection.settings;
            },
          ),
          if (collapsed && canToggle)
            Tooltip(
              message: 'Mở rộng menu',
              child: IconButton(
                onPressed: onToggle,
                icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
                iconSize: 18,
                color: AppColors.textMuted,
              ),
            )
          else if (!collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  version.when(
                    data: (value) => value,
                    loading: () => '',
                    error: (error, stackTrace) => 'v?',
                  ),
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.72),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        hoverColor: AppColors.navigationSidebarHover,
        child: SizedBox(
          height: AppDimens.navigationItemHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(icon, size: 19, color: AppColors.navigationSidebarText),
                if (!collapsed) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.navigationSidebarText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: collapsed ? Tooltip(message: label, child: button) : button,
    );
  }
}

class _DesktopWorkspace extends ConsumerStatefulWidget {
  const _DesktopWorkspace({
    required this.selectedSection,
    required this.onOpenStaffWorkstation,
  });

  final DesktopSection selectedSection;
  final VoidCallback onOpenStaffWorkstation;

  @override
  ConsumerState<_DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends ConsumerState<_DesktopWorkspace> {
  @override
  Widget build(BuildContext context) {
    ref.listen<OfflineUpdateSummary?>(offlineUpdateLastResultProvider, (
      previous,
      next,
    ) {
      if (!mounted || next == null || !next.hasUpdate || next.manifest == null) {
        return;
      }

      final previousVersion = previous?.manifest?.latestVersion;
      final nextVersion = next.manifest!.latestVersion;
      if (previousVersion == nextVersion) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Có bản cập nhật mới $nextVersion. Mở Cài đặt để xem chi tiết.',
          ),
        ),
      );
    });

    final latestUpdate = ref.watch(offlineUpdateLastResultProvider);

    return ColoredBox(
      color: AppColors.workspaceBackground,
      child: Column(
        children: [
          SizedBox(
            height: AppDimens.workspaceTopBarHeight,
            child: _WorkspaceTopBar(
              selectedSection: widget.selectedSection,
              updateSummary: latestUpdate,
              onOpenStaffWorkstation: widget.onOpenStaffWorkstation,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.workspaceHorizontalPadding,
                AppDimens.workspaceVerticalPadding,
                AppDimens.workspaceHorizontalPadding,
                AppDimens.workspaceVerticalPadding,
              ),
              child: _buildSectionBody(widget.selectedSection),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody(DesktopSection section) {
    return switch (section) {
      DesktopSection.overview => const OverviewPage(),
      DesktopSection.appointments => const AppointmentsPage(),
      DesktopSection.customers => const CustomersPage(),
      DesktopSection.services => const ServicesPage(),
      DesktopSection.employees => const EmployeesPage(),
      DesktopSection.sales => const SalesPage(),
      DesktopSection.invoices => const InvoicesPage(),
      DesktopSection.reports => const ReportsPage(),
      DesktopSection.settings => const SettingsPage(),
    };
  }
}

class _WorkspaceTopBar extends StatelessWidget {
  const _WorkspaceTopBar({
    required this.selectedSection,
    required this.onOpenStaffWorkstation,
    this.updateSummary,
  });

  final DesktopSection selectedSection;
  final VoidCallback onOpenStaffWorkstation;
  final OfflineUpdateSummary? updateSummary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.workspaceTopBarSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.workspaceDivider),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedSection.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          selectedSection.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (updateSummary?.hasUpdate == true &&
                    updateSummary?.manifest != null) ...[
                  _TopBarStatus(
                    icon: Icons.system_update_alt_outlined,
                    label: 'Bản ${updateSummary!.manifest!.latestVersion}',
                  ),
                  const SizedBox(width: 8),
                ],
                if (!compact) ...[
                  _TopBarStatus(
                    icon: Icons.today_outlined,
                    label: _todayLabel(),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: onOpenStaffWorkstation,
                  icon: const Icon(Icons.storefront_outlined, size: 17),
                  label: compact
                      ? const Text('Nhân viên')
                      : const Text('Bàn nhân viên'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopBarStatus extends StatelessWidget {
  const _TopBarStatus({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.workspaceDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.copperSoft),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
