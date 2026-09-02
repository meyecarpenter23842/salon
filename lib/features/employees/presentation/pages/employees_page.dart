import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/employee_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final employeeSearchQueryProvider = StateProvider<String>((ref) => '');

final employeeRoleFilterProvider = StateProvider<String>((ref) => 'Tất cả');

final selectedEmployeeIndexProvider = StateProvider<int>((ref) => 0);

final filteredEmployeesProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) async {
  final employees = await ref
      .watch(employeesRepositoryProvider)
      .fetchEmployeesView();
  final query = ref.watch(employeeSearchQueryProvider).trim().toLowerCase();
  final role = ref.watch(employeeRoleFilterProvider);

  return employees.where((item) {
    final matchesRole = role == 'Tất cả' || item['role'] == role;
    final matchesQuery =
        query.isEmpty ||
        [
          item['name'],
          item['role'],
          item['specialty'],
          item['phone'],
          item['status'],
        ].any((value) => value.toString().toLowerCase().contains(query));

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
    builder: (dialogContext) => _EmployeeEditorDialog(employee: employee),
  );

  if (input == null || !context.mounted) {
    return;
  }

  final saved = await ref
      .read(employeesRepositoryProvider)
      .saveEmployee(input, existingId: employee?['id']?.toString());

  if (!context.mounted) {
    return;
  }

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

  if (!context.mounted) {
    return;
  }

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
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được nhân sự: $error')),
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
    final selectedEmployee = items.isEmpty ? null : items[effectiveIndex];
    final selectedRole = ref.watch(employeeRoleFilterProvider);

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 520;

        Widget buildBody() {
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1180;

              if (compact) {
                return Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _EmployeeListPanel(
                        items: items,
                        selectedIndex: effectiveIndex,
                      ),
                    ),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(
                      flex: 4,
                      child: _EmployeeDetailPanel(employee: selectedEmployee),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _EmployeeListPanel(
                      items: items,
                      selectedIndex: effectiveIndex,
                    ),
                  ),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(
                    flex: 4,
                    child: _EmployeeDetailPanel(employee: selectedEmployee),
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
              const _EmployeesHero(),
              const SizedBox(height: AppDimens.heroGap),
              _EmployeesSummaryRow(items: items),
              const SizedBox(height: AppDimens.sectionGap),
              _EmployeesToolbar(selectedRole: selectedRole),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 680, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _EmployeesHero(),
            const SizedBox(height: AppDimens.heroGap),
            _EmployeesSummaryRow(items: items),
            const SizedBox(height: AppDimens.sectionGap),
            _EmployeesToolbar(selectedRole: selectedRole),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _EmployeesHero extends StatelessWidget {
  const _EmployeesHero();

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nhân sự',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text(
            'Workflow nhân sự desktop-first: danh sách team, lọc theo vai trò, trạng thái l� m viá»‡c và  panel chi tiết để chuẩn bị cho bước phân ca, hoa hồng và  CRUD thật.',
            style: TextStyle(color: AppColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _EmployeesSummaryRow extends StatelessWidget {
  const _EmployeesSummaryRow({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Widget build(BuildContext context) {
    final activeCount = items
        .where((item) => item['status'] == 'Đang làm việc')
        .length;
    final stylistCount = items
        .where((item) => item['role'].toString().contains('Stylist'))
        .length;
    final supportCount = items
        .where((item) => !item['role'].toString().contains('Stylist'))
        .length;

    final cards = [
      _EmployeeSummaryCard(label: 'Tá»•ng nhân sự', value: '${items.length}'),
      _EmployeeSummaryCard(label: 'Đang làm việc', value: '$activeCount'),
      _EmployeeSummaryCard(label: 'Stylist chính', value: '$stylistCount'),
      _EmployeeSummaryCard(label: 'Hỗ trợ vận hành', value: '$supportCount'),
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

        if (constraints.maxWidth < 1280) {
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

class _EmployeeSummaryCard extends StatelessWidget {
  const _EmployeeSummaryCard({required this.label, required this.value});

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

class _EmployeesToolbar extends ConsumerWidget {
  const _EmployeesToolbar({required this.selectedRole});

  final String selectedRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const roles = [
      'Tất cả',
      'Stylist chính',
      'Barber',
      'Chăm sóc tóc',
      'Lễ tân',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: ref.watch(employeeSearchQueryProvider),
                onChanged: (value) {
                  ref.read(employeeSearchQueryProvider.notifier).state = value;
                  ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText:
                      'Tìm theo tên, vai trò, chuyên môn, số điện thoại hoặc trạng thái',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () => _openEmployeeEditor(context, ref),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Thêm nhân sự'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: roles
              .map(
                (item) => FilterChip(
                  label: Text(item),
                  selected: item == selectedRole,
                  onSelected: (_) {
                    ref.read(employeeRoleFilterProvider.notifier).state = item;
                    ref.read(selectedEmployeeIndexProvider.notifier).state = 0;
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _EmployeeListPanel extends ConsumerWidget {
  const _EmployeeListPanel({required this.items, required this.selectedIndex});

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
                    'Danh sách nhân sự',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${items.length} hồ sơ',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Không có nhân sự phù há»£p vá»›i bá»™ lọc hiá»‡n táº¡i.',
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemCount: items.length,
                  itemBuilder: (context, index) => _EmployeeListTile(
                    employee: items[index],
                    selected: index == selectedIndex,
                    onTap: () {
                      ref.read(selectedEmployeeIndexProvider.notifier).state =
                          index;
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeListTile extends StatelessWidget {
  const _EmployeeListTile({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  final Map<String, Object?> employee;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? AppColors.copper : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          onTap: onTap,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.avatarFill,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.copper),
            ),
            alignment: Alignment.center,
            child: Text(
              employee['initials'].toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(
            employee['name'].toString(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${employee['role']} • ${employee['shift']}'),
                const SizedBox(height: 4),
                Text(
                  employee['specialty'].toString(),
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusLabel(text: employee['status'].toString()),
              const SizedBox(height: 6),
              Text(
                employee['todaySchedule'].toString(),
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeDetailPanel extends ConsumerWidget {
  const _EmployeeDetailPanel({required this.employee});

  final Map<String, Object?>? employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (employee == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chá»n má»™t nhân sự để xem chi tiết.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.copper),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            employee!['initials'].toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee!['name'].toString(),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${employee!['role']} • ${employee!['phone']}',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          label: 'Ca làm',
                          value: employee!['shift'].toString(),
                        ),
                        _MetricCard(
                          label: 'Hoa hồng',
                          value: employee!['commission'].toString(),
                        ),
                        _MetricCard(
                          label: 'Đánh giá',
                          value: employee!['rating'].toString(),
                        ),
                        _MetricCard(
                          label: 'Dịch vụ tháng',
                          value: '${employee!['servicesDone']}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Chuyên môn',
                      content: employee!['specialty'].toString(),
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      title: 'Ghi chú vận hành',
                      content: employee!['note'].toString(),
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      title: 'Hiệu suất tháng',
                      content:
                          '${employee!['monthlyRevenue']} • ${employee!['todaySchedule']}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _openEmployeeEditor(context, ref, employee: employee),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Sửa hồ sơ'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _updateEmployeeStatus(context, ref, employee!),
                    icon: const Icon(Icons.sync_alt_outlined),
                    label: const Text('Đổi trạng thái'),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
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

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (text) {
      case 'Đang làm việc':
        color = AppColors.success;
        break;
      case 'Sắp có lịch':
        color = AppColors.copper;
        break;
      case 'Tạm nghỉ':
        color = AppColors.textMuted;
        break;
      default:
        color = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
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
                          if (value != null) {
                            setState(() {
                              _role = value;
                            });
                          }
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
                                child: Text(
                                  item,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _status = value;
                            });
                          }
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
                          labelText: 'Sá»‘ điện thoáº¡i',
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
                        controller: _todayScheduleController,
                        decoration: const InputDecoration(
                          labelText: 'Lịch hôm nay',
                        ),
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
                        decoration: const InputDecoration(
                          labelText: 'Dịch vụ tháng',
                        ),
                        keyboardType: TextInputType.number,
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
                  controller: _monthlyRevenueController,
                  decoration: const InputDecoration(
                    labelText: 'Doanh thu tháng',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú vận hành',
                  ),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
