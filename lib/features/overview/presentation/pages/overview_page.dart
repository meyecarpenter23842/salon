import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/appointment_entry.dart';
import '../../../../core/providers/data_backend_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(overviewSummaryProvider);
    final appointments = ref.watch(appointmentsViewProvider);
    final backend = ref.watch(appDataBackendProvider);

    return overview.when(
      data: (summary) => appointments.when(
        data: (appointmentRows) => _OverviewLoaded(
          summary: summary,
          appointments: appointmentRows,
          backend: backend,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Không tải được lịch overview: $error'),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được tổng quan: $error')),
    );
  }
}

class _OverviewLoaded extends StatelessWidget {
  const _OverviewLoaded({
    required this.summary,
    required this.appointments,
    required this.backend,
  });

  final Map<String, Object?> summary;
  final List<AppointmentEntry> appointments;
  final AppDataBackend backend;

  @override
  Widget build(BuildContext context) {
    final kpis = _mapList(summary['kpis']);
    final featuredCustomers = _mapList(summary['featuredCustomers']);
    final quickCheckoutLines = _mapList(summary['quickCheckoutLines']);
    final revenueSeries = _mapList(summary['revenueSeries']);

    final waitingAppointments = appointments
        .where((item) => item.status == 'Chờ xác nhận')
        .length;
    final activeAppointments = appointments
        .where(
          (item) => item.status == 'Đã đặt' || item.status == 'Đang làm',
        )
        .length;

    final contentGrid = _OverviewContentGrid(
      appointments: appointments,
      featuredCustomers: featuredCustomers,
      quickCheckoutCustomer: summary['quickCheckoutCustomer'].toString(),
      quickCheckoutDiscount: summary['quickCheckoutDiscount'].toString(),
      quickCheckoutLines: quickCheckoutLines,
      quickCheckoutPaymentNote: summary['quickCheckoutPaymentNote'].toString(),
      quickCheckoutTotal: summary['quickCheckoutTotal'].toString(),
      revenueSeries: revenueSeries,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortViewport = constraints.maxHeight < 560;

        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              _OverviewHero(
                nextSlot: kpis.length > 3 ? kpis[3]['value'].toString() : '',
                dailyRevenue: kpis.length > 2
                    ? kpis[2]['value'].toString()
                    : '',
                waitingAppointments: waitingAppointments,
                activeAppointments: activeAppointments,
                backend: backend,
              ),
              const SizedBox(height: AppDimens.heroGap),
              _OverviewStatsRow(kpis: kpis),
              const SizedBox(height: AppDimens.sectionGap),
              contentGrid,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OverviewHero(
              nextSlot: kpis.length > 3 ? kpis[3]['value'].toString() : '',
              dailyRevenue: kpis.length > 2 ? kpis[2]['value'].toString() : '',
              waitingAppointments: waitingAppointments,
              activeAppointments: activeAppointments,
              backend: backend,
            ),
            const SizedBox(height: AppDimens.heroGap),
            _OverviewStatsRow(kpis: kpis),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: contentGrid),
          ],
        );
      },
    );
  }
}

class _OverviewHero extends StatelessWidget {
  const _OverviewHero({
    required this.nextSlot,
    required this.dailyRevenue,
    required this.waitingAppointments,
    required this.activeAppointments,
    required this.backend,
  });

  final String nextSlot;
  final String dailyRevenue;
  final int waitingAppointments;
  final int activeAppointments;
  final AppDataBackend backend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        gradient: AppColors.overviewHeroGradient,
        boxShadow: AppColors.luxuryShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1080;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroCopy(backend: backend),
                const SizedBox(height: 20),
                _HeroSpotlight(
                  nextSlot: nextSlot,
                  dailyRevenue: dailyRevenue,
                  waitingAppointments: waitingAppointments,
                  activeAppointments: activeAppointments,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _HeroCopy(backend: backend)),
              const SizedBox(width: 18),
              Expanded(
                flex: 2,
                child: _HeroSpotlight(
                  nextSlot: nextSlot,
                  dailyRevenue: dailyRevenue,
                  waitingAppointments: waitingAppointments,
                  activeAppointments: activeAppointments,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.backend});

  final AppDataBackend backend;

  @override
  Widget build(BuildContext context) {
    final runtimeLabel = backend == AppDataBackend.sqlite
        ? 'SQLite runtime'
        : 'Fake runtime';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tổng quan',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        if (backend == AppDataBackend.fake)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.copper),
                Text(
                  'Overview đang dùng dữ liệu demo',
                  style: TextStyle(color: AppColors.copper, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.circle, size: 8, color: AppColors.success),
                Text(
                  'SQLite runtime • Dữ liệu cập nhật trực tiếp',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        AppBadge(
          label: runtimeLabel,
          tone: backend == AppDataBackend.sqlite
              ? AppBadgeTone.success
              : AppBadgeTone.info,
        ),
      ],
    );
  }
}

