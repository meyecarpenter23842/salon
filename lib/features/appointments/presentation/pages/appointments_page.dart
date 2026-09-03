import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/appointment_upsert_input.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final appointmentStatusFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final appointmentDayFilterProvider = StateProvider<String>((ref) => 'Hôm nay');
final appointmentSearchQueryProvider = StateProvider<String>((ref) => '');
final appointmentBoardFilterProvider = StateProvider<String>((ref) => 'Ngày');
final selectedAppointmentIndexProvider = StateProvider<int>((ref) => 0);

final appointmentEmployeesProvider = FutureProvider<List<Map<String, Object?>>>((ref) {
  return ref.watch(employeesRepositoryProvider).fetchEmployeesView();
});

final filteredAppointmentsProvider = FutureProvider<List<AppointmentEntry>>((ref) async {
  final allItems = await ref.watch(appointmentsRepositoryProvider).fetchAppointmentsView();
  final status = ref.watch(appointmentStatusFilterProvider);
  final day = ref.watch(appointmentDayFilterProvider);
  final query = ref.watch(appointmentSearchQueryProvider).trim().toLowerCase();

  return allItems.where((item) {
    final matchesStatus = status == 'Tất cả' || item.status == status;
    final matchesDay = day == 'Tất cả' || item.dateLabel == day;
    final matchesQuery = query.isEmpty || [
      item.customerName,
      item.serviceName,
      item.staffName,
      item.customerPhone,
    ].any((value) => value.toString().toLowerCase().contains(query));
    return matchesStatus && matchesDay && matchesQuery;
  }).toList();
});

Future<void> _openAppointmentEditor(
  BuildContext context,
  WidgetRef ref, {
  AppointmentEntry? appointment,
}) async {
  final customers = await ref.read(customersRepositoryProvider).fetchCustomersView();
  final services = await ref.read(servicesRepositoryProvider).fetchServicesView();
  final employees = await ref.read(employeesRepositoryProvider).fetchEmployeesView();
  if (!context.mounted) return;

  final input = await showDialog<AppointmentUpsertInput>(
    context: context,
    builder: (_) => _AppointmentEditorDialog(
      appointment: appointment,
      customers: customers,
      services: services,
      employees: employees,
    ),
  );
  if (input == null || !context.mounted) return;

  AppointmentEntry savedAppointment;
  try {
    savedAppointment = await ref
        .read(appointmentsRepositoryProvider)
        .saveAppointment(input, existingId: appointment?.id);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }

  if (!context.mounted) return;
  final viewMode = ref.read(appointmentBoardFilterProvider);
  ref.read(appointmentDayFilterProvider.notifier).state = savedAppointment.dateLabel;
  if (viewMode == 'Ngày') {
    ref.read(appointmentSearchQueryProvider.notifier).state = '';
    ref.read(appointmentStatusFilterProvider.notifier).state = 'Tất cả';
  } else {
    ref.read(appointmentSearchQueryProvider.notifier).state = savedAppointment.customerName;
    ref.read(appointmentStatusFilterProvider.notifier).state = savedAppointment.status;
  }
  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  ref.invalidate(filteredAppointmentsProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        appointment == null
            ? 'Đã tạo lịch cho ${savedAppointment.customerName}'
            : 'Đã cập nhật lịch cho ${savedAppointment.customerName}',
      ),
    ),
  );
}

Future<void> _updateAppointmentStatus(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  final nextStatus = _nextStatus(appointment.status);
  if (nextStatus == null) return;

  final updated = await ref
      .read(appointmentsRepositoryProvider)
      .updateAppointmentStatus(appointment.id, nextStatus);
  if (!context.mounted) return;

  if (ref.read(appointmentBoardFilterProvider) == 'Danh sách') {
    ref.read(appointmentSearchQueryProvider.notifier).state = updated.customerName;
    ref.read(appointmentDayFilterProvider.notifier).state = updated.dateLabel;
    ref.read(appointmentStatusFilterProvider.notifier).state = updated.status;
    ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  }
  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã chuyển lịch sang trạng thái ${updated.status}')),
  );
}

Future<void> _undoAppointmentComplete(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  await ref
      .read(appointmentsRepositoryProvider)
      .updateAppointmentStatus(appointment.id, 'Đang làm');
  if (!context.mounted) return;
  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Đã hoàn tác về trạng thái Đang làm')),
  );
}

