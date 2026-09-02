import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version}';
});

String _todayLabel() {
  final now = DateTime.now();
  const viDays = [
    '',
    'Th\u1ee9 Hai',
    'Th\u1ee9 Ba',
    'Th\u1ee9 T\u01b0',
    'Th\u1ee9 N\u0103m',
    'Th\u1ee9 S\u00e1u',
    'Th\u1ee9 B\u1ea3y',
    'Ch\u1ee7 Nh\u1eadt',
  ];
  final dayName = viDays[now.weekday];
  return '$dayName, ${DateFormat("dd/MM/yyyy").format(now)}';
}

class DesktopShellPage extends ConsumerWidget {
  const DesktopShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSection = ref.watch(desktopSectionProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1100;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.background, AppColors.backgroundSoft],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppDimens.shellPadding),
                child: isCompact
                    ? _CompactDesktopLayout(selectedSection: selectedSection)
                    : Row(
                        children: [
                          _DesktopSidebar(selectedSection: selectedSection),
                          const SizedBox(width: AppDimens.shellGap),
                          Expanded(
                            child: _DesktopMainArea(
                              selectedSection: selectedSection,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactDesktopLayout extends StatelessWidget {
  const _CompactDesktopLayout({required this.selectedSection});

  final DesktopSection selectedSection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CompactNavigationRail(selectedSection: selectedSection),
        const SizedBox(width: AppDimens.shellGap),
        Expanded(
          child: _DesktopMainArea(
            selectedSection: selectedSection,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _CompactNavigationRail extends ConsumerWidget {
  const _CompactNavigationRail({required this.selectedSection});

  final DesktopSection selectedSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: AppDimens.sidebarCollapsedWidth,
      padding: const EdgeInsets.symmetric(vertical: AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.shellGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.luxuryShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.espresso,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Icon(Icons.content_cut_rounded, color: AppColors.copper),
          ),
          const SizedBox(height: AppDimens.sectionGap),
          Expanded(
            child: ListView.builder(
              primary: false,
              itemCount: desktopNavigationItems.length,
              itemBuilder: (context, index) {
                final item = desktopNavigationItems[index];
                final isSelected = item.section == selectedSection;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Tooltip(
                    message: item.section.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        ref.read(desktopSectionProvider.notifier).state =
                            item.section;
                      },
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.selectedSurface
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.borderStrong
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          item.section.icon,
                          size: 19,
                          color: isSelected
                              ? AppColors.copper
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends ConsumerWidget {
  const _DesktopSidebar({required this.selectedSection});

  final DesktopSection selectedSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: AppDimens.sidebarWidth,
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.shellGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.luxuryShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandBlock(),
          const SizedBox(height: AppDimens.sectionGap),
          Expanded(
            child: ListView(
              primary: false,
              children: desktopNavigationItems
                  .map(
                    (item) => _SidebarItem(
                      icon: item.section.icon,
                      label: item.section.label,
                      selected: item.section == selectedSection,
                      onTap: () {
                        ref.read(desktopSectionProvider.notifier).state =
                            item.section;
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Consumer(
            builder: (context, ref, _) {
              final ver = ref.watch(_appVersionProvider);
              return Text(
                ver.when(
                  data: (v) => v,
                  loading: () => '',
                  error: (error, stackTrace) => 'v?',
                ),
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: AppColors.espresso,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderStrong),
            boxShadow: AppColors.luxuryShadow,
          ),
          child: Icon(Icons.content_cut_rounded, color: AppColors.copper),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản Lý Salon Tóc',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Hệ thống quản lý nội bộ',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected ? AppColors.sidebarSelectionGradient : null,
              color: selected ? null : Colors.transparent,
              border: Border.all(
                color: selected
                    ? AppColors.borderStrong.withValues(alpha: 0.75)
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? AppColors.copperSoft
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? AppColors.espresso
                            : AppColors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMainArea extends ConsumerStatefulWidget {
  const _DesktopMainArea({required this.selectedSection, this.compact = false});

  final DesktopSection selectedSection;
  final bool compact;

  @override
  ConsumerState<_DesktopMainArea> createState() => _DesktopMainAreaState();
}

class _DesktopMainAreaState extends ConsumerState<_DesktopMainArea> {
  Timer? _refreshTimer;
  DesktopSection _previousSection = DesktopSection.overview;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.invalidate(overviewSummaryProvider);
      ref.invalidate(appointmentsViewProvider);
      ref.invalidate(customersViewProvider);
      ref.invalidate(reportsSummaryProvider);
      ref.invalidate(invoiceDraftProvider);
      ref.invalidate(invoiceHistoryProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Intercept employees section tap → open as floating window instead
    ref.listen<DesktopSection>(desktopSectionProvider, (prev, next) {
      if (next == DesktopSection.employees) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(desktopSectionProvider.notifier).state = _previousSection;
          _openEmployeesWindow();
        });
      } else {
        _previousSection = next;
      }
    });

    ref.listen<OfflineUpdateSummary?>(offlineUpdateLastResultProvider, (
      previous,
      next,
    ) {
      if (!mounted ||
          next == null ||
          !next.hasUpdate ||
          next.manifest == null) {
        return;
      }

      final previousVersion = previous?.manifest?.latestVersion;
      final nextVersion = next.manifest!.latestVersion;
      if (previousVersion == nextVersion) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Có bản cập nhật mới $nextVersion. Mở Cài đặt để tải và cài đặt.',
          ),
        ),
      );
    });

    final latestUpdate = ref.watch(offlineUpdateLastResultProvider);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.compact ? 84 : AppDimens.topBarHeight,
          child: _TopBar(
            selectedSection: widget.selectedSection,
            updateSummary: latestUpdate,
            onOpenStaffWorkstation: _openStaffWorkstation,
            compact: widget.compact,
          ),
        ),
        const SizedBox(height: AppDimens.shellGap),
        Expanded(child: _buildSectionPage(widget.selectedSection)),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 0 : AppDimens.shellGap,
        0,
        widget.compact ? 0 : AppDimens.shellGap,
        0,
      ),
      child: content,
    );
  }

  Future<void> _openEmployeesWindow() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _EmployeesWindowDialog(),
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
      await Process.start(Platform.resolvedExecutable, [
        '--staff-window',
      ], mode: ProcessStartMode.detached);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã mở cửa sổ Bàn nhân viên riêng.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không mở được cửa sổ staff riêng: $error')),
      );
    }
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

  Widget _buildSectionPage(DesktopSection section) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: _buildSectionBody(section),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.selectedSection,
    required this.onOpenStaffWorkstation,
    this.updateSummary,
    this.compact = false,
  });

  final DesktopSection selectedSection;
  final VoidCallback onOpenStaffWorkstation;
  final OfflineUpdateSummary? updateSummary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = compact || constraints.maxWidth < 1120;

        final searchField = Container(
          decoration: BoxDecoration(
            color: AppColors.fieldShell,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.luxuryShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
              hintText: 'Tìm khách hàng, lịch hẹn, dịch vụ...',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  widthFactor: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.shortcutFill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Ctrl K',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.copperSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        );

        if (isCompact) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.topBarAccent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.luxuryShadow,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeaderPill(
                    icon: selectedSection.icon,
                    label: selectedSection.label,
                    emphasized: true,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onOpenStaffWorkstation,
                  icon: const Icon(Icons.storefront_outlined),
                  tooltip: 'Bàn nhân viên',
                ),
              ],
            ),
          );
        }

        final actions = Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            if (updateSummary?.hasUpdate == true &&
                updateSummary?.manifest != null)
              _HeaderPill(
                icon: Icons.system_update_alt_outlined,
                label: 'Có bản ${updateSummary!.manifest!.latestVersion}',
              ),
            FilledButton.icon(
              onPressed: onOpenStaffWorkstation,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Bàn nhân viên'),
            ),
            _HeaderPill(
              icon: selectedSection.icon,
              label: selectedSection.label,
              emphasized: true,
            ),
            _HeaderPill(icon: Icons.today_outlined, label: _todayLabel()),
            const _HeaderPill(icon: Icons.person_outline, label: 'Chủ salon'),
          ],
        );

        final content = Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            actions,
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.topBarAccent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.luxuryShadow,
          ),
          child: content,
        );
      },
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: emphasized ? AppColors.topBarPillActive : AppColors.topBarPill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: emphasized ? AppColors.borderStrong : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: emphasized
                  ? AppColors.topBarPillActiveText
                  : AppColors.copperSoft,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: emphasized
                      ? AppColors.topBarPillActiveText
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Employee Management floating window (full-screen dialog)
// ---------------------------------------------------------------------------
class _EmployeesWindowDialog extends StatelessWidget {
  const _EmployeesWindowDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.background, AppColors.backgroundSoft],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.topBarAccent,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 20,
                      color: AppColors.copperSoft,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Quản lý nhân viên',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: 'Đóng cửa sổ',
                    ),
                  ],
                ),
              ),
              const Expanded(child: EmployeesPage()),
            ],
          ),
        ),
      ),
    );
  }
}
