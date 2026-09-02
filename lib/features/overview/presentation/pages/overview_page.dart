import 'dart:math' as math;

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
        final compact = constraints.maxWidth < 1030;

        return ListView(
          primary: false,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            _KpiGrid(
              kpis: kpis,
              onOpenAppointments: onOpenAppointments,
              onOpenReports: onOpenReports,
            ),
            const SizedBox(height: 18),
            if (compact) ...[
              _AppointmentsPanel(rows: appointments, onOpen: onOpenAppointments),
              const SizedBox(height: 18),
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
                    flex: 7,
                    child: _AppointmentsPanel(
                      rows: appointments,
                      onOpen: onOpenAppointments,
                    ),
                  ),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 340,
                    child: _AttentionPanel(
                      waitingAppointments: waitingAppointments,
                      activeAppointments: activeAppointments,
                      bookedAppointments: bookedAppointments,
                      onOpenAppointments: onOpenAppointments,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),
            if (compact) ...[
              _FeaturedCustomersPanel(
                customers: featuredCustomers,
                onOpen: onOpenCustomers,
              ),
              const SizedBox(height: 18),
              _RevenuePanel(points: revenueSeries, onOpen: onOpenReports),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: _FeaturedCustomersPanel(
                      customers: featuredCustomers,
                      onOpen: onOpenCustomers,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 7,
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
      Icons.task_alt_rounded,
      Icons.account_balance_wallet_outlined,
      Icons.schedule_rounded,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const gap = 14.0;
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
    return _PremiumSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          _IconMedallion(icon: icon, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
        ],
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

    return _PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.calendar_today_outlined,
            title: 'Lịch hôm nay',
            actionLabel: 'Xem lịch đầy đủ',
            actionKey: const Key('overview-open-appointments'),
            onAction: onOpen,
          ),
          const SizedBox(height: 10),
          if (visibleRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text(
                  'Chưa có lịch hẹn hôm nay.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            for (var index = 0; index < visibleRows.length; index++) ...[
              _AppointmentRow(
                row: visibleRows[index],
                onTap: onOpen,
                emphasize: index == 0 && visibleRows[index].status != 'Hoàn thành',
              ),
              if (index < visibleRows.length - 1)
                Divider(height: 1, color: AppColors.workspaceDivider),
            ],
        ],
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.row,
    required this.onTap,
    required this.emphasize,
  });

  final AppointmentEntry row;
  final VoidCallback onTap;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showService = constraints.maxWidth >= 620;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: emphasize
                    ? AppColors.copper.withValues(alpha: AppColors.isLight ? 0.07 : 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.copper.withValues(alpha: emphasize ? 0.95 : 0.34),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    child: Text(
                      row.timeLabel,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  _InitialAvatar(name: row.customerName),
                  const SizedBox(width: 11),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  _StatusPill(label: row.status),
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
    return _PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.bolt_rounded,
            title: 'Cần xử lý',
            actionLabel: 'Xem tất cả',
            onAction: onOpenAppointments,
          ),
          const SizedBox(height: 12),
          _AttentionRow(
            icon: Icons.schedule_outlined,
            label: 'Chờ xác nhận',
            value: '$waitingAppointments',
            onTap: onOpenAppointments,
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            icon: Icons.content_cut_rounded,
            label: 'Đang phục vụ',
            value: '$activeAppointments',
            onTap: onOpenAppointments,
          ),
          const SizedBox(height: 6),
          _AttentionRow(
            icon: Icons.event_available_outlined,
            label: 'Đã đặt còn lại',
            value: '$bookedAppointments',
            onTap: onOpenAppointments,
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.panelRaised.withValues(alpha: AppColors.isLight ? 0.72 : 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.62)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.iconSurface,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: AppColors.copper),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
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

    return _PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.group_outlined,
            title: 'Khách hàng cần nhớ',
            actionLabel: 'Xem tất cả',
            actionKey: const Key('overview-open-customers'),
            onAction: onOpen,
          ),
          const SizedBox(height: 10),
          if (visibleCustomers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 27),
              child: Text(
                'Chưa có khách hàng nổi bật.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            for (var index = 0; index < visibleCustomers.length; index++) ...[
              _CustomerRow(customer: visibleCustomers[index], onTap: onOpen),
              if (index < visibleCustomers.length - 1)
                Divider(height: 1, color: AppColors.workspaceDivider),
            ],
        ],
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
    final initials = customer['initials']?.toString().trim();
    final name = customer['name']?.toString() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              _InitialAvatar(name: name, initials: initials, radius: 18),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      customer['service']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(label: customer['tier']?.toString() ?? ''),
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
    final values = points
        .map((point) => (point['value'] as num?)?.toDouble() ?? 0)
        .toList();

    return _PremiumSurface(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.bar_chart_rounded,
            title: 'Doanh thu 7 ngày',
            actionLabel: 'Xem báo cáo',
            actionKey: const Key('overview-open-reports'),
            onAction: onOpen,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenueSparklinePainter(values),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var index = 0; index < points.length; index++)
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                      child: Column(
                        children: [
                          Text(
                            points[index]['label']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _compactMoney(values.length > index ? values[index] : 0),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.iconSurface,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: AppColors.copper),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        TextButton(
          key: actionKey,
          onPressed: onAction,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(actionLabel),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_forward_rounded, size: 15),
            ],
          ),
        ),
      ],
    );
  }
}

