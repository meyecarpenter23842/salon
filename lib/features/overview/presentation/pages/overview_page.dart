import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewSummaryProvider);
    final appointments = ref.watch(appointmentsViewProvider);

    void openSection(DesktopSection section) {
      ref.read(desktopSectionProvider.notifier).state = section;
    }

    void refresh() {
      ref.invalidate(overviewSummaryProvider);
      ref.invalidate(appointmentsViewProvider);
    }

    return overview.when(
      data: (summary) => appointments.when(
        data: (rows) => _OverviewLoaded(
          summary: summary,
          appointments: rows,
          onRefresh: refresh,
          onOpenAppointments: () => openSection(DesktopSection.appointments),
          onOpenCustomers: () => openSection(DesktopSection.customers),
          onOpenEmployees: () => openSection(DesktopSection.employees),
          onOpenInvoices: () => openSection(DesktopSection.invoices),
          onOpenReports: () => openSection(DesktopSection.reports),
        ),
        loading: () => const PremiumLoadingState(
          label: 'Đang tải lịch vận hành hôm nay…',
        ),
        error: (error, _) => PremiumErrorState(
          title: 'Không tải được lịch hôm nay',
          message: '$error',
          onRetry: () => ref.invalidate(appointmentsViewProvider),
        ),
      ),
      loading: () => const PremiumLoadingState(
        label: 'Đang tải tổng quan điều hành…',
      ),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được tổng quan',
        message: '$error',
        onRetry: () => ref.invalidate(overviewSummaryProvider),
      ),
    );
  }
}

class _OverviewLoaded extends StatelessWidget {
  const _OverviewLoaded({
    required this.summary,
    required this.appointments,
    required this.onRefresh,
    required this.onOpenAppointments,
    required this.onOpenCustomers,
    required this.onOpenEmployees,
    required this.onOpenInvoices,
    required this.onOpenReports,
  });

