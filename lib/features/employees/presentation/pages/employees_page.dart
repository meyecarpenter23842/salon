import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/employee_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');
final employeeRoleFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final selectedEmployeeIndexProvider = StateProvider<int>((ref) => 0);

final filteredEmployeesProvider = FutureProvider<List<Map<String, Object?>>>((ref) async {
  final employees = await ref.watch(employeesRepositoryProvider).fetchEmployeesView();
  final query = ref.watch(employeeSearchQueryProvider).trim().toLowerCase();
  final role = ref.watch(employeeRoleFilterProvider);

  return employees.where((item) {
    final matchesRole = role == 'Tất cả' || item['role'] == role;
    final matchesQuery = query.isEmpty ||
        [item['name'], item['role'], item['specialty'], item['phone'], item['status']]
            .any((value) => value.toString().toLowerCase().contains(query));
    return matchesRole && matchesQuery;
  }).toList();
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

  final saved = await ref
      .read(employeesRepositoryProvider)
      .saveEmployee(input, existingId: employee?['id']?.toString());
  if (!context.mounted) return;

  ref.read(employeeSearchQueryProvider.notifier).state =
      saved['name']?.toString() ?? '';
  ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
  ref.invalidate(filteredEmployeesProvider);
  ref.invalidate(employeesViewProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        employee == null
            ? 'Đã thêm nhân sự ${saved['name']}'
            : 'Đã cập nhật ${saved['name']}',
      ),
    ),
  );
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

  final updated = await ref
      .read(employeesRepositoryProvider)
      .updateEmployeeStatus(employee['id']!.toString(), nextStatus);
  if (!context.mounted) return;

  ref.read(employeeSearchQueryProvider.notifier).state =
      updated['name']?.toString() ?? '';
  ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
  ref.invalidate(filteredEmployeesProvider);
  ref.invalidate(employeesViewProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Đã chuyển ${updated['name']} sang trạng thái ${updated['status']}',
      ),
    ),
  );
}

class EmployeesPage extends ConsumerWidget {
  const EmployeesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(filteredEmployeesProvider);
    return employees.when(
      data: (items) => _EmployeesView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Không tải được nhân sự',
        message: '$error',
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
    final effectiveIndex =
        items.isEmpty ? 0 : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final active =
        items.where((item) => item['status'] == 'Đang làm việc').length;
    final upcoming =
        items.where((item) => item['status'] == 'Sắp có lịch').length;
    final stylists = items
        .where((item) => item['role'].toString().contains('Stylist'))
        .length;

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 760;

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumSectionCard(
              key: const Key('employees-premium-header'),
              child: PremiumPageHeader(
                icon: Icons.badge_outlined,
                eyebrow: 'Đội ngũ salon',
                title: 'Nhân viên',
                subtitle:
                    'Theo dõi vai trò, ca làm, chuyên môn, hiệu suất và trạng thái làm việc của từng thành viên.',
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
            const SizedBox(height: 14),
            _EmployeeStats(
              total: items.length,
              active: active,
              upcoming: upcoming,
              stylists: stylists,
            ),
            const SizedBox(height: 14),
            const _EmployeesToolbar(),
            const SizedBox(height: 14),
            if (shortViewport)
              SizedBox(
                height: 720,
                child: _EmployeeWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              )
            else
              Expanded(
                child: _EmployeeWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              ),
          ],
        );

        if (shortViewport) {
          return ListView(
            key: const Key('employees-premium-workspace'),
            primary: false,
            children: [content],
          );
        }

        return KeyedSubtree(
          key: const Key('employees-premium-workspace'),
          child: content,
        );
      },
    );
  }
}

class _EmployeeStats extends StatelessWidget {
  const _EmployeeStats({
    required this.total,
    required this.active,
    required this.upcoming,
    required this.stylists,
  });