Future<void> _cancelAppointment(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  final shouldCancel = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xác nhận hủy lịch'),
      content: Text('Đánh dấu lịch của ${appointment.customerName} là Đã hủy?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Giữ lịch'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Hủy lịch'),
        ),
      ],
    ),
  );
  if (shouldCancel != true) return;

  final updated = await ref
      .read(appointmentsRepositoryProvider)
      .updateAppointmentStatus(appointment.id, 'Đã hủy');
  if (!context.mounted) return;

  if (ref.read(appointmentBoardFilterProvider) == 'Danh sách') {
    ref.read(appointmentSearchQueryProvider.notifier).state = updated.customerName;
    ref.read(appointmentDayFilterProvider.notifier).state = updated.dateLabel;
    ref.read(appointmentStatusFilterProvider.notifier).state = updated.status;
    ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  }
  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã hủy lịch của ${updated.customerName}')),
  );
}

Future<void> _sendAppointmentToInvoice(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  await ref.read(invoicesRepositoryProvider).prefillDraftFromAppointment(appointment);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã chuyển lịch của ${appointment.customerName} sang tính tiền')),
  );
}

String _appointmentSaveErrorMessage(Object error) {
  final raw = error.toString().trim();
  const prefix = 'Bad state: ';
  return raw.startsWith(prefix) ? raw.substring(prefix.length).trim() : raw;
}

class AppointmentsPage extends ConsumerWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(filteredAppointmentsProvider);
    return appointments.when(
      data: (items) => _AppointmentsView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Không tải được lịch hẹn: $error')),
    );
  }
}

class _AppointmentsView extends ConsumerWidget {
  const _AppointmentsView({required this.items});