  final Map<String, Object?> summary;
  final List<AppointmentEntry> appointments;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenEmployees;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayAppointments = appointments
        .where((item) => _sameDay(item.startsAt, now))
        .toList(growable: false)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final kpis = _mapList(summary['kpis']);
    final team = _mapList(summary['teamStatus']);
    final effectiveTeam = team.isEmpty
        ? _fallbackTeam(todayAppointments)
        : team;
    final topSales = _mapList(summary['topSales']);
    final alerts = _mapList(summary['operationalAlerts']);
    final effectiveAlerts = alerts.isEmpty
        ? _fallbackAlerts(todayAppointments, now)
        : alerts;
    final featuredCustomers = _mapList(summary['featuredCustomers']);
    final revenueSeries = _mapList(summary['revenueSeries']);
    final nextAppointment = _asMap(summary['nextAppointment']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 760 || constraints.maxWidth < 1180;
        final gap = dense ? 10.0 : 14.0;

        return Column(
          key: const Key('overview-premium-workspace'),
          children: [
            _OverviewHeader(
              nextAppointment: nextAppointment,
              dense: dense,
              onRefresh: onRefresh,
            ),
            SizedBox(height: gap),
            _KpiStrip(
              kpis: kpis,
              dense: dense,
              onOpenAppointments: onOpenAppointments,
              onOpenInvoices: onOpenInvoices,
              onOpenReports: onOpenReports,
            ),
            SizedBox(height: gap),
            Expanded(
              child: constraints.maxWidth < 980
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _TodayFlowPanel(
                            rows: todayAppointments,
                            now: now,
                            dense: dense,
                            onOpen: onOpenAppointments,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 5,
                          child: _CompactOperationsTabs(
                            team: effectiveTeam,
                            topSales: topSales,
                            alerts: effectiveAlerts,
                            featuredCustomers: featuredCustomers,
                            revenueSeries: revenueSeries,
                            onOpenAppointments: onOpenAppointments,
                            onOpenCustomers: onOpenCustomers,
                            onOpenEmployees: onOpenEmployees,
                            onOpenInvoices: onOpenInvoices,
                            onOpenReports: onOpenReports,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _TodayFlowPanel(
                            rows: todayAppointments,
                            now: now,
                            dense: dense,
                            onOpen: onOpenAppointments,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              Expanded(
                                child: _TeamPanel(
                                  rows: effectiveTeam,
                                  onOpen: onOpenEmployees,
                                ),
                              ),
                              SizedBox(height: gap),
                              Expanded(
                                child: _TopSalesPanel(
                                  rows: topSales,
                                  onOpenReports: onOpenReports,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              Expanded(
                                child: _AlertsPanel(
                                  rows: effectiveAlerts,
                                  onOpenAppointments: onOpenAppointments,
                                  onOpenInvoices: onOpenInvoices,
                                ),
                              ),
                              SizedBox(height: gap),
                              Expanded(
                                child: _InsightsPanel(
                                  featuredCustomers: featuredCustomers,
                                  revenueSeries: revenueSeries,
                                  onOpenCustomers: onOpenCustomers,
                                  onOpenReports: onOpenReports,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({
    required this.nextAppointment,
    required this.dense,
    required this.onRefresh,
  });

  final Map<String, Object?>? nextAppointment;
  final bool dense;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.now();
    final next = nextAppointment;
    final nextLabel = next == null
        ? 'Chưa có lịch tiếp theo'
        : '${next['time']} · ${next['customer']}';

    return Container(
      key: const Key('overview-premium-header'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 14 : 18,
        vertical: dense ? 10 : 13,
      ),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: dense ? 38 : 44,
            height: dense ? 38 : 44,
            decoration: BoxDecoration(
              color: AppColors.copper.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.space_dashboard_outlined,
              color: AppColors.copper,
              size: dense ? 19 : 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Điều hành hôm nay',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: dense ? 17 : 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_weekdayLabel(date.weekday)}, ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: dense ? 10.5 : 11.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.panelRaised,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: AppColors.copper),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    nextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Làm mới tổng quan',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.kpis,
    required this.dense,
    required this.onOpenAppointments,
    required this.onOpenInvoices,
    required this.onOpenReports,
  });

  final List<Map<String, Object?>> kpis;
  final bool dense;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final fallback = [
      {'title': 'Khách hôm nay', 'value': '0', 'note': 'Chưa phát sinh'},
      {'title': 'Lịch hôm nay', 'value': '0', 'note': 'Chưa phát sinh'},
      {'title': 'Doanh thu hôm nay', 'value': '0đ', 'note': 'Chưa phát sinh'},
      {'title': 'Bill đã thu', 'value': '0', 'note': 'Chưa phát sinh'},
    ];
    final items = List<Map<String, Object?>>.generate(
      4,
      (index) => index < kpis.length ? kpis[index] : fallback[index],
    );
    const icons = [
      Icons.groups_2_outlined,
      Icons.event_available_outlined,
      Icons.account_balance_wallet_outlined,
      Icons.receipt_long_outlined,
    ];
    final actions = [
      onOpenAppointments,
      onOpenAppointments,
      onOpenReports,
      onOpenInvoices,
    ];

    return SizedBox(
      height: dense ? 86 : 100,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) SizedBox(width: dense ? 9 : 12),
            Expanded(
              child: _MetricCard(
                title: items[index]['title']?.toString() ?? '',
                value: items[index]['value']?.toString() ?? '0',
                note: items[index]['note']?.toString() ?? '',
                icon: icons[index],
                dense: dense,
                onTap: actions[index],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.dense,
    required this.onTap,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      onTap: onTap,
      padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 15, vertical: 10),
      child: Row(
        children: [
          Container(
            width: dense ? 34 : 40,
            height: dense ? 34 : 40,
            decoration: BoxDecoration(
              color: AppColors.copper.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: dense ? 17 : 19, color: AppColors.copper),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: dense ? 9.5 : 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: dense ? 17 : 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayFlowPanel extends StatelessWidget {
  const _TodayFlowPanel({
    required this.rows,
    required this.now,
    required this.dense,
    required this.onOpen,
  });

  final List<AppointmentEntry> rows;
  final DateTime now;
  final bool dense;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = rows.where((item) => item.status == 'Đang làm').length;
    final waiting = rows.where((item) => item.status == 'Chờ xác nhận').length;

    return _Panel(
      key: const Key('overview-today-flow'),
      icon: Icons.view_timeline_outlined,
      title: 'Nhịp vận hành hôm nay',
      subtitle: '${rows.length} lịch · $active đang làm · $waiting chờ xác nhận',
      actionLabel: 'Mở lịch',
      actionKey: const Key('overview-open-appointments'),
      onAction: onOpen,
      child: rows.isEmpty
          ? const _PanelEmpty(
              icon: Icons.event_available_outlined,
              text: 'Chưa có lịch hẹn trong hôm nay.',
            )
          : ListView.separated(
              primary: false,
              padding: const EdgeInsets.only(top: 2),
              itemCount: rows.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: AppColors.border.withValues(alpha: 0.55),
              ),
              itemBuilder: (context, index) {
                final row = rows[index];
                final late = row.startsAt.isBefore(now) &&
                    (row.status == 'Đã đặt' || row.status == 'Chờ xác nhận');
                return InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: dense ? 8 : 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: dense ? 52 : 60,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.timeLabel,
                                style: TextStyle(
                                  color: late ? AppColors.danger : AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                row.durationLabel,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 8.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 3,
                          height: 34,
                          decoration: BoxDecoration(
                            color: late
                                ? AppColors.danger
                                : _statusTone(row.status),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${row.servicesSummary} · ${row.staffName.isEmpty ? 'Chưa phân công' : row.staffName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(label: late ? 'Quá giờ' : row.status),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({required this.rows, required this.onOpen});

  final List<Map<String, Object?>> rows;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final busy = rows.where((row) => row['state']?.toString() == 'Đang bận').length;
    final ready = rows.where((row) => row['state']?.toString() == 'Sẵn sàng').length;
    return _Panel(
      key: const Key('overview-team-status'),
      icon: Icons.groups_3_outlined,
      title: 'Nhân sự trong ca',
      subtitle: '$busy đang bận · $ready sẵn sàng',
      actionLabel: 'Nhân viên',
      onAction: onOpen,
      child: rows.isEmpty
          ? const _PanelEmpty(
              icon: Icons.badge_outlined,
              text: 'Chưa có nhân viên để hiển thị.',
            )
          : ListView.separated(
              primary: false,
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final row = rows[index];
                final tone = _teamTone(row['tone']?.toString());
                return InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.panelRaised.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 15,
                          backgroundColor: tone.withValues(alpha: 0.12),
                          foregroundColor: tone,
                          child: Text(
                            row['initials']?.toString() ?? 'NV',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['name']?.toString() ?? 'Nhân viên',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                row['detail']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 8.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        _MiniBadge(
                          text: row['state']?.toString() ?? 'Sẵn sàng',
                          tone: tone,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _TopSalesPanel extends StatelessWidget {
  const _TopSalesPanel({required this.rows, required this.onOpenReports});

  final List<Map<String, Object?>> rows;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: const Key('overview-top-sales'),
      icon: Icons.workspace_premium_outlined,
      title: 'Bán chạy hôm nay',
      subtitle: 'DV/SP theo doanh thu đã thu',
      actionLabel: 'Báo cáo',
      onAction: onOpenReports,
      child: rows.isEmpty
          ? const _PanelEmpty(
              icon: Icons.point_of_sale_outlined,
              text: 'Chưa có bill đã thanh toán hôm nay.',
            )
          : ListView.builder(
              primary: false,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final isProduct = row['type']?.toString() == 'Sản phẩm';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (isProduct ? AppColors.info : AppColors.copper)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isProduct ? AppColors.info : AppColors.copper,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${row['type']} · ${row['quantity']} lượt',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 8.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        row['revenueLabel']?.toString() ?? '0đ',
                        style: TextStyle(
                          color: AppColors.copper,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({
    required this.rows,
    required this.onOpenAppointments,
    required this.onOpenInvoices,
  });

  final List<Map<String, Object?>> rows;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenInvoices;

  @override
  Widget build(BuildContext context) {
    final urgent = rows
        .where((row) => row['severity'] == 'critical' || row['severity'] == 'warning')
        .length;
    return _Panel(
      key: const Key('overview-operational-alerts'),
      icon: Icons.notifications_active_outlined,
      title: 'Cần xử lý',
      subtitle: urgent == 0 ? 'Không có cảnh báo gấp' : '$urgent nhóm cần ưu tiên',
      child: ListView.separated(
        primary: false,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final row = rows[index];
          final severity = row['severity']?.toString() ?? 'info';
          final tone = _alertTone(severity);
          final route = row['route']?.toString();
          return InkWell(
            onTap: route == 'invoices' ? onOpenInvoices : onOpenAppointments,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: tone.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(_alertIcon(severity), size: 17, color: tone),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['title']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          row['detail']?.toString() ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 8.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((row['count'] as num?)?.toInt() != 0)
                    _MiniBadge(
                      text: '${(row['count'] as num?)?.toInt() ?? 0}',
                      tone: tone,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({
    required this.featuredCustomers,
    required this.revenueSeries,
    required this.onOpenCustomers,
    required this.onOpenReports,
  });

  final List<Map<String, Object?>> featuredCustomers;
  final List<Map<String, Object?>> revenueSeries;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: _Surface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            SizedBox(
              height: 30,
              child: TabBar(
                dividerColor: Colors.transparent,
                labelColor: AppColors.copper,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.copper,
                labelStyle: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: '7 ngày'),
                  Tab(text: 'Khách nổi bật'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TabBarView(
                children: [
                  _RevenueMiniChart(
                    rows: revenueSeries,
                    onOpen: onOpenReports,
                  ),
                  _FeaturedCustomersMini(
                    rows: featuredCustomers,
                    onOpen: onOpenCustomers,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactOperationsTabs extends StatelessWidget {
  const _CompactOperationsTabs({
    required this.team,
    required this.topSales,
    required this.alerts,
    required this.featuredCustomers,
    required this.revenueSeries,
    required this.onOpenAppointments,
    required this.onOpenCustomers,
    required this.onOpenEmployees,
    required this.onOpenInvoices,
    required this.onOpenReports,
  });

  final List<Map<String, Object?>> team;
  final List<Map<String, Object?>> topSales;
  final List<Map<String, Object?>> alerts;
  final List<Map<String, Object?>> featuredCustomers;
  final List<Map<String, Object?>> revenueSeries;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenEmployees;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: _Surface(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          children: [
            SizedBox(
              height: 32,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelColor: AppColors.copper,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.copper,
                labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                tabs: const [
                  Tab(text: 'Nhân sự'),
                  Tab(text: 'Cảnh báo'),
                  Tab(text: 'Bán chạy'),
                  Tab(text: 'Insights'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TabBarView(
                children: [
                  _TeamPanel(rows: team, onOpen: onOpenEmployees),
                  _AlertsPanel(
                    rows: alerts,
                    onOpenAppointments: onOpenAppointments,
                    onOpenInvoices: onOpenInvoices,
                  ),
                  _TopSalesPanel(rows: topSales, onOpenReports: onOpenReports),
                  _InsightsPanel(
                    featuredCustomers: featuredCustomers,
                    revenueSeries: revenueSeries,
                    onOpenCustomers: onOpenCustomers,
                    onOpenReports: onOpenReports,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueMiniChart extends StatelessWidget {
  const _RevenueMiniChart({required this.rows, required this.onOpen});

  final List<Map<String, Object?>> rows;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _PanelEmpty(
        icon: Icons.bar_chart_outlined,
        text: 'Chưa có dữ liệu doanh thu 7 ngày.',
      );
    }
    final values = rows.map((row) => _intValue(row['value'])).toList();
    final maxValue = values.fold<int>(0, (max, value) => value > max ? value : max);
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 8, 5, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var index = 0; index < rows.length; index++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxValue <= 0
                              ? 0.04
                              : (values[index] / maxValue).clamp(0.06, 1.0),
                          widthFactor: 0.54,
                          child: Container(
                            decoration: BoxDecoration(
                              color: index == rows.length - 1
                                  ? AppColors.copper
                                  : AppColors.copper.withValues(alpha: 0.38),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rows[index]['label']?.toString() ?? '',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 8),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedCustomersMini extends StatelessWidget {
  const _FeaturedCustomersMini({required this.rows, required this.onOpen});

  final List<Map<String, Object?>> rows;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _PanelEmpty(
        icon: Icons.person_search_outlined,
        text: 'Chưa có dữ liệu khách nổi bật.',
      );
    }
    return ListView.builder(
      primary: false,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.copper.withValues(alpha: 0.12),
                  foregroundColor: AppColors.copper,
                  child: Text(
                    row['initials']?.toString() ?? 'K',
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        row['spendLabel']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.copper),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 8.5),
                      ),
                  ],
                ),
              ),
              if (onAction != null && actionLabel != null)
                TextButton(
                  key: actionKey,
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                  ),
                  child: Text(actionLabel!, style: const TextStyle(fontSize: 9)),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
    if (onTap == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: container,
      ),
    );
  }
}

class _PanelEmpty extends StatelessWidget {
  const _PanelEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: AppColors.textMuted),
          const SizedBox(height: 7),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = label == 'Quá giờ' ? AppColors.danger : _statusTone(label);
    return _MiniBadge(text: label, tone: tone);
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: tone, fontSize: 8.2, fontWeight: FontWeight.w800),
      ),
    );
  }
}

List<Map<String, Object?>> _fallbackTeam(List<AppointmentEntry> appointments) {
  final byStaff = <String, AppointmentEntry>{};
  for (final appointment in appointments) {
    final staff = appointment.staffName.trim();
    if (staff.isEmpty) continue;
    final current = byStaff[staff];
    if (current == null || appointment.status == 'Đang làm') {
      byStaff[staff] = appointment;
    }
  }
  return byStaff.entries
      .map(
        (entry) => {
          'name': entry.key,
          'initials': _initials(entry.key),
          'state': entry.value.status == 'Đang làm' ? 'Đang bận' : 'Có lịch',
          'detail': '${entry.value.timeLabel} · ${entry.value.customerName}',
          'tone': entry.value.status == 'Đang làm' ? 'warning' : 'success',
        },
      )
      .toList(growable: false);
}

List<Map<String, Object?>> _fallbackAlerts(
  List<AppointmentEntry> appointments,
  DateTime now,
) {
  final overdue = appointments
      .where(
        (item) => item.startsAt.isBefore(now) &&
            (item.status == 'Đã đặt' || item.status == 'Chờ xác nhận'),
      )
      .length;
  final waiting = appointments.where((item) => item.status == 'Chờ xác nhận').length;
  final rows = <Map<String, Object?>>[];
  if (overdue > 0) {
    rows.add({
      'severity': 'critical',
      'count': overdue,
      'title': 'Lịch đã quá giờ',
      'detail': 'Có lịch đã tới giờ nhưng chưa bắt đầu.',
      'route': 'appointments',
    });
  }
  if (waiting > 0) {
    rows.add({
      'severity': 'warning',
      'count': waiting,
      'title': 'Chờ xác nhận',
      'detail': 'Cần xác nhận khách trong hôm nay.',
      'route': 'appointments',
    });
  }
  if (rows.isEmpty) {
    rows.add({
      'severity': 'success',
      'count': 0,
      'title': 'Ca làm đang sạch',
      'detail': 'Chưa có việc tồn cần ưu tiên xử lý.',
      'route': 'appointments',
    });
  }
  return rows;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  return value.map((key, value) => MapEntry(key.toString(), value));
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year && left.month == right.month && left.day == right.day;
}

Color _statusTone(String status) {
  return switch (status) {
    'Đang làm' => AppColors.warning,
    'Hoàn thành' => AppColors.success,
    'Chờ xác nhận' => AppColors.info,
    _ => AppColors.copper,
  };
}

Color _teamTone(String? tone) {
  return switch (tone) {
    'warning' => AppColors.warning,
    'success' => AppColors.success,
    _ => AppColors.textMuted,
  };
}

Color _alertTone(String severity) {
  return switch (severity) {
    'critical' => AppColors.danger,
    'warning' => AppColors.warning,
    'success' => AppColors.success,
    _ => AppColors.info,
  };
}

IconData _alertIcon(String severity) {
  return switch (severity) {
    'critical' => Icons.error_outline_rounded,
    'warning' => Icons.warning_amber_rounded,
    'success' => Icons.check_circle_outline_rounded,
    _ => Icons.info_outline_rounded,
  };
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => 'Thứ Hai',
    DateTime.tuesday => 'Thứ Ba',
    DateTime.wednesday => 'Thứ Tư',
    DateTime.thursday => 'Thứ Năm',
    DateTime.friday => 'Thứ Sáu',
    DateTime.saturday => 'Thứ Bảy',
    _ => 'Chủ Nhật',
  };
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toList();
  if (parts.isEmpty) return 'NV';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
