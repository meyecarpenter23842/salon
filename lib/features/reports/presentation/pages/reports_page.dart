import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/models/reports_period.dart';
import '../../../../core/providers/data_backend_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final selectedReportServiceIndexProvider = StateProvider<int>((ref) => 0);

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsSummaryProvider);
    final backend = ref.watch(appDataBackendProvider);

    return reports.when(
      data: (summary) => _ReportsView(summary: summary, backend: backend),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được báo cáo: $error')),
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
    final periods = ReportsPeriod.values;
    final selectedPeriod = ref.watch(reportsPeriodProvider);
    final selectedIndex = ref.watch(selectedReportServiceIndexProvider);
    final effectiveIndex = servicePerformance.isEmpty
        ? 0
        : selectedIndex.clamp(0, servicePerformance.length - 1);
    final selectedService = servicePerformance.isEmpty
        ? null
        : servicePerformance[effectiveIndex];

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 560;

        Widget buildBody() {
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1220;

              if (compact) {
                return ListView(
                  primary: false,
                  children: [
                    _RevenueTrendPanel(points: revenueTrend),
                    const SizedBox(height: 16),
                    _ServicePerformancePanel(
                      items: servicePerformance,
                      selectedIndex: effectiveIndex,
                    ),
                    const SizedBox(height: 16),
                    _ReportServiceDetailPanel(service: selectedService),
                    const SizedBox(height: 16),
                    _EmployeePerformancePanel(items: employeePerformance),
                    const SizedBox(height: 16),
                    _InsightsPanel(items: insights),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: ListView(
                      primary: false,
                      children: [
                        _RevenueTrendPanel(points: revenueTrend),
                        const SizedBox(height: 16),
                        _ServicePerformancePanel(
                          items: servicePerformance,
                          selectedIndex: effectiveIndex,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: ListView(
                      primary: false,
                      children: [
                        _ReportServiceDetailPanel(service: selectedService),
                        const SizedBox(height: 16),
                        _EmployeePerformancePanel(items: employeePerformance),
                        const SizedBox(height: 16),
                        _InsightsPanel(items: insights),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }

        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              _ReportsHero(
                goalRevenue: summary['revenue'].toString(),
                fillRate: summary['fillRate'].toString(),
                backend: backend,
              ),
              const SizedBox(height: AppDimens.heroGap),
              _ReportsSummaryRow(summary: summary),
              const SizedBox(height: AppDimens.sectionGap),
              _ReportsToolbar(
                periods: periods,
                selectedPeriod: selectedPeriod,
                summary: summary,
              ),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 980, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReportsHero(
              goalRevenue: summary['revenue'].toString(),
              fillRate: summary['fillRate'].toString(),
              backend: backend,
            ),
            const SizedBox(height: AppDimens.heroGap),
            _ReportsSummaryRow(summary: summary),
            const SizedBox(height: AppDimens.sectionGap),
            _ReportsToolbar(
              periods: periods,
              selectedPeriod: selectedPeriod,
              summary: summary,
            ),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _ReportsHero extends StatelessWidget {
  const _ReportsHero({
    required this.goalRevenue,
    required this.fillRate,
    required this.backend,
  });

  final String goalRevenue;
  final String fillRate;
  final AppDataBackend backend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1080;
          final spotlight = _HeroSpotlight(
            goalRevenue: goalRevenue,
            fillRate: fillRate,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroCopy(backend: backend),
                const SizedBox(height: 18),
                spotlight,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _HeroCopy(backend: backend)),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: spotlight),
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
        ? 'Runtime: SQLite'
        : 'Runtime: Fake';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.copper.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Reports Desktop',
            style: TextStyle(
              color: AppColors.copper,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Báo cáo',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Workflow báo cáo desktop-first - đọc nhanh doanh thu, dịch vụ chủ lực, hiệu suất nhân sự và insight vận hành trước khi nối dữ liệu thật.',
          style: TextStyle(color: AppColors.textMuted, height: 1.6),
        ),
        const SizedBox(height: 16),
        if (backend == AppDataBackend.fake) ...[
          const _DataSourceNotice(
            title: 'Báo cáo đang dùng dữ liệu demo',
            message:
                'Toàn bộ số liệu doanh thu, dịch vụ, nhân sự và insight trong màn hình này hiện lấy từ fake repository để khóa UX desktop. Không dùng các chỉ số này làm số liệu vận hành thật.',
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppBadge(
              label: runtimeLabel,
              tone: backend == AppDataBackend.sqlite
                  ? AppBadgeTone.success
                  : AppBadgeTone.info,
            ),
            if (backend == AppDataBackend.fake)
              const AppBadge(label: 'Demo metrics', tone: AppBadgeTone.warning),
          ],
        ),
      ],
    );
  }
}

class _DataSourceNotice extends StatelessWidget {
  const _DataSourceNotice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.copper.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.copper),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(color: AppColors.textMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSpotlight extends StatelessWidget {
  const _HeroSpotlight({required this.goalRevenue, required this.fillRate});

  final String goalRevenue;
  final String fillRate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tóm tắt tuần hiện tại',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          _HeroMetric(label: 'Doanh thu', value: goalRevenue),
          const SizedBox(height: 12),
          _HeroMetric(label: 'Tỷ lệ kín lịch', value: fillRate),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ReportsSummaryRow extends StatelessWidget {
  const _ReportsSummaryRow({required this.summary});

  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(label: 'Doanh thu', value: summary['revenue'].toString()),
      _SummaryCard(
        label: 'Số hóa đơn',
        value: summary['invoiceCount'].toString(),
      ),
      _SummaryCard(
        label: 'Top dịch vụ',
        value: summary['topService'].toString(),
      ),
      _SummaryCard(
        label: 'Top nhân sự',
        value: summary['topEmployee'].toString(),
      ),
      _SummaryCard(
        label: 'Tỷ lệ kín lịch',
        value: summary['fillRate'].toString(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        if (constraints.maxWidth < 1320) {
          final columns = constraints.maxWidth < 1080 ? 2 : 3;
          final cardWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsToolbar extends ConsumerWidget {
  const _ReportsToolbar({
    required this.periods,
    required this.selectedPeriod,
    required this.summary,
  });

  final List<ReportsPeriod> periods;
  final ReportsPeriod selectedPeriod;
  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: periods
              .map(
                (period) => FilterChip(
                  label: Text(period.label),
                  selected: period == selectedPeriod,
                  onSelected: (_) {
                    ref.read(reportsPeriodProvider.notifier).state = period;
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _exportReportsCsv(context, summary),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Xuất CSV'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RevenueTrendPanel extends StatelessWidget {
  const _RevenueTrendPanel({required this.points});

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Xu hướng doanh thu',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: AppColors.panelRaised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(20),
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
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: points
                        .map(
                          (point) => Text(
                            point['label'].toString(),
                            style: TextStyle(color: AppColors.textMuted),
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

class _ServicePerformancePanel extends ConsumerWidget {
  const _ServicePerformancePanel({
    required this.items,
    required this.selectedIndex,
  });

  final List<Map<String, Object?>> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Top dịch vụ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${items.length} mục',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...items.asMap().entries.map(
              (entry) => _ServicePerformanceTile(
                item: entry.value,
                selected: entry.key == selectedIndex,
                onTap: () {
                  ref.read(selectedReportServiceIndexProvider.notifier).state =
                      entry.key;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicePerformanceTile extends StatelessWidget {
  const _ServicePerformanceTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final Map<String, Object?> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.copper : AppColors.border,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.avatarFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.auto_graph_outlined, color: AppColors.copper),
        ),
        title: Text(
          item['name'].toString(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${item['bookings']} lịch - ${item['share']} doanh thu',
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
        trailing: Text(
          item['revenue'].toString(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ReportServiceDetailPanel extends StatelessWidget {
  const _ReportServiceDetailPanel({required this.service});

  final Map<String, Object?>? service;

  @override
  Widget build(BuildContext context) {
    if (service == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chọn một dịch vụ để xem chi tiết báo cáo.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              service!['name'].toString(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Doanh thu',
                    value: service!['revenue'].toString(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    label: 'Số lịch',
                    value: '${service!['bookings']}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    label: 'Tỷ trọng',
                    value: service!['share'].toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DetailSection(
              title: 'Nhận định',
              content: service!['note'].toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeePerformancePanel extends StatelessWidget {
  const _EmployeePerformancePanel({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hiệu suất nhân sự',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            ...items.map(
              (item) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panelRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['name']} - ${item['role']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          item['revenue'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item['clients']} khách - Rating ${item['rating']}',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['focus'].toString(),
                      style: TextStyle(color: AppColors.textMuted, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Insight vận hành',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            ...items.map(
              (item) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panelRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      color: AppColors.copper,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(height: 1.5)),
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
      'Tong_quan,Ty_le_kin_lich,${summary['fillRate']}',
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
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã xuất báo cáo: $outputPath')));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Xuất báo cáo thất bại: $error')));
  }
}
