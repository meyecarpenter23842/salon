import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/models/reports_period.dart';
import '../../../../core/providers/data_backend_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final selectedReportServiceIndexProvider = StateProvider<int>((ref) => 0);

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsSummaryProvider);
    final backend = ref.watch(appDataBackendProvider);

    return reports.when(
      data: (summary) => _ReportsView(summary: summary, backend: backend),
      loading: () => const PremiumLoadingState(label: 'Đang tải báo cáo…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được báo cáo',
        message: '$error',
        onRetry: () => ref.invalidate(reportsSummaryProvider),
      ),
    );
  }
}

class _ReportsView extends ConsumerWidget {
  const _ReportsView({required this.summary, required this.backend});

  final Map<String, Object?> summary;
  final AppDataBackend backend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicePerformance = _mapList(summary['servicePerformance']);
    final employeePerformance = _mapList(summary['employeePerformance']);
    final revenueTrend = _mapList(summary['revenueTrend']);
    final insights = _stringList(summary['insights']);
    final selectedIndex = ref.watch(selectedReportServiceIndexProvider);
    final effectiveIndex = servicePerformance.isEmpty
        ? 0
        : selectedIndex.clamp(0, servicePerformance.length - 1);
    final selectedService = servicePerformance.isEmpty
        ? null
        : servicePerformance[effectiveIndex];
    final serviceDetail = PremiumAnimatedDetail(
      transitionKey: ValueKey(
        selectedService?['name']?.toString() ?? 'report-service-empty',
      ),
      child: _ReportServiceDetailPanel(service: selectedService),
    );

