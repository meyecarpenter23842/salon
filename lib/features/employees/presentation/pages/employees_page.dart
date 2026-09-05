import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/employee_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/employee_profile_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/compact_management.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');
final employeeRoleFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final employeeStatusFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final selectedEmployeeIndexProvider = StateProvider<int>((ref) => 0);

final employeeProfileRepositoryProvider = Provider<EmployeeProfileRepository?>((
  ref,
) {
  final repository = ref.watch(employeesRepositoryProvider);
  return repository is EmployeeProfileRepository
      ? repository as EmployeeProfileRepository
      : null;
});

final employeeProfileProvider =
    FutureProvider.family<Map<String, Object?>?, String>((
      ref,
      employeeId,
    ) async {
      final repository = ref.watch(employeeProfileRepositoryProvider);
      if (repository == null) return null;
      return repository.fetchEmployeeProfile(employeeId);
    });

final filteredEmployeesProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final employees = await ref
      .watch(employeesRepositoryProvider)
      .fetchEmployeesView();
  final query = ref.watch(employeeSearchQueryProvider).trim().toLowerCase();
  final role = ref.watch(employeeRoleFilterProvider);
  final status = ref.watch(employeeStatusFilterProvider);

  return employees
      .where((item) {
        final matchesRole = role == 'Tất cả' || item['role'] == role;
        final matchesStatus = status == 'Tất cả' || item['status'] == status;
        final matchesQuery =
            query.isEmpty ||
            [
              item['name'],
              item['role'],
              item['specialty'],
              item['phone'],
              item['status'],
            ].any((value) => value.toString().toLowerCase().contains(query));
        return matchesRole && matchesStatus && matchesQuery;
      })
      .toList(growable: false);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Không lưu được nhân sự: $error')));
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
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final allEmployees = ref.watch(employeesViewProvider).valueOrNull ?? items;
    final active = allEmployees
        .where((item) => item['status'] == 'Đang làm việc')
        .length;
    final upcoming = allEmployees
        .where((item) => item['status'] == 'Sắp có lịch')
        .length;
    final resting = allEmployees
        .where((item) => item['status'] == 'Tạm nghỉ')
        .length;

    return KeyedSubtree(
      key: const Key('employees-premium-workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompactManagementHeader(
            key: const Key('employees-premium-header'),
            title: 'Nhân viên',
            subtitle:
                'Đội ngũ, ca làm, lịch hẹn và hiệu suất trong một workspace.',
            actionLabel: 'Thêm nhân sự',
            actionIcon: Icons.person_add_alt_1_outlined,
            onAction: () => _openEmployeeEditor(context, ref),
          ),
          const SizedBox(height: 12),
          _EmployeesToolbar(
            total: allEmployees.length,
            active: active,
            upcoming: upcoming,
            resting: resting,
          ),
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

class _EmployeesToolbar extends ConsumerWidget {
  const _EmployeesToolbar({
    required this.total,
    required this.active,
    required this.upcoming,
    required this.resting,
  });

  final int total;
  final int active;
  final int upcoming;
  final int resting;

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
    final selectedStatus = ref.watch(employeeStatusFilterProvider);
    final query = ref.watch(employeeSearchQueryProvider);
    final statuses = [
      ('Tất cả', total),
      ('Đang làm việc', active),
      ('Sắp có lịch', upcoming),
      ('Tạm nghỉ', resting),
    ];

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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth >= 760)
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: 220, child: role),
                ],
              )
            else ...[
              search,
              const SizedBox(height: 8),
              role,
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final status in statuses)
                  FilterChip(
                    label: Text('${status.$1} ${status.$2}'),
                    selected: selectedStatus == status.$1,
                    showCheckmark: false,
                    onSelected: (_) {
                      ref.read(employeeStatusFilterProvider.notifier).state =
                          status.$1;
                      ref.read(selectedEmployeeIndexProvider.notifier).state =
                          0;
                    },
                  ),
              ],
            ),
          ],
        );
      },
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
          transitionKey: ValueKey(
            selected?['id']?.toString() ?? 'employee-empty',
          ),
          child: _EmployeeDetail(employee: selected),
        );

        if (constraints.maxWidth < 760) {
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
                    ref.read(selectedEmployeeIndexProvider.notifier).state =
                        index;
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
    final today = _mapList(profile['todayAppointments']);
    final upcoming = _mapList(profile['upcomingAppointments']);
    final topServices = _mapList(profile['topServices']);
    final history = _mapList(profile['serviceHistory']);
    final nextAppointment = today.isNotEmpty
        ? today.first
        : upcoming.isNotEmpty
        ? upcoming.first
        : null;

    return PremiumSectionCard(
      key: const Key('employee-profile-card'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
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
                      const SizedBox(height: 3),
                      Text(
                        profile['specialty']?.toString() ??
                            'Chưa thiết lập chuyên môn',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                PremiumStatusPill(label: status, tone: tone),
                const SizedBox(width: 6),
                IconButton.outlined(
                  key: const Key('employee-profile-edit-action'),
                  tooltip: 'Sửa hồ sơ',
                  onPressed: () =>
                      _openEmployeeEditor(context, ref, employee: baseEmployee),
                  icon: const Icon(Icons.edit_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Thêm thao tác',
                  onSelected: (value) {
                    if (value == 'status') {
                      _updateEmployeeStatus(context, ref, baseEmployee);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'status',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.sync_alt_outlined),
                        title: Text('Đổi trạng thái'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const PremiumDivider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          Icons.event_note_outlined,
                          'Lịch hôm nay',
                          '${_intValue(profile['todayAppointmentCount'])}',
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          Icons.payments_outlined,
                          'Doanh thu tháng',
                          profile['monthRevenue']?.toString() ?? '0đ',
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          Icons.content_cut_rounded,
                          'Dịch vụ',
                          '${_intValue(profile['monthServiceCount'])}',
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          Icons.people_outline_rounded,
                          'Khách',
                          '${_intValue(profile['monthCustomerCount'])}',
                        ),
                      ),
                      Expanded(
                        child: _metric(
                          Icons.percent_rounded,
                          'Hoa hồng',
                          profile['estimatedCommission']?.toString() ?? '0đ',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final next = _nextAppointmentCard(
                          context,
                          nextAppointment,
                          [...today, ...upcoming],
                        );
                        final top = _topServicesCard(topServices);
                        if (constraints.maxWidth < 720) {
                          return Column(
                            children: [
                              Expanded(child: next),
                              const SizedBox(height: 8),
                              Expanded(child: top),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 11, child: next),
                            const SizedBox(width: 8),
                            Expanded(flex: 9, child: top),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(height: 142, child: _historyCard(context, history)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.copper),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextAppointmentCard(
    BuildContext context,
    Map<String, Object?>? next,
    List<Map<String, Object?>> appointments,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        if (compact) {
          final summary = next == null
              ? (profile['nextAppointmentLabel']?.toString() ??
                    'Chưa có lịch sắp tới')
              : '${next['timeRange']?.toString() ?? ''} · ${next['customerName']?.toString() ?? 'Khách'} · ${next['serviceName']?.toString() ?? 'Dịch vụ'}';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.featureSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 16,
                  color: AppColors.copper,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lịch tiếp theo · $summary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                if (appointments.isNotEmpty)
                  IconButton(
                    tooltip: 'Xem lịch',
                    onPressed: () => _showAppointments(context, appointments),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 18,
                    color: AppColors.copper,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Lịch tiếp theo',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: appointments.isEmpty
                        ? null
                        : () => _showAppointments(context, appointments),
                    child: const Text('Xem lịch'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (next == null)
                Text(
                  profile['nextAppointmentLabel']?.toString() ??
                      'Chưa có lịch sắp tới.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else ...[
                Text(
                  next['timeRange']?.toString() ?? '',
                  style: TextStyle(
                    color: AppColors.copper,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  next['customerName']?.toString() ?? 'Khách',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  next['serviceName']?.toString() ?? 'Dịch vụ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PremiumStatusPill(
                    label: next['status']?.toString() ?? '',
                    tone: _appointmentStatusTone(
                      next['status']?.toString() ?? '',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _topServicesCard(List<Map<String, Object?>> services) {
    final rows = services.take(3).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        if (compact) {
          final summary = rows.isEmpty
              ? 'Chưa có dữ liệu'
              : '${rows.first['title']?.toString() ?? 'Dịch vụ'} · ${_intValue(rows.first['quantity'])} lượt';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.featureSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.content_cut_rounded,
                  size: 16,
                  color: AppColors.copper,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Top dịch vụ · $summary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.content_cut_rounded,
                    size: 18,
                    color: AppColors.copper,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Top dịch vụ tháng này',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Text(
                  'Chưa có dữ liệu dịch vụ.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                )
              else
                for (var index = 0; index < rows.length; index++) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}.',
                          style: TextStyle(
                            color: AppColors.copper,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rows[index]['title']?.toString() ?? 'Dịch vụ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_intValue(rows[index]['quantity'])} lượt',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  if (index < rows.length - 1) const SizedBox(height: 6),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _historyCard(
    BuildContext context,
    List<Map<String, Object?>> history,
  ) {
    final rows = history.take(2).toList(growable: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 18, color: AppColors.copper),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Lịch sử phục vụ gần đây',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: history.isEmpty
                    ? null
                    : () => _showHistory(context, history),
                child: Text('Xem tất cả (${history.length})'),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (rows.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chưa có lịch sử dịch vụ đã thanh toán.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
              ),
            )
          else
            for (var index = 0; index < rows.length; index++) ...[
              Expanded(child: _historyRow(rows[index])),
              if (index < rows.length - 1) const PremiumDivider(),
            ],
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, Object?> row) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '${row['dateLabel'] ?? ''} ${row['timeLabel'] ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${row['customerName'] ?? 'Khách'} • ${row['title'] ?? 'Dịch vụ'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          row['revenueLabel']?.toString() ?? '0đ',
          style: TextStyle(
            color: AppColors.copper,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Future<void> _showHistory(
    BuildContext context,
    List<Map<String, Object?>> history,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lịch sử phục vụ'),
        content: SizedBox(
          width: 760,
          height: 480,
          child: ListView.separated(
            itemCount: history.length,
            separatorBuilder: (_, _) => const PremiumDivider(),
            itemBuilder: (_, index) =>
                SizedBox(height: 50, child: _historyRow(history[index])),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppointments(
    BuildContext context,
    List<Map<String, Object?>> appointments,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lịch nhân viên'),
        content: SizedBox(
          width: 760,
          height: 480,
          child: ListView.separated(
            itemCount: appointments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) =>
                _AppointmentProfileRow(row: appointments[index]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
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
          PremiumStatusPill(
            label: status,
            tone: _appointmentStatusTone(status),
          ),
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
    'monthRevenue':
        employee['monthlyRevenue']?.toString().trim().isNotEmpty == true
        ? employee['monthlyRevenue']
        : '0đ',
    'monthServiceCount': _intValue(employee['servicesDone']),
    'monthCustomerCount': 0,
    'estimatedCommission': employee['commission']?.toString() ?? 'KPI cố định',
    'nextAppointmentLabel':
        employee['todaySchedule']?.toString().trim().isNotEmpty == true
        ? employee['todaySchedule']
        : 'Chưa có lịch sắp tới',
    'dataNote':
        'Backend demo chưa có dữ liệu giao dịch thật cho hồ sơ nhân viên.',
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
  static const _statusOptions = ['Đang làm việc', 'Sắp có lịch', 'Tạm nghỉ'];

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
    _nameController = TextEditingController(
      text: employee?['name']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: employee?['phone']?.toString() ?? '',
    );
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
    _noteController = TextEditingController(
      text: employee?['note']?.toString() ?? '',
    );
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
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
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
                        decoration: const InputDecoration(
                          labelText: 'Trạng thái',
                        ),
                        items: _statusOptions
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
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
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại',
                        ),
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
                        decoration: const InputDecoration(
                          labelText: 'Hoa hồng / KPI',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ratingController,
                        decoration: const InputDecoration(
                          labelText: 'Đánh giá',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú vận hành',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Lịch hôm nay, dịch vụ tháng và doanh thu được hệ thống tự tính từ dữ liệu thật.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10.5,
                    ),
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