  final List<AppointmentEntry> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedAppointmentIndexProvider);
    final effectiveIndex = items.isEmpty ? 0 : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final status = ref.watch(appointmentStatusFilterProvider);
    final day = ref.watch(appointmentDayFilterProvider);
    final board = ref.watch(appointmentBoardFilterProvider);
    final employees = ref.watch(appointmentEmployeesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1160;
        final bodyHeight = constraints.maxHeight < 760 ? 610.0 : 650.0;
        final detail = PremiumAnimatedDetail(
          transitionKey: ValueKey(selected?.id ?? 'appointment-empty'),
          child: _AppointmentDetailPanel(appointment: selected),
        );

        return ListView(
          primary: false,
          key: const Key('appointments-premium-workspace'),
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            PremiumPageHeader(
              key: const Key('appointments-premium-header'),
              icon: Icons.calendar_month_outlined,
              eyebrow: 'Vận hành hôm nay',
              title: 'Lịch hẹn',
              subtitle: 'Theo dõi khách, trạng thái phục vụ và phân công nhân viên trong một luồng gọn.',
              trailing: [
                FilledButton.icon(
                  onPressed: () => _openAppointmentEditor(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tạo lịch'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AppointmentStats(items: items),
            const SizedBox(height: 16),
            _AppointmentToolbar(status: status, day: day, board: board),
            const SizedBox(height: 16),
            if (board == 'Ngày') ...[
              SizedBox(
                height: bodyHeight,
                child: _AppointmentDayPanel(
                  items: items,
                  employees: employees,
                  selectedIndex: effectiveIndex,
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: 16),
                PremiumAnimatedDetail(
                  transitionKey: ValueKey('day-${selected.id}'),
                  child: _AppointmentDetailPanel(
                    appointment: selected,
                    compact: true,
                  ),
                ),
              ],
            ] else if (wide)
              SizedBox(
                height: bodyHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _AppointmentsListPanel(
                        items: items,
                        selectedIndex: effectiveIndex,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 5, child: detail),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: 430,
                child: _AppointmentsListPanel(
                  items: items,
                  selectedIndex: effectiveIndex,
                ),
              ),
              const SizedBox(height: 16),
              PremiumAnimatedDetail(
                transitionKey: ValueKey(selected?.id ?? 'appointment-empty'),
                child: _AppointmentDetailPanel(
                  appointment: selected,
                  compact: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AppointmentStats extends StatelessWidget {
  const _AppointmentStats({required this.items});

  final List<AppointmentEntry> items;

  @override
  Widget build(BuildContext context) {
    final booked = items.where((item) => item.status == 'Đã đặt').length;
    final active = items.where((item) => item.status == 'Đang làm').length;
    final waiting = items.where((item) => item.status == 'Chờ xác nhận').length;
    final stats = [
      PremiumStatCard(
        icon: Icons.event_available_outlined,
        label: 'Lịch đang hiển thị',
        value: '${items.length}',
        note: 'Theo bộ lọc hiện tại',
      ),
      PremiumStatCard(
        icon: Icons.verified_outlined,
        label: 'Đã đặt',
        value: '$booked',
        tone: AppColors.info,
      ),
      PremiumStatCard(
        icon: Icons.content_cut_rounded,
        label: 'Đang phục vụ',
        value: '$active',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.notifications_active_outlined,
        label: 'Chờ xác nhận',
        value: '$waiting',
        tone: AppColors.copper,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120 ? 4 : constraints.maxWidth >= 620 ? 2 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final stat in stats) SizedBox(width: width, child: stat)],
        );
      },
    );
  }
}

class _AppointmentToolbar extends ConsumerWidget {
  const _AppointmentToolbar({required this.status, required this.day, required this.board});

  final String status;
  final String day;
  final String board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const statuses = ['Tất cả', 'Chờ xác nhận', 'Đã đặt', 'Đã đến', 'Đang làm', 'Hoàn thành', 'Đã hủy'];
    final days = board == 'Ngày'
        ? const ['Hôm nay', 'Ngày mai']
        : const ['Tất cả', 'Hôm nay', 'Ngày mai'];

    return PremiumSectionCard(
      icon: Icons.tune_rounded,
      title: 'Bộ lọc lịch',
      subtitle: 'Tìm nhanh và thu hẹp lịch cần xử lý.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final search = TextFormField(
                initialValue: ref.watch(appointmentSearchQueryProvider),
                onChanged: (value) {
                  ref.read(appointmentSearchQueryProvider.notifier).state = value;
                  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Khách hàng, dịch vụ, thợ hoặc số điện thoại',
                ),
              );
              final boardSelector = SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Ngày', icon: Icon(Icons.calendar_view_day_outlined), label: Text('Ngày')),
                  ButtonSegment(value: 'Danh sách', icon: Icon(Icons.view_agenda_outlined), label: Text('Danh sách')),
                ],
                selected: {board},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  final nextMode = selection.first;
                  ref.read(appointmentBoardFilterProvider.notifier).state = nextMode;
                  if (nextMode == 'Ngày' && day == 'Tất cả') {
                    ref.read(appointmentDayFilterProvider.notifier).state = 'Hôm nay';
                  }
                  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                },
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [search, const SizedBox(height: 10), SingleChildScrollView(scrollDirection: Axis.horizontal, child: boardSelector)],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  boardSelector,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Ngày', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
              for (final option in days)
                ChoiceChip(
                  label: Text(option),
                  selected: option == day,
                  onSelected: (_) {
                    ref.read(appointmentDayFilterProvider.notifier).state = option;
                    ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                  },
                ),
              const SizedBox(width: 4),
              Text('Trạng thái', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
              for (final option in statuses)
                FilterChip(
                  label: Text(option),
                  selected: option == status,
                  onSelected: (_) {
                    ref.read(appointmentStatusFilterProvider.notifier).state = option;
                    ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppointmentDayPanel extends ConsumerWidget {
  const _AppointmentDayPanel({
    required this.items,
    required this.employees,
    required this.selectedIndex,
  });

  final List<AppointmentEntry> items;
  final AsyncValue<List<Map<String, Object?>>> employees;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      key: const Key('appointments-day-board'),
      icon: Icons.calendar_view_week_outlined,
      title: 'Lịch theo giờ × nhân viên',
      subtitle: items.isEmpty
          ? 'Chưa có lịch phù hợp trong ngày đang chọn.'
          : '${items.length} lịch • chọn một lịch để xem và xử lý chi tiết',
      trailing: PremiumStatusPill(label: '${items.length} lịch', tone: AppColors.info),
      child: Expanded(
        child: employees.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => PremiumEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Không tải được nhân viên',
            message: '$error',
          ),
          data: (staff) {
            final visibleStaff = staff
                .where((employee) => (employee['id']?.toString() ?? '').isNotEmpty)
                .toList(growable: false);
            if (visibleStaff.isEmpty) {
              return const PremiumEmptyState(
                icon: Icons.groups_outlined,
                title: 'Chưa có nhân viên',
                message: 'Thêm nhân viên trước khi phân lịch theo cột.',
              );
            }
            if (items.isEmpty) {
              return const PremiumEmptyState(
                icon: Icons.event_available_outlined,
                title: 'Ngày này đang trống',
                message: 'Chưa có lịch phù hợp với bộ lọc hiện tại.',
              );
            }

            return _AppointmentDayGrid(
              items: items,
              employees: visibleStaff,
              selectedIndex: selectedIndex,
              onSelect: (index) {
                ref.read(selectedAppointmentIndexProvider.notifier).state = index;
              },
            );
          },
        ),
      ),
    );
  }
}

class _AppointmentDayGrid extends StatelessWidget {
  const _AppointmentDayGrid({
    required this.items,
    required this.employees,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const double _timeColumnWidth = 72;
  static const double _employeeColumnWidth = 210;
  static const double _headerHeight = 58;
  static const double _rowHeight = 112;

  final List<AppointmentEntry> items;
  final List<Map<String, Object?>> employees;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final slots = _dayBoardSlots(items);
    final totalWidth = _timeColumnWidth + employees.length * _employeeColumnWidth;

    return SingleChildScrollView(
      primary: false,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Row(
                children: [
                  Container(
                    width: _timeColumnWidth,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.featureSurface,
                      border: Border(right: BorderSide(color: AppColors.workspaceDivider)),
                    ),
                    child: Text(
                      'Giờ',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  for (final employee in employees)
                    _DayEmployeeHeader(
                      employee: employee,
                      width: _employeeColumnWidth,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                primary: false,
                itemCount: slots.length,
                itemBuilder: (context, slotIndex) {
                  final slot = slots[slotIndex];
                  return SizedBox(
                    height: _rowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: _timeColumnWidth,
                          padding: const EdgeInsets.only(top: 10),
                          alignment: Alignment.topCenter,
                          decoration: BoxDecoration(
                            color: AppColors.featureSurface,
                            border: Border(
                              top: BorderSide(color: AppColors.workspaceDivider),
                              right: BorderSide(color: AppColors.workspaceDivider),
                            ),
                          ),
                          child: Text(
                            _minutesLabel(slot),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                        for (final employee in employees)
                          _DayScheduleCell(
                            width: _employeeColumnWidth,
                            appointments: _appointmentsForCell(
                              items: items,
                              employee: employee,
                              slotMinutes: slot,
                            ),
                            selectedAppointmentId: items.isEmpty
                                ? null
                                : items[selectedIndex.clamp(0, items.length - 1)].id,
                            onSelect: (appointment) {
                              final index = items.indexWhere((item) => item.id == appointment.id);
                              if (index >= 0) onSelect(index);
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEmployeeHeader extends StatelessWidget {
  const _DayEmployeeHeader({required this.employee, required this.width});

  final Map<String, Object?> employee;
  final double width;

  @override
  Widget build(BuildContext context) {
    final name = employee['name']?.toString() ?? 'Nhân viên';
    final initials = employee['initials']?.toString() ?? _initials(name);
    final role = employee['role']?.toString() ?? '';

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        border: Border(right: BorderSide(color: AppColors.workspaceDivider)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.iconSurface,
            foregroundColor: AppColors.copper,
            child: Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (role.isNotEmpty)
                  Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayScheduleCell extends StatelessWidget {
  const _DayScheduleCell({
    required this.width,
    required this.appointments,
    required this.selectedAppointmentId,
    required this.onSelect,
  });

  final double width;
  final List<AppointmentEntry> appointments;
  final String? selectedAppointmentId;
  final ValueChanged<AppointmentEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    final appointment = appointments.firstOrNull;
    return Container(
      width: width,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.workspaceDivider),
          right: BorderSide(color: AppColors.workspaceDivider),
        ),
      ),
      child: appointment == null
          ? Center(
              child: Text('Trống', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DayAppointmentCard(
                    appointment: appointment,
                    selected: appointment.id == selectedAppointmentId,
                    onTap: () => onSelect(appointment),
                  ),
                ),
                if (appointments.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '+${appointments.length - 1} lịch cùng mốc',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DayAppointmentCard extends StatelessWidget {
  const _DayAppointmentCard({
    required this.appointment,
    required this.selected,
    required this.onTap,
  });

  final AppointmentEntry appointment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumInteractiveSurface(
      key: Key('appointment-day-card-${appointment.id}'),
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appointment.timeRangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 5),
              PremiumStatusPill(label: appointment.status, tone: _statusColor(appointment.status)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            appointment.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            appointment.servicesSummary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

List<int> _dayBoardSlots(List<AppointmentEntry> items) {
  if (items.isEmpty) return const [];

  var earliest = 24 * 60;
  var latest = 0;
  for (final item in items) {
    final start = item.startsAt.hour * 60 + item.startsAt.minute;
    final end = item.endsAt.hour * 60 + item.endsAt.minute + (item.endsAt.day != item.startsAt.day ? 24 * 60 : 0);
    if (start < earliest) earliest = start;
    if (end > latest) latest = end;
  }

  final firstSlot = ((_floorHalfHour(earliest) - 30).clamp(0, 24 * 60 - 30)).toInt();
  final lastSlot = ((_ceilHalfHour(latest) + 30).clamp(firstSlot + 30, 24 * 60)).toInt();
  return [for (var minute = firstSlot; minute < lastSlot; minute += 30) minute];
}

List<AppointmentEntry> _appointmentsForCell({
  required List<AppointmentEntry> items,
  required Map<String, Object?> employee,
  required int slotMinutes,
}) {
  final results = items.where((appointment) {
    final startMinutes = appointment.startsAt.hour * 60 + appointment.startsAt.minute;
    return _floorHalfHour(startMinutes) == slotMinutes && _matchesEmployee(appointment, employee);
  }).toList(growable: false);
  results.sort((a, b) {
    if (a.status == 'Đã hủy' && b.status != 'Đã hủy') return 1;
    if (a.status != 'Đã hủy' && b.status == 'Đã hủy') return -1;
    return a.startsAt.compareTo(b.startsAt);
  });
  return results;
}

bool _matchesEmployee(AppointmentEntry appointment, Map<String, Object?> employee) {
  final employeeId = employee['id']?.toString();
  if (appointment.employeeId != null && appointment.employeeId == employeeId) {
    return true;
  }
  final employeeName = employee['name']?.toString().trim().toLowerCase() ?? '';
  return employeeName.isNotEmpty && appointment.staffName.trim().toLowerCase() == employeeName;
}

int _floorHalfHour(int minutes) => (minutes ~/ 30) * 30;
int _ceilHalfHour(int minutes) => ((minutes + 29) ~/ 30) * 30;

String _minutesLabel(int minutes) {
  if (minutes >= 24 * 60) return '24:00';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

class _AppointmentsListPanel extends ConsumerWidget {
  const _AppointmentsListPanel({required this.items, required this.selectedIndex});

  final List<AppointmentEntry> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.schedule_outlined,
      title: 'Lịch trong ngày',
      subtitle: items.isEmpty ? 'Không có lịch phù hợp' : '${items.length} lịch theo bộ lọc',
      trailing: PremiumStatusPill(label: '${items.length} lịch', tone: AppColors.info),
      child: Expanded(
        child: items.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Chưa có lịch phù hợp',
                message: 'Đổi bộ lọc hoặc tạo lịch mới để tiếp tục.',
              )
            : ListView.separated(
                primary: false,
                itemCount: items.length,
                separatorBuilder: (context, index) => const PremiumDivider(indent: 54),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _AppointmentRow(
                    appointment: item,
                    selected: index == selectedIndex,
                    onTap: () => ref.read(selectedAppointmentIndexProvider.notifier).state = index,
                  );
                },
              ),
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({required this.appointment, required this.selected, required this.onTap});

  final AppointmentEntry appointment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _statusColor(appointment.status);
    return PremiumInteractiveSurface(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.iconSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(appointment.timeLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                Text(appointment.dateLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appointment.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(appointment.servicesSummary, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text('${appointment.staffName} • ${appointment.durationLabel} • ${appointment.slotLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PremiumStatusPill(label: appointment.status, tone: tone),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}

class _AppointmentDetailPanel extends ConsumerWidget {
  const _AppointmentDetailPanel({required this.appointment, this.compact = false});

  final AppointmentEntry? appointment;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = appointment;
    if (item == null) {
      return const PremiumSectionCard(
        icon: Icons.person_search_outlined,
        title: 'Chi tiết lịch',
        child: PremiumEmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Chọn một lịch hẹn',
          message: 'Thông tin khách, dịch vụ và thao tác sẽ hiện tại đây.',
        ),
      );
    }

    final tone = _statusColor(item.status);
    final statusAction = _statusActionLabel(item.status);
    final linkedInvoice = ref.watch(appointmentInvoiceHistoryProvider(item.id));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: AppColors.iconSurface,
              foregroundColor: AppColors.copper,
              child: Text(_initials(item.customerName), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.customerName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)),
                  const SizedBox(height: 3),
                  Text(item.customerPhone, style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            ),
            PremiumStatusPill(label: item.status, tone: tone),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Expanded(child: _MiniMetric(icon: Icons.schedule_rounded, label: 'Giờ', value: item.timeRangeLabel)),
              Container(width: 1, height: 34, color: AppColors.workspaceDivider),
              Expanded(child: _MiniMetric(icon: Icons.timelapse_rounded, label: 'Thời lượng', value: item.durationLabel)),
              Container(width: 1, height: 34, color: AppColors.workspaceDivider),
              Expanded(child: _MiniMetric(icon: Icons.chair_outlined, label: 'Khu vực', value: item.slotLabel)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        PremiumInfoRow(icon: Icons.content_cut_rounded, label: 'Dịch vụ', value: item.servicesSummary),
        const PremiumDivider(indent: 43),
        PremiumInfoRow(icon: Icons.badge_outlined, label: 'Nhân viên phụ trách', value: item.staffName),
        const PremiumDivider(indent: 43),
        PremiumInfoRow(icon: Icons.calendar_today_outlined, label: 'Ngày hẹn', value: item.dateLabel),
        const PremiumDivider(indent: 43),
        PremiumInfoRow(icon: Icons.notes_outlined, label: 'Ghi chú', value: item.note.trim().isEmpty ? 'Không có ghi chú' : item.note),
        const SizedBox(height: 10),
        _AppointmentInvoiceSummary(invoiceState: linkedInvoice),
        const SizedBox(height: 16),
        _AppointmentActions(
          appointment: item,
          statusActionLabel: statusAction,
          onStatus: statusAction == null ? null : () => _updateAppointmentStatus(context, ref, item),
          onEdit: () => _openAppointmentEditor(context, ref, appointment: item),
          onCheckout: item.status == 'Chờ xác nhận' || item.status == 'Đã hủy'
              ? null
              : () => _sendAppointmentToInvoice(context, ref, item),
          onUndo: item.status == 'Hoàn thành' ? () => _undoAppointmentComplete(context, ref, item) : null,
          onCancel: item.status == 'Đã hủy' ? null : () => _cancelAppointment(context, ref, item),
        ),
      ],
    );

    return PremiumSectionCard(
      icon: Icons.contact_page_outlined,
      title: 'Chi tiết lịch',
      subtitle: 'Thông tin và thao tác cho lịch đang chọn.',
      child: compact ? content : Expanded(child: SingleChildScrollView(primary: false, child: content)),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.copper),
              const SizedBox(width: 4),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
            ],
          ),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AppointmentInvoiceSummary extends StatelessWidget {
  const _AppointmentInvoiceSummary({required this.invoiceState});

  final AsyncValue<InvoiceDraft?> invoiceState;

  @override
  Widget build(BuildContext context) {
    return invoiceState.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => PremiumInfoRow(
        icon: Icons.receipt_long_outlined,
        label: 'Hóa đơn liên quan',
        value: 'Không tải được: $error',
      ),
      data: (invoice) {
        if (invoice == null) {
          return const PremiumInfoRow(
            icon: Icons.receipt_long_outlined,
            label: 'Hóa đơn liên quan',
            value: 'Chưa có hóa đơn đã thanh toán',
          );
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.selectedSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.copper.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              PremiumIconBadge(icon: Icons.receipt_long_outlined, size: 36, tone: AppColors.success),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Đã chốt hóa đơn', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.success, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text('${_currency(invoice.totalAmount)} • ${invoice.paymentMethod} • ${invoice.lines.length} mục', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (invoice.paidAt != null) Text(_dateTime(invoice.paidAt!), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppointmentActions extends StatelessWidget {
  const _AppointmentActions({
    required this.appointment,
    required this.statusActionLabel,
    required this.onStatus,
    required this.onEdit,
    required this.onCheckout,
    required this.onUndo,
    required this.onCancel,
  });

  final AppointmentEntry appointment;
  final String? statusActionLabel;
  final VoidCallback? onStatus;
  final VoidCallback onEdit;
  final VoidCallback? onCheckout;
  final VoidCallback? onUndo;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Đưa sang tính tiền'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: onEdit, tooltip: 'Sửa lịch', icon: const Icon(Icons.edit_outlined)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (statusActionLabel != null)
              OutlinedButton.icon(
                onPressed: onStatus,
                icon: Icon(_statusActionIcon(appointment.status)),
                label: Text(statusActionLabel!),
              ),
            if (onUndo != null)
              OutlinedButton.icon(onPressed: onUndo, icon: const Icon(Icons.undo_outlined), label: const Text('Hoàn tác')),
            OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Hủy lịch'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppointmentEditorDialog extends StatefulWidget {
  const _AppointmentEditorDialog({
    required this.customers,
    required this.services,
    required this.employees,
    this.appointment,
  });

  final AppointmentEntry? appointment;
  final List<CustomerProfile> customers;
  final List<ServiceCatalogItem> services;
  final List<Map<String, Object?>> employees;

  @override
  State<_AppointmentEditorDialog> createState() => _AppointmentEditorDialogState();
}

class _AppointmentEditorDialogState extends State<_AppointmentEditorDialog> {
  static const _statusOptions = ['Chờ xác nhận', 'Đã đặt', 'Đã đến', 'Đang làm', 'Hoàn thành', 'Đã hủy'];
  static const _dayOptions = ['Hôm nay', 'Ngày mai'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _durationController;
  late final TextEditingController _slotController;
  late final TextEditingController _timeController;
  late final TextEditingController _noteController;
  String? _selectedCustomerId;
  late List<String> _selectedServiceIds;
  String? _selectedEmployeeId;
  late String _status;
  late String _dayLabel;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    _selectedServiceIds = _resolveInitialServiceIds(appointment);
    _selectedEmployeeId = _resolveInitialEmployeeId(appointment);
    _selectedCustomerId = _resolveInitialCustomerId(appointment);
    _durationController = TextEditingController(
      text: appointment?.durationMinutes.toString() ?? _selectedServicesDuration.toString(),
    );
    _slotController = TextEditingController(text: appointment?.slotLabel ?? 'Ghế VIP 1');
    _timeController = TextEditingController(text: appointment?.timeLabel ?? '10:00');
    _noteController = TextEditingController(text: appointment?.note ?? '');
    _status = _statusOptions.contains(appointment?.status) ? appointment!.status : 'Chờ xác nhận';
    _dayLabel = _dayOptions.contains(appointment?.dateLabel) ? appointment!.dateLabel : 'Hôm nay';
  }

  @override
  void dispose() {
    _durationController.dispose();
    _slotController.dispose();
    _timeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.appointment != null;
    final selectedCustomer = _selectedCustomer;
    final selectedEmployee = _selectedEmployee;
    final selectedServices = _selectedServices;

    return AlertDialog(
      title: Row(
        children: [
          PremiumIconBadge(icon: isEditing ? Icons.edit_calendar_outlined : Icons.add_task_rounded, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Text(isEditing ? 'Sửa lịch hẹn' : 'Tạo lịch hẹn')),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 620),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Khách hàng', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 7),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCustomerId,
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline)),
                  items: widget.customers.map((customer) => DropdownMenuItem(
                    value: customer.id,
                    child: Text('${customer.fullName} • ${customer.phone}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  validator: (value) => value == null || value.isEmpty ? 'Chọn khách hàng có sẵn' : null,
                  onChanged: (value) => setState(() => _selectedCustomerId = value),
                ),
                if (selectedCustomer != null) ...[
                  const SizedBox(height: 8),
                  Text('SĐT ${selectedCustomer.phone} • Hạng ${selectedCustomer.tier}', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 16),
                Text('Dịch vụ', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 7),
                FormField<List<String>>(
                  initialValue: _selectedServiceIds,
                  validator: (value) => value == null || value.isEmpty ? 'Chọn ít nhất một dịch vụ có sẵn' : null,
                  builder: (field) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.fieldShell,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: field.hasError ? AppColors.danger : AppColors.controlBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      children: [
                        for (final service in widget.services.where((service) => service.isActive))
                          CheckboxListTile(
                            value: _selectedServiceIds.contains(service.id),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(service.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${service.category} • ${service.durationLabel} • ${service.priceLabel}'),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  if (!_selectedServiceIds.contains(service.id)) {
                                    _selectedServiceIds = [..._selectedServiceIds, service.id];
                                  }
                                } else {
                                  _selectedServiceIds = _selectedServiceIds.where((id) => id != service.id).toList(growable: false);
                                }
                                _durationController.text = _selectedServicesDuration.toString();
                                field.didChange(_selectedServiceIds);
                              });
                            },
                          ),
                        if (field.hasError)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                              child: Text(field.errorText!, style: TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (selectedServices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${selectedServices.length} dịch vụ • $_selectedServicesPriceLabel • $_selectedServicesDuration phút', style: TextStyle(fontSize: 11, color: AppColors.copper, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmployeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nhân viên phụ trách', prefixIcon: Icon(Icons.badge_outlined)),
                  items: widget.employees.map((employee) => DropdownMenuItem(
                    value: employee['id']?.toString(),
                    child: Text('${employee['name']} • ${employee['role']}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  validator: (value) => value == null || value.isEmpty ? 'Chọn nhân viên có sẵn' : null,
                  onChanged: (value) => setState(() => _selectedEmployeeId = value),
                ),
                if (selectedEmployee != null) ...[
                  const SizedBox(height: 8),
                  Text('Ca ${selectedEmployee['shift']} • ${selectedEmployee['role']}', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final dateField = DropdownButtonFormField<String>(
                      initialValue: _dayLabel,
                      decoration: const InputDecoration(labelText: 'Ngày hẹn'),
                      items: _dayOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                      onChanged: (value) { if (value != null) setState(() => _dayLabel = value); },
                    );
                    final timeField = TextFormField(
                      controller: _timeController,
                      decoration: const InputDecoration(labelText: 'Giờ hẹn'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Nhập giờ hẹn';
                        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) return 'Dùng HH:mm';
                        return null;
                      },
                    );
                    if (stacked) return Column(children: [dateField, const SizedBox(height: 10), timeField]);
                    return Row(children: [Expanded(child: dateField), const SizedBox(width: 10), Expanded(child: timeField)]);
                  },
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final duration = TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(labelText: 'Thời lượng (phút)'),
                      validator: (value) {
                        final minutes = int.tryParse(value?.trim() ?? '');
                        return minutes == null || minutes <= 0 ? 'Nhập số phút hợp lệ' : null;
                      },
                    );
                    final slot = TextFormField(
                      controller: _slotController,
                      decoration: const InputDecoration(labelText: 'Khu vực / ghế'),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Nhập khu vực phục vụ' : null,
                    );
                    if (stacked) return Column(children: [duration, const SizedBox(height: 10), slot]);
                    return Row(children: [Expanded(child: duration), const SizedBox(width: 10), Expanded(child: slot)]);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: _statusOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                  onChanged: (value) { if (value != null) setState(() => _status = value); },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Ghi chú', prefixIcon: Icon(Icons.notes_outlined)),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(isEditing ? 'Lưu lịch' : 'Tạo lịch'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final customer = _selectedCustomer;
    final services = _selectedServices;
    final employee = _selectedEmployee;
    if (customer == null || services.isEmpty || employee == null) return;
    setState(() => _isSubmitting = true);

    Navigator.of(context).pop(
      AppointmentUpsertInput(
        customerId: customer.id,
        serviceIds: services.map((service) => service.id).toList(growable: false),
        employeeId: employee['id']!.toString(),
        customerName: customer.fullName,
        customerPhone: customer.phone,
        serviceName: services.map((service) => service.name).join(' + '),
        staffName: employee['name']!.toString(),
        status: _status,
        durationMinutes: int.parse(_durationController.text.trim()),
        slotLabel: _slotController.text.trim(),
        note: _noteController.text.trim(),
        dayLabel: _dayLabel,
        timeLabel: _timeController.text.trim(),
      ),
    );
  }

  String? _resolveInitialCustomerId(AppointmentEntry? appointment) {
    if (appointment == null) return widget.customers.isEmpty ? null : widget.customers.first.id;
    for (final customer in widget.customers) {
      if (customer.id == appointment.customerId) return customer.id;
    }
    return widget.customers.isEmpty ? null : widget.customers.first.id;
  }

  List<String> _resolveInitialServiceIds(AppointmentEntry? appointment) {
    if (appointment == null) return const [];
    if (appointment.services.isNotEmpty) {
      return appointment.services.map((service) => service.serviceId).toList(growable: false);
    }
    for (final service in widget.services) {
      if (service.id == appointment.serviceId || service.name == appointment.serviceName) return [service.id];
    }
    return const [];
  }

  String? _resolveInitialEmployeeId(AppointmentEntry? appointment) {
    if (appointment == null) return widget.employees.firstOrNull?['id']?.toString();
    for (final employee in widget.employees) {
      if (employee['id']?.toString() == appointment.employeeId || employee['name']?.toString() == appointment.staffName) {
        return employee['id']?.toString();
      }
    }
    return widget.employees.firstOrNull?['id']?.toString();
  }

  CustomerProfile? get _selectedCustomer {
    final id = _selectedCustomerId;
    if (id == null) return null;
    for (final customer in widget.customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  List<ServiceCatalogItem> get _selectedServices {
    final ids = _selectedServiceIds.toSet();
    return widget.services.where((service) => ids.contains(service.id)).toList(growable: false);
  }

  int get _selectedServicesDuration {
    final services = _selectedServices;
    if (services.isEmpty) return 90;
    return services.fold<int>(0, (sum, service) => sum + service.durationMinutes);
  }

  String get _selectedServicesPriceLabel {
    final price = _selectedServices.fold<int>(0, (sum, service) => sum + service.price);
    return _currency(price);
  }

  Map<String, Object?>? get _selectedEmployee {
    final id = _selectedEmployeeId;
    if (id == null) return null;
    for (final employee in widget.employees) {
      if (employee['id']?.toString() == id) return employee;
    }
    return null;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'Đã đến':
      return AppColors.success;
    case 'Đang làm':
      return AppColors.info;
    case 'Hoàn thành':
      return AppColors.success;
    case 'Đã hủy':
      return AppColors.danger;
    case 'Chờ xác nhận':
      return AppColors.copper;
    default:
      return AppColors.info;
  }
}

String? _nextStatus(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return 'Đã đặt';
    case 'Đã đặt':
      return 'Đã đến';
    case 'Đã đến':
      return 'Đang làm';
    case 'Đang làm':
      return 'Hoàn thành';
    case 'Hoàn thành':
      return 'Đang làm';
    case 'Đã hủy':
      return 'Chờ xác nhận';
    default:
      return null;
  }
}

String? _statusActionLabel(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return 'Xác nhận lịch';
    case 'Đã đặt':
      return 'Đánh dấu đã đến';
    case 'Đã đến':
      return 'Bắt đầu dịch vụ';
    case 'Đang làm':
      return 'Đánh dấu hoàn thành';
    case 'Hoàn thành':
      return 'Mở lại Đang làm';
    case 'Đã hủy':
      return 'Mở lại lịch';
    default:
      return null;
  }
}

IconData _statusActionIcon(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return Icons.verified_outlined;
    case 'Đã đặt':
      return Icons.how_to_reg_outlined;
    case 'Đã đến':
      return Icons.play_arrow_rounded;
    case 'Đang làm':
      return Icons.task_alt_rounded;
    case 'Hoàn thành':
      return Icons.replay_rounded;
    default:
      return Icons.refresh_rounded;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

final NumberFormat _currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
final DateFormat _dateTimeFormatter = DateFormat('dd/MM HH:mm');
String _currency(int value) => _currencyFormatter.format(value).replaceAll(',', '.');
String _dateTime(DateTime value) => _dateTimeFormatter.format(value);