  final int total;
  final int active;
  final int upcoming;
  final int stylists;

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
        icon: Icons.content_cut_rounded,
        label: 'Stylist chính',
        value: '$stylists',
        tone: AppColors.info,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const gap = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
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

    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: ref.watch(employeeSearchQueryProvider),
            onChanged: (value) {
              ref.read(employeeSearchQueryProvider.notifier).state = value;
              ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText:
                  'Tìm tên, vai trò, chuyên môn, số điện thoại hoặc trạng thái',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in roles)
                FilterChip(
                  label: Text(role),
                  selected: role == selectedRole,
                  showCheckmark: false,
                  onSelected: (_) {
                    ref.read(employeeRoleFilterProvider.notifier).state = role;
                    ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          ),
        ],
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
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(
        selected?['id']?.toString() ?? 'employee-empty',
      ),
      child: _EmployeeDetail(employee: selected),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1040) {
          return ListView(
            primary: false,
            children: [
              SizedBox(
                height: 300,
                child: _EmployeeList(
                  items: items,
                  selectedIndex: selectedIndex,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 430, child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _EmployeeList(
                items: items,
                selectedIndex: selectedIndex,
              ),
            ),
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
      title: 'Danh sách đội ngũ',
      subtitle: '${items.length} hồ sơ phù hợp bộ lọc',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Không có nhân sự phù hợp',
              message: 'Thử đổi bộ lọc hoặc thêm nhân sự mới.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 54),
              itemBuilder: (context, index) {
                final employee = items[index];
                final isSelected = index == selectedIndex;
                final status = employee['status']?.toString() ?? '';
                final tone = _statusTone(status);

                return PremiumInteractiveSurface(
                  selected: isSelected,
                  onTap: () {
                    ref.read(selectedEmployeeIndexProvider.notifier).state =
                        index;
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 300;
                      final identity = Column(
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
                          const SizedBox(height: 4),
                          Text(
                            '${employee['role']} • ${employee['shift']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      );

                      if (compact) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  identity,
                                  const SizedBox(height: 7),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 5,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      PremiumStatusPill(
                                        label: status,
                                        tone: tone,
                                      ),
                                      Text(
                                        employee['todaySchedule']?.toString() ??
                                            '',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          PremiumIconBadge(
                            icon: Icons.person_outline_rounded,
                            size: 38,
                            tone: tone,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: identity),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              PremiumStatusPill(
                                label: status,
                                tone: tone,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                employee['todaySchedule']?.toString() ?? '',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
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
          message: 'Ca làm, chuyên môn và hiệu suất sẽ hiển thị ở đây.',
        ),
      );
    }

    final status = current['status']?.toString() ?? '';
    final tone = _statusTone(status);

    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 320;
                final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${current['role']} • ${current['phone']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PremiumIconBadge(
                            icon: Icons.person_rounded,
                            size: 46,
                            tone: tone,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: identity),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PremiumStatusPill(label: status, tone: tone),
                    ],
                  );
                }

                return Row(
                  children: [
                    PremiumIconBadge(
                      icon: Icons.person_rounded,
                      size: 46,
                      tone: tone,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: identity),
                    const SizedBox(width: 10),
                    PremiumStatusPill(label: status, tone: tone),
                  ],
                );
              },
            ),
          ),
          const PremiumDivider(),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _EmployeeMetricStrip(employee: current),
                  const SizedBox(height: 8),
                  PremiumInfoRow(
                    icon: Icons.schedule_outlined,
                    label: 'Ca làm',
                    value: current['shift']?.toString() ?? '',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Chuyên môn',
                    value: current['specialty']?.toString() ?? '',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.percent_rounded,
                    label: 'Hoa hồng / KPI',
                    value: current['commission']?.toString() ?? '',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.trending_up_rounded,
                    label: 'Hiệu suất tháng',
                    value:
                        '${current['monthlyRevenue']} • ${current['todaySchedule']}',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Ghi chú vận hành',
                    value: (current['note']?.toString().isEmpty ?? true)
                        ? 'Chưa có ghi chú'
                        : current['note'].toString(),
                  ),
                ],
              ),
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final editButton = FilledButton.icon(
                  onPressed: () => _openEmployeeEditor(
                    context,
                    ref,
                    employee: current,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa hồ sơ'),
                );
                final statusButton = OutlinedButton.icon(
                  onPressed: () =>
                      _updateEmployeeStatus(context, ref, current),
                  icon: const Icon(Icons.sync_alt_outlined),
                  label: const Text('Đổi trạng thái'),
                );

                if (constraints.maxWidth < 390) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      editButton,
                      const SizedBox(height: 8),
                      statusButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: editButton),
                    const SizedBox(width: 8),
                    Expanded(child: statusButton),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeMetricStrip extends StatelessWidget {
  const _EmployeeMetricStrip({required this.employee});

  final Map<String, Object?> employee;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Dịch vụ tháng', '${employee['servicesDone'] ?? 0}'),
      ('Đánh giá', employee['rating']?.toString() ?? '-'),
      ('Hoa hồng', employee['commission']?.toString() ?? '-'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(
                    metrics[index].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    metrics[index].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (index < metrics.length - 1)
              Container(
                width: 1,
                height: 32,
                color: AppColors.workspaceDivider,
              ),
          ],
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
  late final TextEditingController _todayScheduleController;
  late final TextEditingController _servicesDoneController;
  late final TextEditingController _monthlyRevenueController;
  late final TextEditingController _ratingController;
  late final TextEditingController _noteController;
  late String _role;
  late String _status;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _nameController =
        TextEditingController(text: employee?['name']?.toString() ?? '');
    _phoneController =
        TextEditingController(text: employee?['phone']?.toString() ?? '');
    _shiftController = TextEditingController(
      text: employee?['shift']?.toString() ?? '09:00 - 18:00',
    );
    _specialtyController = TextEditingController(
      text: employee?['specialty']?.toString() ?? '',
    );
    _commissionController = TextEditingController(
      text: employee?['commission']?.toString() ?? '15%',
    );
    _todayScheduleController = TextEditingController(
      text: employee?['todaySchedule']?.toString() ?? '0 lịch hôm nay',
    );
    _servicesDoneController = TextEditingController(
      text: '${employee?['servicesDone'] ?? 0}',
    );
    _monthlyRevenueController = TextEditingController(
      text: employee?['monthlyRevenue']?.toString() ?? '0đ',
    );
    _ratingController = TextEditingController(
      text: employee?['rating']?.toString() ?? '4.8',
    );
    _noteController =
        TextEditingController(text: employee?['note']?.toString() ?? '');
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
    _todayScheduleController.dispose();
    _servicesDoneController.dispose();
    _monthlyRevenueController.dispose();
    _ratingController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.employee != null;

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(isEditing ? 'Sửa nhân sự' : 'Thêm nhân sự'),
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
                                child: Text(
                                  item,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
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
                        decoration:
                            const InputDecoration(labelText: 'Trạng thái'),
                        items: _statusOptions
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
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
                        decoration:
                            const InputDecoration(labelText: 'Số điện thoại'),
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
                        decoration:
                            const InputDecoration(labelText: 'Hoa hồng / KPI'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _todayScheduleController,
                        decoration:
                            const InputDecoration(labelText: 'Lịch hôm nay'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _servicesDoneController,
                        decoration:
                            const InputDecoration(labelText: 'Dịch vụ tháng'),
                        keyboardType: TextInputType.number,
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
                  controller: _monthlyRevenueController,
                  decoration:
                      const InputDecoration(labelText: 'Doanh thu tháng'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration:
                      const InputDecoration(labelText: 'Ghi chú vận hành'),
                  maxLines: 3,
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
          child: Text(isEditing ? 'Lưu nhân sự' : 'Tạo nhân sự'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      EmployeeUpsertInput(
        fullName: _nameController.text.trim(),
        role: _role,
        status: _status,
        phone: _phoneController.text.trim(),
        shift: _shiftController.text.trim(),
        specialty: _specialtyController.text.trim(),
        commissionLabel: _commissionController.text.trim(),
        todaySchedule: _todayScheduleController.text.trim(),
        servicesDone: int.tryParse(_servicesDoneController.text.trim()) ?? 0,
        monthlyRevenue: _monthlyRevenueController.text.trim(),
        rating: _ratingController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }
}