class _PremiumSurface extends StatelessWidget {
  const _PremiumSurface({
    required this.child,
    required this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppColors.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: content,
      ),
    );
  }
}

class _IconMedallion extends StatelessWidget {
  const _IconMedallion({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.iconSurface,
        borderRadius: BorderRadius.circular(AppColors.isIvory ? size / 2 : 14),
        border: Border.all(color: AppColors.copper.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: AppColors.copper.withValues(alpha: AppColors.isLight ? 0.08 : 0.12),
            blurRadius: 16,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.43, color: AppColors.copper),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.name,
    this.initials,
    this.radius = 17,
  });

  final String name;
  final String? initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = (initials == null || initials!.trim().isEmpty)
        ? _initialsFromName(name)
        : initials!.trim();

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.avatarFill,
      foregroundColor: AppColors.textPrimary,
      child: Text(
        resolved,
        maxLines: 1,
        style: TextStyle(fontSize: radius * 0.56, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (label) {
      'Hoàn thành' => (Icons.check_circle_outline_rounded, AppColors.success),
      'Đang làm' => (Icons.content_cut_rounded, AppColors.copper),
      'Chờ xác nhận' => (Icons.hourglass_top_rounded, AppColors.warning),
      'Đã đặt' => (Icons.event_available_outlined, AppColors.info),
      _ => (Icons.circle_outlined, AppColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppColors.isLight ? 0.10 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueSparklinePainter extends CustomPainter {
  const _RevenueSparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    final topPadding = 10.0;
    final bottomPadding = 12.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final normalized = (values[index] - minValue) / range;
      points.add(
        Offset(
          step * index,
          topPadding + chartHeight * (1 - normalized),
        ),
      );
    }

    final gridPaint = Paint()
      ..color = AppColors.chartGrid
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - bottomPadding),
      Offset(size.width, size.height - bottomPadding),
      gridPaint,
    );

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      linePath.lineTo(points[index].dx, points[index].dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height - bottomPadding)
      ..lineTo(points.first.dx, size.height - bottomPadding)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.copper.withValues(alpha: AppColors.isLight ? 0.18 : 0.24),
          AppColors.copper.withValues(alpha: 0.015),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = AppColors.copper
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()..color = AppColors.copper;
    for (final point in points) {
      canvas.drawCircle(point, 2.7, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueSparklinePainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (var index = 0; index < values.length; index++) {
      if (oldDelegate.values[index] != values[index]) return true;
    }
    return false;
  }
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}

String _initialsFromName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

String _compactMoney(double value) {
  if (value >= 1000000) {
    final amount = value / 1000000;
    return '${amount.toStringAsFixed(amount >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)}K';
  }
  return value.toStringAsFixed(0);
}
