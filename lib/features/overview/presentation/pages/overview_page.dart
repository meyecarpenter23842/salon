import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewSummaryProvider);
    final appointments = ref.watch(appointmentsViewProvider);

    void openSection(DesktopSection section) {
      ref.read(desktopSectionProvider.notifier).state = section;
    }

    return overview.when(
      data: (summary) => appointments.when(
        data: (appointmentRows) => _OverviewLoaded(
          summary: summary,
          appointments: appointmentRows,
          onOpenAppointments: () => openSection(DesktopSection.appointments),
          onOpenCustomers: () => openSection(DesktopSection.customers),
          onOpenReports: () => openSection(DesktopSection.reports),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Không tải được lịch hôm nay: $error'),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text('Không tải được tổng quan: $error'),
      ),
    );
  }
}

class _OverviewLoaded extends StatelessWidget {
  const _OverviewLoaded({
    required this.summary,
    required this.appointments,
    required this.onOpenAppointments,
    required this.onOpenCustomers,
    required this.onOpenReports,
  });

  final Map<String, Object?> summary;
  final List<AppointmentEntry> appointments;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    final kpis = _mapList(summary['kpis']);
    final featuredCustomers = _mapList(summary['featuredCustomers']);
    final revenueSeries = _mapList(summary['revenueSeries']);

    final waitingAppointments = appointments
        .where((item) => item.status == 'Chờ xác nhận')
        .length;
    final activeAppointments = appointments
        .where((item) => item.status == 'Đang làm')
        .length;
    final bookedAppointments = appointments
        .where((item) => item.status == 'Đã đặt')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < 980;

        return ListView(
          primary: false,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _KpiGrid(
              kpis: kpis,
              onOpenAppointments: onOpenAppointments,
              onOpenReports: onOpenReports,
            ),
            const SizedBox(height: 16),
            if (singleColumn) ...[
              _AppointmentsPanel(
                rows: appointments,
                onOpen: onOpenAppointments,
              ),
              const SizedBox(height: 16),
              _AttentionPanel(
                waitingAppointments: waitingAppointments,
                activeAppointments: activeAppointments,
                bookedAppointments: bookedAppointments,
                onOpenAppointments: onOpenAppointments,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _AppointmentsPanel(
                      rows: appointments,
                      onOpen: onOpenAppointments,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 360,
                    child: _AttentionPanel(
                      waitingAppointments: waitingAppointments,
                      activeAppointments: activeAppointments,
                      bookedAppointments: bookedAppointments,
                      onOpenAppointments: onOpenAppointments,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            if (singleColumn) ...[
              _FeaturedCustomersPanel(
                customers: featuredCustomers,
                onOpen: onOpenCustomers,
              ),
              const SizedBox(height: 16),
              _RevenuePanel(points: revenueSeries, onOpen: onOpenReports),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FeaturedCustomersPanel(
                      customers: featuredCustomers,
                      onOpen: onOpenCustomers,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _RevenuePanel(
                      points: revenueSeries,
                      onOpen: onOpenReports,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.kpis,
    required this.onOpenAppointments,
    required this.onOpenReports,
  });

  final List<Map<String, Object?>> kpis;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenReports;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.groups_2_outlined,
      Icons.check_circle_outline,
      Icons.payments_outlined,
      Icons.schedule_outlined,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const gap = 12.0;
        final cardWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < kpis.length; index++)
              SizedBox(
                width: cardWidth,
                child: _MetricCard(
                  title: kpis[index]['title'].toString(),
                  value: kpis[index]['value'].toString(),
                  note: kpis[index]['note'].toString(),
                  icon: icons[index.clamp(0, icons.length - 1)],
                  onTap: index == 2 ? onOpenReports : onOpenAppointments,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.shellAccentSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icon, size: 18, color: AppColors.copper),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentsPanel extends StatelessWidget {
  const _AppointmentsPanel({required this.rows, required this.onOpen});

  final List<AppointmentEntry> rows;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.take(6).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              title: 'Lịch hôm nay',
              actionLabel: 'Mở lịch hẹn',
              actionKey: const Key('overview-open-appointments'),
              onAction: onOpen,
            ),
            const SizedBox(height: 10),
            if (visibleRows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Center(
                  child: Text(
                    'Chưa có lịch hẹn hôm nay.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              )
            else
              for (var index = 0; index < visibleRows.length; index++) ...[
                _AppointmentRow(row: visibleRows[index], onTap: onOpen),
                if (index < visibleRows.length - 1)
                  Divider(height: 1, color: AppColors.border),
              ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.row, required this.onTap});

  final AppointmentEntry row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showService = constraints.maxWidth >= 620;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      row.timeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showService) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.servicesSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  AppStatusBadge(label: row.status),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({
    required this.waitingAppointments,
    required this.activeAppointments,
    required this.bookedAppointments,
    required this.onOpenAppointments,
  });

  final int waitingAppointments;
  final int activeAppointments;
  final int bookedAppointments;
  final VoidCallback onOpenAppointments;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              title: 'Cần xử lý',
              actionLabel: 'Xem lịch',
              onAction: onOpenAppointments,
            ),
            const SizedBox(height: 12),
            _AttentionRow(
              label: 'Chờ xác nhận',
              value: '$waitingAppointments',
              onTap: onOpenAppointments,
            ),
            _AttentionRow(
              label: 'Đang phục vụ',
              value: '$activeAppointments',
              onTap: onOpenAppointments,
            ),
            _AttentionRow(
              label: 'Đã đặt còn lại',
              value: '$bookedAppointments',
              onTap: onOpenAppointments,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedCustomersPanel extends StatelessWidget {
  const _FeaturedCustomersPanel({
    required this.customers,
    required this.onOpen,
  });

  final List<Map<String, Object?>> customers;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final visibleCustomers = customers.take(3).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              title: 'Khách hàng cần nhớ',
              actionLabel: 'Mở khách hàng',
              actionKey: const Key('overview-open-customers'),
              onAction: onOpen,
            ),
            const SizedBox(height: 10),
            if (visibleCustomers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Chưa có khách hàng nổi bật.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              )
            else
              for (var index = 0; index < visibleCustomers.length; index++) ...[
                _CustomerRow(customer: visibleCustomers[index], onTap: onOpen),
                if (index < visibleCustomers.length - 1)
                  Divider(height: 1, color: AppColors.border),
              ],
          ],
        ),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer, required this.onTap});

  final Map<String, Object?> customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.shellAccentSurface,
                foregroundColor: AppColors.textPrimary,
                child: Text(
                  customer['initials'].toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      customer['service'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(label: customer['tier'].toString()),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({required this.points, required this.onOpen});

  final List<Map<String, Object?>> points;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              title: 'Doanh thu 7 ngày',
              actionLabel: 'Mở báo cáo',
              actionKey: const Key('overview-open-reports'),
              onAction: onOpen,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final point in points)
                  _RevenuePoint(
                    label: point['label'].toString(),
                    value: (point['value'] as num?)?.toDouble() ?? 0,
                    onTap: onOpen,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenuePoint extends StatelessWidget {
  const _RevenuePoint({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final double value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panelRaised,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 88),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 4),
              Text(
                _compactCurrency(value),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          key: actionKey,
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

List<Map<String, Object?>> _mapList(Object? source) {
  if (source is List) {
    return source
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }
  return const [];
}

String _compactCurrency(double value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
  }
  return value.toStringAsFixed(0);
}