    return ListView(
      key: const Key('reports-premium-workspace'),
      primary: false,
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        PremiumSectionCard(
          key: const Key('reports-premium-header'),
          child: PremiumPageHeader(
            icon: Icons.query_stats_rounded,
            eyebrow: 'Hiệu suất salon',
            title: 'Báo cáo',
            subtitle:
                'Theo dõi doanh thu, dịch vụ chủ lực, hiệu suất nhân sự và insight vận hành theo dữ liệu runtime.',
            trailing: [
              PremiumStatusPill(
                label: backend == AppDataBackend.sqlite
                    ? 'SQLite runtime'
                    : 'Dữ liệu demo',
                tone: backend == AppDataBackend.sqlite
                    ? AppColors.success
                    : AppColors.warning,
              ),
              FilledButton.icon(
                onPressed: () => _exportReportsCsv(context, summary),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Xuất CSV'),
              ),
            ],
          ),
        ),
        if (backend == AppDataBackend.fake) ...[
          const SizedBox(height: 12),
          const _DemoDataNotice(),
        ],
        const SizedBox(height: 14),
        _ReportStats(summary: summary),
        const SizedBox(height: 14),
        const _ReportsToolbar(),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 1180;
            final left = Column(
              children: [
                _RevenueTrendPanel(points: revenueTrend),
                const SizedBox(height: 14),
                _ServicePerformancePanel(
                  items: servicePerformance,
                  selectedIndex: effectiveIndex,
                ),
              ],
            );
            final right = Column(
              children: [
                serviceDetail,
                const SizedBox(height: 14),
                _EmployeePerformancePanel(items: employeePerformance),
                const SizedBox(height: 14),
                _InsightsPanel(items: insights),
              ],
            );

            if (!twoColumns) {
              return Column(
                children: [
                  left,
                  const SizedBox(height: 14),
                  right,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 11, child: left),
                const SizedBox(width: 14),
                Expanded(flex: 9, child: right),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DemoDataNotice extends StatelessWidget {
  const _DemoDataNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: AppColors.isLight ? 0.08 : 0.11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Môi trường hiện tại đang dùng fake repository. Các chỉ số trên màn hình này chỉ dùng để kiểm tra giao diện, không phải số liệu vận hành thật.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportStats extends StatelessWidget {
  const _ReportStats({required this.summary});

  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Doanh thu',
        value: summary['revenue'].toString(),
        tone: AppColors.copper,
      ),
      PremiumStatCard(
        icon: Icons.receipt_long_outlined,
        label: 'Số hóa đơn',
        value: summary['invoiceCount'].toString(),
        tone: AppColors.info,
      ),
      PremiumStatCard(
        icon: Icons.content_cut_rounded,
        label: 'Top dịch vụ',
        value: summary['topService'].toString(),
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.badge_outlined,
        label: 'Top nhân sự',
        value: summary['topEmployee'].toString(),
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.event_available_outlined,
        label: 'Tỷ lệ hoàn thành',
        value:
            summary['completionRate']?.toString() ?? summary['fillRate'].toString(),
        tone: AppColors.copper,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1450
            ? 5
            : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 580
                    ? 2
                    : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }
}

class _ReportsToolbar extends ConsumerWidget {
  const _ReportsToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reportsPeriodProvider);
    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.date_range_outlined, size: 17, color: AppColors.copper),
                    const SizedBox(width: 7),
                    Text(
                      'Khoảng thời gian',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              for (final period in ReportsPeriod.values)
                FilterChip(
                  label: Text(period.label),
                  selected: period == selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    ref.read(reportsPeriodProvider.notifier).state = period;
                    ref.read(selectedReportServiceIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RevenueTrendPanel extends StatelessWidget {
  const _RevenueTrendPanel({required this.points});

  final List<Map<String, Object?>> points;

  @override
  Widget build(BuildContext context) {
    final values = points
        .map((point) => (point['value'] as num?)?.toDouble() ?? 0)
        .toList();
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final average = values.isEmpty ? 0.0 : total / values.length;

    return PremiumSectionCard(
      icon: Icons.show_chart_rounded,
      title: 'Xu hướng doanh thu',
      subtitle: points.isEmpty
          ? 'Chưa có dữ liệu theo kỳ đã chọn'
          : '${points.length} mốc dữ liệu • trung bình ${_compactCurrency(average)}',
      child: points.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.show_chart_rounded,
              title: 'Chưa có dữ liệu doanh thu',
              message: 'Đổi khoảng thời gian hoặc ghi nhận hóa đơn để xem xu hướng.',
            )
          : Column(
              children: [
                Container(
                  height: 210,
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  decoration: BoxDecoration(
                    color: AppColors.featureSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: _RevenueTrendPainter(values),
                  ),
                ),
                const SizedBox(height: 10),
                _ChartEdgeLabels(points: points),
              ],
            ),
    );
  }
}

class _ChartEdgeLabels extends StatelessWidget {
  const _ChartEdgeLabels({required this.points});

  final List<Map<String, Object?>> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final middle = points.length > 2 ? points[points.length ~/ 2] : null;
    final labels = <Map<String, Object?>>[
      points.first,
      ?middle,
      if (points.length > 1) points.last,
    ];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Column(
              crossAxisAlignment: index == 0
                  ? CrossAxisAlignment.start
                  : index == labels.length - 1
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.center,
              children: [
                Text(
                  labels[index]['label']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  _compactCurrency(
                    (labels[index]['value'] as num?)?.toDouble() ?? 0,
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RevenueTrendPainter extends CustomPainter {
  const _RevenueTrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    const top = 18.0;
    const bottom = 22.0;
    const horizontal = 6.0;
    final chartWidth = math.max(1.0, size.width - horizontal * 2);
    final chartHeight = math.max(1.0, size.height - top - bottom);
    final step = values.length <= 1 ? 0.0 : chartWidth / (values.length - 1);

    final gridPaint = Paint()
      ..color = AppColors.chartGrid
      ..strokeWidth = 1;
    for (var row = 0; row < 4; row++) {
      final y = top + (chartHeight / 3) * row;
      canvas.drawLine(Offset(horizontal, y), Offset(size.width - horizontal, y), gridPaint);
    }

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final normalized = (values[index] - minValue) / range;
      points.add(
        Offset(
          horizontal + step * index,
          top + chartHeight * (1 - normalized),
        ),
      );
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final controlX = (previous.dx + current.dx) / 2;
      linePath.cubicTo(controlX, previous.dy, controlX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, top + chartHeight)
      ..lineTo(points.first.dx, top + chartHeight)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.copper.withValues(alpha: AppColors.isLight ? 0.20 : 0.28),
          AppColors.copper.withValues(alpha: 0.01),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = AppColors.copper
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()..color = AppColors.copper;
    for (final point in points) {
      canvas.drawCircle(point, 2.8, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueTrendPainter oldDelegate) {
    if (oldDelegate.values.length != values.length) return true;
    for (var index = 0; index < values.length; index++) {
      if (oldDelegate.values[index] != values[index]) return true;
    }
    return false;
  }
}

class _ServicePerformancePanel extends ConsumerWidget {
  const _ServicePerformancePanel({
    required this.items,
    required this.selectedIndex,
  });

  final List<Map<String, Object?>> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.content_cut_rounded,
      title: 'Top dịch vụ',
      subtitle: '${items.length} dịch vụ trong kỳ đã chọn',
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.content_cut_rounded,
              title: 'Chưa có hiệu suất dịch vụ',
              message: 'Dữ liệu sẽ xuất hiện sau khi có hóa đơn trong kỳ.',
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _ServicePerformanceRow(
                    item: items[index],
                    selected: index == selectedIndex,
                    rank: index + 1,
                    onTap: () {
                      ref.read(selectedReportServiceIndexProvider.notifier).state = index;
                    },
                  ),
                  if (index < items.length - 1)
                    const PremiumDivider(indent: 52),
                ],
              ],
            ),
    );
  }
}

class _ServicePerformanceRow extends StatelessWidget {
  const _ServicePerformanceRow({
    required this.item,
    required this.selected,
    required this.rank,
    required this.onTap,
  });

  final Map<String, Object?> item;
  final bool selected;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumInteractiveSurface(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          PremiumIconBadge(
            icon: rank == 1 ? Icons.workspace_premium_outlined : Icons.auto_graph_outlined,
            size: 36,
            tone: rank == 1 ? AppColors.warning : AppColors.copper,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['bookings']} lịch • ${item['share']} doanh thu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item['revenue']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ReportServiceDetailPanel extends StatelessWidget {
  const _ReportServiceDetailPanel({required this.service});

  final Map<String, Object?>? service;

  @override
  Widget build(BuildContext context) {
    final item = service;
    if (item == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.analytics_outlined,
          title: 'Chọn một dịch vụ',
          message: 'Doanh thu, số lịch, tỷ trọng và nhận định sẽ hiển thị ở đây.',
        ),
      );
    }

    return PremiumSectionCard(
      icon: Icons.analytics_outlined,
      title: item['name']?.toString() ?? 'Chi tiết dịch vụ',
      subtitle: 'Hiệu suất trong khoảng thời gian đang chọn',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricWrap(
            metrics: [
              ('Doanh thu', item['revenue']?.toString() ?? '-'),
              ('Số lịch', item['bookings']?.toString() ?? '-'),
              ('Tỷ trọng', item['share']?.toString() ?? '-'),
            ],
          ),
          const SizedBox(height: 12),
          PremiumInfoRow(
            icon: Icons.lightbulb_outline_rounded,
            label: 'Nhận định',
            value: item['note']?.toString() ?? 'Chưa có nhận định',
          ),
        ],
      ),
    );
  }
}

class _MetricWrap extends StatelessWidget {
  const _MetricWrap({required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? metrics.length : 1;
        const gap = 8.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.featureSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        metric.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmployeePerformancePanel extends StatelessWidget {
  const _EmployeePerformancePanel({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionCard(
      icon: Icons.groups_2_outlined,
      title: 'Hiệu suất nhân sự',
      subtitle: '${items.length} thành viên có dữ liệu trong kỳ',
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.groups_2_outlined,
              title: 'Chưa có dữ liệu nhân sự',
              message: 'Hiệu suất sẽ xuất hiện khi hóa đơn có gắn nhân viên.',
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _EmployeePerformanceRow(item: items[index], rank: index + 1),
                  if (index < items.length - 1)
                    const PremiumDivider(indent: 52),
                ],
              ],
            ),
    );
  }
}

class _EmployeePerformanceRow extends StatelessWidget {
  const _EmployeePerformanceRow({required this.item, required this.rank});

  final Map<String, Object?> item;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumIconBadge(
            icon: Icons.person_outline_rounded,
            size: 36,
            tone: rank == 1 ? AppColors.warning : AppColors.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['name'] ?? ''} • ${item['role'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['clients']} khách • Rating ${item['rating']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 5),
                Text(
                  item['focus']?.toString() ?? '',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item['revenue']?.toString() ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionCard(
      icon: Icons.tips_and_updates_outlined,
      title: 'Insight vận hành',
      subtitle: 'Điểm đáng chú ý từ dữ liệu trong kỳ',
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.tips_and_updates_outlined,
              title: 'Chưa có insight',
              message: 'Insight sẽ xuất hiện khi có đủ dữ liệu để tổng hợp.',
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PremiumIconBadge(
                          icon: Icons.auto_awesome_outlined,
                          size: 32,
                          tone: index == 0 ? AppColors.warning : AppColors.copper,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            items[index],
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < items.length - 1)
                    const PremiumDivider(indent: 42),
                ],
              ],
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

List<String> _stringList(Object? source) {
  if (source is List) {
    return source.map((item) => item.toString()).toList();
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

Future<void> _exportReportsCsv(
  BuildContext context,
  Map<String, Object?> summary,
) async {
  try {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final baseDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(path.join(baseDir.path, 'salon_reports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final outputPath = path.join(exportDir.path, 'bao_cao_$timestamp.csv');
    final file = File(outputPath);

    final servicePerformance = _mapList(summary['servicePerformance']);
    final employeePerformance = _mapList(summary['employeePerformance']);
    final revenueTrend = _mapList(summary['revenueTrend']);
    final insights = _stringList(summary['insights']);

    final lines = <String>[
      'Muc,Chi_tiet,So_lieu',
      'Tong_quan,Doanh_thu,${summary['revenue']}',
      'Tong_quan,Top_dich_vu,${summary['topService']}',
      'Tong_quan,Top_nhan_su,${summary['topEmployee']}',
      'Tong_quan,Ty_le_hoan_thanh,${summary['completionRate'] ?? summary['fillRate']}',
      '',
      'Xu_huong_doanh_thu,Nhan,So_tien',
      ...revenueTrend.map(
        (item) => 'RevenueTrend,${item['label']},${item['value']}',
      ),
      '',
      'Hieu_suat_dich_vu,Ten,Doanh_thu,So_lich,Ty_trong,Ghi_chu',
      ...servicePerformance.map(
        (item) =>
            'Service,${item['name']},${item['revenue']},${item['bookings']},${item['share']},${item['note']}',
      ),
      '',
      'Hieu_suat_nhan_su,Ten,Vai_tro,Doanh_thu,Khach,Rating,Focus',
      ...employeePerformance.map(
        (item) =>
            'Employee,${item['name']},${item['role']},${item['revenue']},${item['clients']},${item['rating']},${item['focus']}',
      ),
      '',
      'Insight,Noi_dung',
      ...insights.map((item) => 'Insight,$item'),
    ];

    await file.writeAsString(lines.join('\n'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xuất báo cáo: $outputPath')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Xuất báo cáo thất bại: $error')),
    );
  }
}
