import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/employee_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/employee_profile_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');
final employeeRoleFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final selectedEmployeeIndexProvider = StateProvider<int>((ref) => 0);

final employeeProfileRepositoryProvider =
    Provider<EmployeeProfileRepository?>((ref) {
  final repository = ref.watch(employeesRepositoryProvider);
  return repository is EmployeeProfileRepository
      ? repository as EmployeeProfileRepository
      : null;
});

final employeeProfileProvider =
    FutureProvider.family<Map<String, Object?>?, String>((ref, employeeId) async {
  final repository = ref.watch(employeeProfileRepositoryProvider);
  if (repository == null) return null;
  return repository.fetchEmployeeProfile(employeeId);
});

final filteredEmployeesProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  final employees =
      await ref.watch(employeesRepositoryProvider).fetchEmployeesView();
  final query = ref.watch(employeeSearchQueryProvider).trim().toLowerCase();
  final role = ref.watch(employeeRoleFilterProvider);

  return employees.where((item) {
    final matchesRole = role == 'Tất cả' || item['role'] == role;
    final matchesQuery = query.isEmpty ||
        [
          item['name'],
          item['role'],
          item['specialty'],
          item['phone'],
          item['status'],
        ].any((value) => value.toString().toLowerCase().contains(query));
    return matchesRole && matchesQuery;
  }).toList(growable: false);
});

Future<void> _openEmployeeEditor(
  BuildContext context,
  WidgetRef ref, {
  Map<String, Object?>? employee,
}) async {
  final input = await showDialog<EmployeeUpsertInput>(
    context: context,
    builder: (_) => _EmployeeEditorDialog(employee: employee),
  );
  if (input == null || !context.mounted) return;

  try {
    final saved = await ref
        .read(employeesRepositoryProvider)
        .saveEmployee(input, existingId: employee?['id']?.toString());
    if (!context.mounted) return;

    final id = saved['id']?.toString() ?? '';
    ref.read(employeeSearchQueryProvider.notifier).state =
        saved['name']?.toString() ?? '';
    ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
    ref.invalidate(filteredEmployeesProvider);
    ref.invalidate(employeesViewProvider);
    if (id.isNotEmpty) ref.invalidate(employeeProfileProvider(id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          employee == null
              ? 'Đã thêm nhân sự ${saved['name']}'
              : 'Đã cập nhật ${saved['name']}',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không lưu được nhân sự: $error')),
    );
  }
}

Future<void> _updateEmployeeStatus(
  BuildContext context,
  WidgetRef ref,
  Map<String, Object?> employee,
) async {
  final currentStatus = employee['status']?.toString() ?? 'Đang làm việc';
  final nextStatus = switch (currentStatus) {
    'Đang làm việc' => 'Sắp có lịch',
    'Sắp có lịch' => 'Tạm nghỉ',
    _ => 'Đang làm việc',
  };

  try {
    final updated = await ref
        .read(employeesRepositoryProvider)
        .updateEmployeeStatus(employee['id']!.toString(), nextStatus);
    if (!context.mounted) return;

    final id = updated['id']?.toString() ?? '';
    ref.read(employeeSearchQueryProvider.notifier).state =
        updated['name']?.toString() ?? '';
    ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
    ref.invalidate(filteredEmployeesProvider);
    ref.invalidate(employeesViewProvider);
    if (id.isNotEmpty) ref.invalidate(employeeProfileProvider(id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã chuyển ${updated['name']} sang trạng thái ${updated['status']}',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không đổi được trạng thái: $error')),
    );
  }
}

class EmployeesPage extends ConsumerWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(filteredEmployeesProvider);
    return employees.when(
      data: (items) => _EmployeesView(items: items),
      loading: () => const PremiumLoadingState(label: 'Đang tải đội ngũ…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được nhân sự',
        message: '$error',
        onRetry: () => ref.invalidate(filteredEmployeesProvider),
      ),
    );
  }
}