class _HeroSpotlight extends StatelessWidget {
  const _HeroSpotlight({
    required this.nextSlot,
    required this.dailyRevenue,
    required this.waitingAppointments,
    required this.activeAppointments,
  });

  final String nextSlot;
  final String dailyRevenue;
  final int waitingAppointments;
  final int activeAppointments;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nhịp vận hành hôm nay',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          _FlatMetricRow(label: 'Lịch tiếp theo', value: nextSlot),
          const Divider(height: 20, thickness: 0.5),
          _FlatMetricRow(label: 'Doanh thu trong ngày', value: dailyRevenue),
          const Divider(height: 20, thickness: 0.5),
          _FlatMetricRow(
            label: 'Lịch đang chạy',
            value: '$activeAppointments lịch',
          ),
          const Divider(height: 20, thickness: 0.5),
          _FlatMetricRow(
            label: 'Cần xác nhận thêm',
            value: '$waitingAppointments lịch',
          ),
        ],
      ),
    );
  }
}

class _FlatMetricRow extends StatelessWidget {
  const _FlatMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _OverviewStatsRow extends StatelessWidget {
  const _OverviewStatsRow({required this.kpis});

  final List<Map<String, Object?>> kpis;

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
        final compact = constraints.maxWidth < 760;
        final cards = List.generate(kpis.length, (index) {
          final item = kpis[index];
          return _OverviewStatCard(
            title: item['title'].toString(),
            value: item['value'].toString(),
            note: item['note'].toString(),
            icon: icons[index.clamp(0, icons.length - 1)],
          );
        });

        if (compact) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 16),
              ],
            ],
          );
        }

        if (constraints.maxWidth < 1280) {
          final columns = constraints.maxWidth < 1080 ? 2 : 3;
          final cardWidth =
              (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index < cards.length - 1) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _OverviewStatCard extends StatelessWidget {
  const _OverviewStatCard({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: AppColors.shellAccentSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 16, color: AppColors.copper),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _OverviewContentGrid extends StatelessWidget {
  const _OverviewContentGrid({
    required this.appointments,
    required this.featuredCustomers,
    required this.quickCheckoutCustomer,
    required this.quickCheckoutDiscount,
    required this.quickCheckoutLines,
    required this.quickCheckoutPaymentNote,
    required this.quickCheckoutTotal,
    required this.revenueSeries,
  });

  final List<AppointmentEntry> appointments;
  final List<Map<String, Object?>> featuredCustomers;
  final String quickCheckoutCustomer;
  final String quickCheckoutDiscount;
  final List<Map<String, Object?>> quickCheckoutLines;
  final String quickCheckoutPaymentNote;
  final String quickCheckoutTotal;
  final List<Map<String, Object?>> revenueSeries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1200;

        if (compact) {
          return ListView(
            primary: false,
            children: [
              _AppointmentsPanel(rows: appointments, viewportHeight: 270),
              const SizedBox(height: 16),
              _FeaturedCustomersPanel(
                customers: featuredCustomers,
                viewportHeight: 250,
              ),
              const SizedBox(height: 16),
              _QuickCheckoutPanel(
                customerName: quickCheckoutCustomer,
                discount: quickCheckoutDiscount,
                lines: quickCheckoutLines,
                paymentNote: quickCheckoutPaymentNote,
                total: quickCheckoutTotal,
                viewportHeight: 300,
              ),
              const SizedBox(height: 16),
              _RevenuePanel(points: revenueSeries),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _AppointmentsPanel(rows: appointments),
                  ),
                  const SizedBox(height: 16),
                  _RevenuePanel(points: revenueSeries),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 2,
                    child: _FeaturedCustomersPanel(
                      customers: featuredCustomers,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    flex: 3,
                    child: _QuickCheckoutPanel(
                      customerName: quickCheckoutCustomer,
                      discount: quickCheckoutDiscount,
                      lines: quickCheckoutLines,
                      paymentNote: quickCheckoutPaymentNote,
                      total: quickCheckoutTotal,
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

class _AppointmentsPanel extends StatefulWidget {
  const _AppointmentsPanel({required this.rows, this.viewportHeight});

  final List<AppointmentEntry> rows;
  final double? viewportHeight;

  @override
  State<_AppointmentsPanel> createState() => _AppointmentsPanelState();
}

class _AppointmentsPanelState extends State<_AppointmentsPanel> {
  final ScrollController _vertCtrl = ScrollController();
  final ScrollController _horizCtrl = ScrollController();

  @override
  void dispose() {
    _vertCtrl.dispose();
    _horizCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollArea = Scrollbar(
      controller: _vertCtrl,
      child: SingleChildScrollView(
        controller: _vertCtrl,
        child: SingleChildScrollView(
          controller: _horizCtrl,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 640),
            child: Table(
              columnWidths: const {0: FixedColumnWidth(80)},
              children: [
                const TableRow(
                  children: [
                    _HeaderCell('Giờ'),
                    _HeaderCell('Khách hàng'),
                    _HeaderCell('Dịch vụ'),
                    _HeaderCell('Thợ'),
                    _HeaderCell('Trạng thái'),
                  ],
                ),
                ...widget.rows.map(
                  (row) => TableRow(
                    children: [
                      _BodyCell(row.timeLabel),
                      _BodyCell(row.customerName),
                      _BodyCell(row.servicesSummary),
                      _BodyCell(row.staffName),
                      _StatusCell(row.status),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeader(
              title: 'Lịch hẹn hôm nay',
              action: '${widget.rows.length} lịch hiển thị',
            ),
            const SizedBox(height: 14),
            if (widget.viewportHeight != null)
              SizedBox(height: widget.viewportHeight, child: scrollArea)
            else
              Expanded(child: scrollArea),
          ],
        ),
      ),
    );
  }
}

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({required this.points});

  final List<Map<String, Object?>> points;

  @override
  Widget build(BuildContext context) {
    final maxValue = points
        .map((point) => (point['value'] as num?)?.toDouble() ?? 0)
        .fold<double>(
          1,
          (previousValue, element) =>
              element > previousValue ? element : previousValue,
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(
              title: 'Doanh thu tuần này',
              action: 'Cập nhật theo ngày',
            ),
            const SizedBox(height: 14),
            Container(
              height: 236,
              decoration: BoxDecoration(
                color: AppColors.panelRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(points.length, (index) {
                        final point = points[index];
                        final value = (point['value'] as num?)?.toDouble() ?? 0;
                        final heightFactor = maxValue == 0
                            ? 0.1
                            : value / maxValue;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  _compactCurrency(value),
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      height: 160 * heightFactor.clamp(0.12, 1),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        gradient: AppColors.revenueBarGradient,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: points
                        .map(
                          (point) => Text(
                            point['label'].toString(),
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        )
                        .toList(),
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

class _FeaturedCustomersPanel extends StatefulWidget {
  const _FeaturedCustomersPanel({required this.customers, this.viewportHeight});

  final List<Map<String, Object?>> customers;
  final double? viewportHeight;

  @override
  State<_FeaturedCustomersPanel> createState() =>
      _FeaturedCustomersPanelState();
}

class _FeaturedCustomersPanelState extends State<_FeaturedCustomersPanel> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listView = Scrollbar(
      controller: _scrollCtrl,
      child: ListView.separated(
        controller: _scrollCtrl,
        primary: false,
        itemCount: widget.customers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final customer = widget.customers[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.panelRaised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 36,
                            width: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.copper),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              customer['initials'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        customer['name'].toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    AppBadge(
                                      label: customer['tier'].toString(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  customer['service'].toString(),
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  customer['note'].toString(),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    height: 1.4,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${customer['appointmentTime']} • ${customer['spendLabel']}',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
        },
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(
              title: 'Khách hàng nổi bật',
              action: '3 hồ sơ ưu tiên',
            ),
            const SizedBox(height: 14),
            if (widget.viewportHeight != null)
              SizedBox(height: widget.viewportHeight, child: listView)
            else
              Expanded(child: listView),
          ],
        ),
      ),
    );
  }
}

class _QuickCheckoutPanel extends StatefulWidget {
  const _QuickCheckoutPanel({
    required this.customerName,
    required this.discount,
    required this.lines,
    required this.paymentNote,
    required this.total,
    this.viewportHeight,
  });

  final String customerName;
  final String discount;
  final List<Map<String, Object?>> lines;
  final String paymentNote;
  final String total;
  final double? viewportHeight;

  @override
  State<_QuickCheckoutPanel> createState() => _QuickCheckoutPanelState();
}

class _QuickCheckoutPanelState extends State<_QuickCheckoutPanel> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linesScrollArea = Scrollbar(
      controller: _scrollCtrl,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        primary: false,
        child: Column(
          children: widget.lines
              .map(
                (line) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.panelRaised,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line['label'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Stylist ${line['stylist']} • SL ${line['qty']}',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        line['amount'].toString(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelHeader(
              title: 'Tính tiền nhanh',
              action: 'Draft invoice',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.panelRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Khách đang chọn',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.paymentNote,
                    style: TextStyle(color: AppColors.textMuted, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.viewportHeight != null)
              SizedBox(height: widget.viewportHeight, child: linesScrollArea)
            else
              Expanded(child: linesScrollArea),
            const Divider(height: 28),
            const _CheckoutSummaryRow(label: 'Tạm tính', value: '1.950.000₫'),
            const SizedBox(height: 10),
            _CheckoutSummaryRow(
              label: 'Giảm giá thành viên',
              value: '-${widget.discount}',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tổng cộng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  widget.total,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: null,
                    child: const Text('Tiền mặt'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: null,
                    child: const Text('Chuyển khoản'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.action});

  final String title;
  final String action;

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
        Text(
          action,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _CheckoutSummaryRow extends StatelessWidget {
  const _CheckoutSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: AppColors.textMuted)),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppStatusBadge(label: text),
      ),
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