class _EmployeesView extends ConsumerWidget {
  const _EmployeesView({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedEmployeeIndexProvider);
    final effectiveIndex = items.isEmpty ? 0 : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final active = items.where((item) => item['status'] == 'Đang làm việc').length;
    final upcoming = items.where((item) => item['status'] == 'Sắp có lịch').length;
    final resting = items.where((item) => item['status'] == 'Tạm nghỉ').length;

    return KeyedSubtree(
      key: const Key('employees-premium-workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumSectionCard(
            key: const Key('employees-premium-header'),
            child: PremiumPageHeader(
              icon: Icons.badge_outlined,
              eyebrow: 'Đội ngũ salon',
              title: 'Hồ sơ nhân viên',
              subtitle:
                  'Một nơi để xem ca làm, lịch hẹn, dịch vụ đã làm, doanh thu và hoa hồng thực tế của từng người.',
              trailing: [
                PremiumStatusPill(
                  label: '${items.length} hồ sơ',
                  tone: AppColors.copper,
                ),
                FilledButton.icon(
                  onPressed: () => _openEmployeeEditor(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Thêm nhân sự'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _EmployeeStats(
            total: items.length,
            active: active,
            upcoming: upcoming,
            resting: resting,
          ),
          const SizedBox(height: 12),
          const _EmployeesToolbar(),
          const SizedBox(height: 12),
          Expanded(
            child: _EmployeeWorkspace(
              items: items,
              selectedIndex: effectiveIndex,
              selected: selected,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeStats extends StatelessWidget {
  const _EmployeeStats({
    required this.total,
    required this.active,
    required this.upcoming,
    required this.resting,
  });

  final int total;
  final int active;
  final int upcoming;
  final int resting;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.groups_2_outlined,
        label: 'Tổng nhân sự',
        value: '$total',
      ),
      PremiumStatCard(
        icon: Icons.check_circle_outline_rounded,
        label: 'Đang làm việc',
        value: '$active',
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.event_available_outlined,
        label: 'Sắp có lịch',
        value: '$upcoming',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.pause_circle_outline_rounded,
        label: 'Tạm nghỉ',
        value: '$resting',
        tone: AppColors.textMuted,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        const gap = 10.0;
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

class _EmployeesToolbar extends ConsumerWidget {
  const _EmployeesToolbar();

  static const roles = [
    'Tất cả',
    'Stylist chính',
    'Barber',
    'Chăm sóc tóc',
    'Lễ tân',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRole = ref.watch(employeeRoleFilterProvider);
    final query = ref.watch(employeeSearchQueryProvider);

    return PremiumSectionCard(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextFormField(
            key: ValueKey('employee-search-$query'),
            initialValue: query,
            onChanged: (value) {
              ref.read(employeeSearchQueryProvider.notifier).state = value;
              ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Tìm tên, vai trò, chuyên môn, số điện thoại',
            ),
          );
          final role = DropdownButtonFormField<String>(
            initialValue: roles.contains(selectedRole) ? selectedRole : roles.first,
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.tune_rounded),
              labelText: 'Vai trò',
            ),
            items: roles
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              ref.read(employeeRoleFilterProvider.notifier).state = value;
              ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
            },
          );

          if (constraints.maxWidth < 680) {
            return Column(
              children: [search, const SizedBox(height: 8), role],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 10),
              SizedBox(width: 220, child: role),
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeWorkspace extends StatelessWidget {
  const _EmployeeWorkspace({
    required this.items,
    required this.selectedIndex,
    required this.selected,
  });

  final List<Map<String, Object?>> items;
  final int selectedIndex;
  final Map<String, Object?>? selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final list = _EmployeeList(items: items, selectedIndex: selectedIndex);
        final detail = PremiumAnimatedDetail(
          transitionKey: ValueKey(selected?['id']?.toString() ?? 'employee-empty'),
          child: _EmployeeDetail(employee: selected),
        );

        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              SizedBox(height: 210, child: list),
              const SizedBox(height: 10),
              Expanded(child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: constraints.maxWidth * 0.34, child: list),
            const SizedBox(width: 12),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _EmployeeList extends ConsumerWidget {
  const _EmployeeList({required this.items, required this.selectedIndex});

  final List<Map<String, Object?>> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.groups_2_outlined,
      title: 'Đội ngũ',
      subtitle: '${items.length} hồ sơ phù hợp',
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Không có nhân sự phù hợp',
              message: 'Đổi bộ lọc hoặc thêm nhân sự mới.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 48),
              itemBuilder: (context, index) {
                final employee = items[index];
                final status = employee['status']?.toString() ?? '';
                final tone = _statusTone(status);
                return PremiumInteractiveSurface(
                  selected: index == selectedIndex,
                  onTap: () {
                    ref.read(selectedEmployeeIndexProvider.notifier).state = index;
                  },
                  child: Row(
                    children: [
                      PremiumIconBadge(
                        icon: Icons.person_outline_rounded,
                        size: 38,
                        tone: tone,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${employee['role']} • ${employee['shift']}',
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
                      const SizedBox(width: 8),
                      PremiumStatusPill(label: status, tone: tone),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _EmployeeDetail extends ConsumerWidget {
  const _EmployeeDetail({required this.employee});

  final Map<String, Object?>? employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = employee;
    if (current == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.badge_outlined,
          title: 'Chọn một nhân sự',
          message: 'Hồ sơ, lịch và hiệu suất sẽ hiển thị ở đây.',
        ),
      );
    }

    final id = current['id']?.toString() ?? '';
    final profile = ref.watch(employeeProfileProvider(id));
    return profile.when(
      data: (value) => _EmployeeProfileBody(
        baseEmployee: current,
        profile: value ?? _fallbackProfile(current),
      ),
      loading: () => const PremiumSectionCard(
        child: PremiumLoadingState(label: 'Đang tải hồ sơ nhân viên…'),
      ),
      error: (error, _) => PremiumSectionCard(
        child: PremiumErrorState(
          title: 'Không tải được hồ sơ',
          message: '$error',
          onRetry: () => ref.invalidate(employeeProfileProvider(id)),
        ),
      ),
    );
  }
}

class _EmployeeProfileBody extends ConsumerWidget {
  const _EmployeeProfileBody({
    required this.baseEmployee,
    required this.profile,
  });

  final Map<String, Object?> baseEmployee;
  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = profile['status']?.toString() ?? '';
    final tone = _statusTone(status);

    return PremiumSectionCard(
      key: const Key('employee-profile-card'),
      padding: EdgeInsets.zero,
      child: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  PremiumIconBadge(
                    icon: Icons.person_rounded,
                    size: 46,
                    tone: tone,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile['name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${profile['role']} • ${profile['phone']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  PremiumStatusPill(label: status, tone: tone),
                ],
              ),
            ),
            const PremiumDivider(),
            SizedBox(
              key: const Key('employee-profile-tabs'),
              height: 42,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelColor: AppColors.copper,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.copper,
                tabs: const [
                  Tab(text: 'Tổng quan'),
                  Tab(text: 'Lịch hẹn'),
                  Tab(text: 'Hiệu suất'),
                  Tab(text: 'Lịch sử phục vụ'),
                ],
              ),
            ),
            const PremiumDivider(),
            Expanded(
              child: TabBarView(
                children: [
                  _EmployeeOverviewTab(profile: profile),
                  _EmployeeScheduleTab(profile: profile),
                  _EmployeePerformanceTab(profile: profile),
                  _EmployeeHistoryTab(profile: profile),
                ],
              ),
            ),
            const PremiumDivider(),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openEmployeeEditor(
                        context,
                        ref,
                        employee: baseEmployee,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Sửa hồ sơ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _updateEmployeeStatus(context, ref, baseEmployee),
                      icon: const Icon(Icons.sync_alt_outlined),
                      label: const Text('Đổi trạng thái'),
                    ),
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

class _EmployeeOverviewTab extends StatelessWidget {
  const _EmployeeOverviewTab({required this.profile});

  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('employee-profile-overview'),
      primary: false,
      padding: const EdgeInsets.all(14),
      children: [
        _ProfileMetrics(profile: profile),
        const SizedBox(height: 12),
        PremiumInfoRow(
          icon: Icons.schedule_outlined,
          label: 'Ca làm',
          value: profile['shift']?.toString() ?? 'Chưa thiết lập',
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.auto_awesome_outlined,
          label: 'Chuyên môn',
          value: profile['specialty']?.toString() ?? 'Chưa thiết lập',
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.percent_rounded,
          label: 'Hoa hồng / KPI',
          value: profile['commission']?.toString() ?? 'KPI cố định',
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.event_available_outlined,
          label: 'Lịch tiếp theo',
          value: profile['nextAppointmentLabel']?.toString() ??
              'Chưa có lịch sắp tới',
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.star_outline_rounded,
          label: 'Đánh giá',
          value: (profile['rating']?.toString().trim().isEmpty ?? true)
              ? 'Chưa có đánh giá'
              : profile['rating'].toString(),
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.sticky_note_2_outlined,
          label: 'Ghi chú vận hành',
          value: (profile['note']?.toString().trim().isEmpty ?? true)
              ? 'Chưa có ghi chú'
              : profile['note'].toString(),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_outlined, size: 17, color: AppColors.copper),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile['dataNote']?.toString() ??
                      'Số liệu hiệu suất được tổng hợp từ dữ liệu đã ghi nhận.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileMetrics extends StatelessWidget {
  const _ProfileMetrics({required this.profile});

  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Lịch hôm nay',
        '${_intValue(profile['todayAppointmentCount'])}',
        Icons.event_note_outlined,
      ),
      (
        'Dịch vụ tháng',
        '${_intValue(profile['monthServiceCount'])}',
        Icons.content_cut_rounded,
      ),
      (
        'Doanh thu DV',
        profile['monthRevenue']?.toString() ?? '0đ',
        Icons.payments_outlined,
      ),
      (
        'Hoa hồng ước tính',
        profile['estimatedCommission']?.toString() ?? '0đ',
        Icons.percent_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        const gap = 8.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              Container(
                key: metric.$1 == 'Doanh thu DV'
                    ? const Key('employee-profile-month-revenue')
                    : null,
                width: width,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.featureSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(metric.$3, size: 17, color: AppColors.copper),
                    const SizedBox(height: 7),
                    Text(
                      metric.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metric.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
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

class _EmployeeScheduleTab extends StatelessWidget {
  const _EmployeeScheduleTab({required this.profile});

  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context) {
    final today = _mapList(profile['todayAppointments']);
    final todayIds = today.map((row) => row['id']?.toString()).toSet();
    final upcoming = _mapList(profile['upcomingAppointments'])
        .where((row) => !todayIds.contains(row['id']?.toString()))
        .toList(growable: false);

    return ListView(
      key: const Key('employee-profile-schedule'),
      primary: false,
      padding: const EdgeInsets.all(14),
      children: [
        _SectionLabel(title: 'Hôm nay', count: today.length),
        const SizedBox(height: 8),
        if (today.isEmpty)
          const _InlineEmpty(
            icon: Icons.event_busy_outlined,
            text: 'Chưa có lịch hôm nay.',
          )
        else
          for (final row in today) ...[
            _AppointmentProfileRow(row: row),
            const SizedBox(height: 7),
          ],
        const SizedBox(height: 10),
        _SectionLabel(title: 'Sắp tới', count: upcoming.length),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          const _InlineEmpty(
            icon: Icons.event_available_outlined,
            text: 'Chưa có lịch sắp tới.',
          )
        else
          for (final row in upcoming) ...[
            _AppointmentProfileRow(row: row),
            const SizedBox(height: 7),
          ],
      ],
    );
  }
}

class _AppointmentProfileRow extends StatelessWidget {
  const _AppointmentProfileRow({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['timeRange']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  row['dateLabel']?.toString() ?? '',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['customerName']?.toString() ?? 'Khách',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  row['serviceName']?.toString() ?? 'Dịch vụ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PremiumStatusPill(label: status, tone: _appointmentStatusTone(status)),
        ],
      ),
    );
  }
}

class _EmployeePerformanceTab extends StatelessWidget {
  const _EmployeePerformanceTab({required this.profile});

  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context) {
    final topServices = _mapList(profile['topServices']);
    return ListView(
      key: const Key('employee-profile-performance'),
      primary: false,
      padding: const EdgeInsets.all(14),
      children: [
        _ProfileMetrics(profile: profile),
        const SizedBox(height: 14),
        _SectionLabel(title: 'Dịch vụ nổi bật tháng này', count: topServices.length),
        const SizedBox(height: 8),
        if (topServices.isEmpty)
          const _InlineEmpty(
            icon: Icons.query_stats_outlined,
            text: 'Chưa có dịch vụ đã thanh toán trong tháng.',
          )
        else
          for (var index = 0; index < topServices.length; index++) ...[
            _TopServiceRow(index: index + 1, row: topServices[index]),
            if (index < topServices.length - 1) const SizedBox(height: 7),
          ],
        const SizedBox(height: 14),
        PremiumInfoRow(
          icon: Icons.people_outline_rounded,
          label: 'Khách đã phục vụ tháng này',
          value: '${_intValue(profile['monthCustomerCount'])} khách',
        ),
        const PremiumDivider(indent: 42),
        PremiumInfoRow(
          icon: Icons.percent_rounded,
          label: 'Hoa hồng ước tính',
          value: profile['estimatedCommission']?.toString() ?? '0đ',
        ),
      ],
    );
  }
}

class _TopServiceRow extends StatelessWidget {
  const _TopServiceRow({required this.index, required this.row});

  final int index;
  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          PremiumIconBadge(
            icon: Icons.content_cut_rounded,
            size: 34,
            tone: index == 1 ? AppColors.copper : AppColors.info,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['title']?.toString() ?? 'Dịch vụ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${_intValue(row['quantity'])} lượt',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            row['revenueLabel']?.toString() ?? '0đ',
            style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _EmployeeHistoryTab extends StatelessWidget {
  const _EmployeeHistoryTab({required this.profile});

  final Map<String, Object?> profile;

  @override
  Widget build(BuildContext context) {
    final history = _mapList(profile['serviceHistory']);
    return ListView.separated(
      key: const Key('employee-profile-history'),
      primary: false,
      padding: const EdgeInsets.all(14),
      itemCount: history.isEmpty ? 1 : history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        if (history.isEmpty) {
          return const _InlineEmpty(
            icon: Icons.history_rounded,
            text: 'Chưa có lịch sử dịch vụ đã thanh toán.',
          );
        }
        final row = history[index];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['dateLabel']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      row['timeLabel']?.toString() ?? '',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['customerName']?.toString() ?? 'Khách',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${row['title']} ×${_intValue(row['quantity'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                row['revenueLabel']?.toString() ?? '0đ',
                style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        PremiumStatusPill(label: '$count', tone: AppColors.copper),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textMuted))),
        ],
      ),
    );
  }
}

Color _statusTone(String status) {
  return switch (status) {
    'Đang làm việc' => AppColors.success,
    'Sắp có lịch' => AppColors.warning,
    'Tạm nghỉ' => AppColors.textMuted,
    _ => AppColors.info,
  };
}

Color _appointmentStatusTone(String status) {
  return switch (status) {
    'Hoàn thành' => AppColors.success,
    'Đang làm' => AppColors.info,
    'Chờ xác nhận' => AppColors.warning,
    'Đã đặt' => AppColors.copper,
    _ => AppColors.textMuted,
  };
}

List<Map<String, Object?>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, Object?> _fallbackProfile(Map<String, Object?> employee) {
  return {
    ...employee,
    'todayAppointments': const <Map<String, Object?>>[],
    'upcomingAppointments': const <Map<String, Object?>>[],
    'serviceHistory': const <Map<String, Object?>>[],
    'topServices': const <Map<String, Object?>>[],
    'todayAppointmentCount': 0,
    'monthRevenueValue': 0,
    'monthRevenue': employee['monthlyRevenue']?.toString().trim().isNotEmpty == true
        ? employee['monthlyRevenue']
        : '0đ',
    'monthServiceCount': _intValue(employee['servicesDone']),
    'monthCustomerCount': 0,
    'estimatedCommission': employee['commission']?.toString() ?? 'KPI cố định',
    'nextAppointmentLabel': employee['todaySchedule']?.toString().trim().isNotEmpty == true
        ? employee['todaySchedule']
        : 'Chưa có lịch sắp tới',
    'dataNote': 'Backend demo chưa có dữ liệu giao dịch thật cho hồ sơ nhân viên.',
  };
}

class _EmployeeEditorDialog extends StatefulWidget {
  const _EmployeeEditorDialog({this.employee});

  final Map<String, Object?>? employee;

  @override
  State<_EmployeeEditorDialog> createState() => _EmployeeEditorDialogState();
}

class _EmployeeEditorDialogState extends State<_EmployeeEditorDialog> {
  static const _roleOptions = [
    'Stylist chính',
    'Barber',
    'Chăm sóc tóc',
    'Lễ tân',
  ];
  static const _statusOptions = [
    'Đang làm việc',
    'Sắp có lịch',
    'Tạm nghỉ',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _shiftController;
  late final TextEditingController _specialtyController;
  late final TextEditingController _commissionController;
  late final TextEditingController _ratingController;
  late final TextEditingController _noteController;
  late String _role;
  late String _status;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _nameController = TextEditingController(text: employee?['name']?.toString() ?? '');
    _phoneController = TextEditingController(text: employee?['phone']?.toString() ?? '');
    _shiftController = TextEditingController(
      text: employee?['shift']?.toString() ?? '09:00 - 18:00',
    );
    _specialtyController = TextEditingController(
      text: employee?['specialty']?.toString() ?? '',
    );
    _commissionController = TextEditingController(
      text: employee?['commission']?.toString() ?? '15%',
    );
    _ratingController = TextEditingController(
      text: employee?['rating']?.toString() ?? '',
    );
    _noteController = TextEditingController(text: employee?['note']?.toString() ?? '');
    _role = _roleOptions.contains(employee?['role'])
        ? employee!['role'].toString()
        : _roleOptions.first;
    _status = _statusOptions.contains(employee?['status'])
        ? employee!['status'].toString()
        : _statusOptions.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _shiftController.dispose();
    _specialtyController.dispose();
    _commissionController.dispose();
    _ratingController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.employee != null;
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(isEditing ? 'Sửa hồ sơ nhân viên' : 'Thêm nhân viên'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập họ tên'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _role,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Vai trò'),
                        items: _roleOptions
                            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) setState(() => _role = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Trạng thái'),
                        items: _statusOptions
                            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) setState(() => _status = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(labelText: 'Số điện thoại'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _shiftController,
                        decoration: const InputDecoration(labelText: 'Ca làm'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _specialtyController,
                  decoration: const InputDecoration(labelText: 'Chuyên môn'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _commissionController,
                        decoration: const InputDecoration(labelText: 'Hoa hồng / KPI'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ratingController,
                        decoration: const InputDecoration(labelText: 'Đánh giá'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Ghi chú vận hành'),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Lịch hôm nay, dịch vụ tháng và doanh thu được hệ thống tự tính từ dữ liệu thật.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Lưu hồ sơ' : 'Tạo nhân viên'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.employee;
    Navigator.of(context).pop(
      EmployeeUpsertInput(
        fullName: _nameController.text.trim(),
        role: _role,
        status: _status,
        phone: _phoneController.text.trim(),
        shift: _shiftController.text.trim(),
        specialty: _specialtyController.text.trim(),
        commissionLabel: _commissionController.text.trim(),
        todaySchedule: existing?['todaySchedule']?.toString() ?? '',
        servicesDone: _intValue(existing?['servicesDone']),
        monthlyRevenue: existing?['monthlyRevenue']?.toString() ?? '',
        rating: _ratingController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }
}
