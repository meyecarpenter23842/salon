import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../app/navigation/flow_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/appointment_upsert_input.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

part 'appointments_controls.dart';
part 'appointments_day_panel.dart';
part 'appointments_day_cards.dart';
part 'appointments_day_menu.dart';
part 'appointments_day_helpers.dart';
part 'appointments_list.dart';
part 'appointments_detail_sheet.dart';
part 'appointments_invoice_summary.dart';
part 'appointment_editor_form.dart';
part 'appointment_helpers.dart';

final appointmentStatusFilterProvider = StateProvider<String>(
  (ref) => 'Tất cả',
);
final appointmentDayFilterProvider = StateProvider<String>((ref) => 'Hôm nay');
final appointmentSearchQueryProvider = StateProvider<String>((ref) => '');
final appointmentBoardFilterProvider = StateProvider<String>((ref) => 'Ngày');
final appointmentEmployeeFilterProvider = StateProvider<String>((ref) => 'all');
final selectedAppointmentIndexProvider = StateProvider<int>((ref) => 0);
final appointmentDetailVisibleProvider = StateProvider<bool>((ref) => true);

final appointmentEmployeesProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) {
    return ref.watch(employeesRepositoryProvider).fetchEmployeesView();
  },
);

final appointmentDayRolloverProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(nextMidnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return now;
});

final filteredAppointmentsProvider = FutureProvider<List<AppointmentEntry>>((
  ref,
) async {
  ref.watch(appointmentDayRolloverProvider);
  final allItems = await ref
      .watch(appointmentsRepositoryProvider)
      .fetchAppointmentsView();
  final status = ref.watch(appointmentStatusFilterProvider);
  final day = ref.watch(appointmentDayFilterProvider);
  final query = ref.watch(appointmentSearchQueryProvider).trim().toLowerCase();
  final employeeId = ref.watch(appointmentEmployeeFilterProvider);

  return allItems
      .where((item) {
        final matchesStatus = status == 'Tất cả' || item.status == status;
        final matchesDay = day == 'Tất cả' || item.dateLabel == day;
        final matchesEmployee =
            employeeId == 'all' || item.employeeId == employeeId;
        final matchesQuery =
            query.isEmpty ||
            [
              item.customerName,
              item.serviceName,
              item.staffName,
              item.customerPhone,
            ].any((value) => value.toLowerCase().contains(query));
        return matchesStatus && matchesDay && matchesEmployee && matchesQuery;
      })
      .toList(growable: false);
});

bool _blockPaidAppointment(
  BuildContext context,
  AppointmentEntry? appointment,
) {
  if (appointment?.isPaid != true) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Lịch hẹn đã thanh toán nên được khóa chỉnh sửa và trạng thái.',
      ),
    ),
  );
  return true;
}

Future<void> _openAppointmentEditor(
  BuildContext context,
  WidgetRef ref, {
  AppointmentEntry? appointment,
  String? initialEmployeeId,
  String? initialTimeLabel,
  String? initialDayLabel,
}) async {
  if (_blockPaidAppointment(context, appointment)) return;

  final customers = await ref
      .read(customersRepositoryProvider)
      .fetchCustomersView();
  final services = await ref
      .read(servicesRepositoryProvider)
      .fetchServicesView();
  final employees = await ref
      .read(employeesRepositoryProvider)
      .fetchEmployeesView();
  if (!context.mounted) return;

  final input = await showDialog<AppointmentUpsertInput>(
    context: context,
    builder: (_) => _AppointmentEditorDialog(
      appointment: appointment,
      customers: customers,
      services: services,
      employees: employees,
      initialEmployeeId: initialEmployeeId,
      initialTimeLabel: initialTimeLabel,
      initialDayLabel: initialDayLabel,
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
  ref.read(appointmentDayFilterProvider.notifier).state =
      savedAppointment.dateLabel;
  if (viewMode == 'Ngày') {
    ref.read(appointmentSearchQueryProvider.notifier).state = '';
    ref.read(appointmentStatusFilterProvider.notifier).state = 'Tất cả';
    final employeeFilter = ref.read(appointmentEmployeeFilterProvider);
    if (employeeFilter != 'all' &&
        employeeFilter != savedAppointment.employeeId) {
      ref.read(appointmentEmployeeFilterProvider.notifier).state = 'all';
    }
  } else {
    ref.read(appointmentSearchQueryProvider.notifier).state =
        savedAppointment.customerName;
    ref.read(appointmentStatusFilterProvider.notifier).state =
        savedAppointment.status;
  }
  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  ref.read(appointmentDetailVisibleProvider.notifier).state = true;
  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);

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
  if (_blockPaidAppointment(context, appointment)) return;
  final nextStatus = _nextStatus(appointment.status);
  if (nextStatus == null) return;

  AppointmentEntry updated;
  try {
    updated = await ref
        .read(appointmentsRepositoryProvider)
        .updateAppointmentStatus(appointment.id, nextStatus);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }
  if (!context.mounted) return;

  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã chuyển lịch sang ${updated.status}')),
  );
}

Future<void> _undoAppointmentComplete(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  if (_blockPaidAppointment(context, appointment)) return;
  try {
    await ref
        .read(appointmentsRepositoryProvider)
        .updateAppointmentStatus(appointment.id, 'Đang làm');
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }
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
  if (_blockPaidAppointment(context, appointment)) return;
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

  try {
    await ref
        .read(appointmentsRepositoryProvider)
        .updateAppointmentStatus(appointment.id, 'Đã hủy');
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }
  if (!context.mounted) return;
  ref.invalidate(filteredAppointmentsProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã hủy lịch của ${appointment.customerName}')),
  );
}

Future<void> _sendAppointmentToInvoice(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  if (_blockPaidAppointment(context, appointment)) return;
  try {
    await ref
        .read(invoicesRepositoryProvider)
        .prefillDraftFromAppointment(appointment);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Đã chuyển lịch của ${appointment.customerName} sang tính tiền',
      ),
    ),
  );
}

Future<void> _handleAppointmentMenuAction(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
  _AppointmentMenuAction action,
) async {
  if (_blockPaidAppointment(context, appointment)) return;
  switch (action) {
    case _AppointmentMenuAction.advance:
      await _updateAppointmentStatus(context, ref, appointment);
      return;
    case _AppointmentMenuAction.edit:
      await _openAppointmentEditor(context, ref, appointment: appointment);
      return;
    case _AppointmentMenuAction.checkout:
      await _sendAppointmentToInvoice(context, ref, appointment);
      return;
    case _AppointmentMenuAction.cancel:
      await _cancelAppointment(context, ref, appointment);
      return;
    case _AppointmentMenuAction.undo:
      await _undoAppointmentComplete(context, ref, appointment);
      return;
  }
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
      loading: () => const PremiumLoadingState(label: 'Đang tải lịch hẹn…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được lịch hẹn',
        message: '$error',
        onRetry: () => ref.invalidate(filteredAppointmentsProvider),
      ),
    );
  }
}

class _AppointmentsView extends ConsumerWidget {
  const _AppointmentsView({required this.items});

  final List<AppointmentEntry> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedAppointmentIndexProvider);
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final status = ref.watch(appointmentStatusFilterProvider);
    final day = ref.watch(appointmentDayFilterProvider);
    final board = ref.watch(appointmentBoardFilterProvider);
    final employees = ref.watch(appointmentEmployeesProvider);
    final detailVisible = ref.watch(appointmentDetailVisibleProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600 || constraints.maxHeight < 320) {
          return const SizedBox.expand(
            key: Key('appointments-premium-workspace'),
          );
        }

        final showSideDetail =
            constraints.maxWidth >= 1120 && selected != null && detailVisible;

        void selectAppointment(AppointmentEntry appointment) {
          final index = items.indexWhere((item) => item.id == appointment.id);
          if (index < 0) return;
          ref.read(selectedAppointmentIndexProvider.notifier).state = index;
          ref.read(appointmentDetailVisibleProvider.notifier).state = true;
          if (constraints.maxWidth < 1120) {
            _showAppointmentDetailDialog(context, ref, appointment);
          }
        }

        return Column(
          key: const Key('appointments-premium-workspace'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AppointmentCommandBar(
              key: const Key('appointments-premium-header'),
              day: day,
              board: board,
              employees: employees,
              onCreate: () => _openAppointmentEditor(context, ref),
            ),
            const SizedBox(height: 8),
            _AppointmentToolbar(status: status, day: day),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: board == 'Ngày'
                        ? _AppointmentDayPanel(
                            items: items,
                            employees: employees,
                            selectedIndex: effectiveIndex,
                            onSelect: selectAppointment,
                          )
                        : _AppointmentsListPanel(
                            items: items,
                            selectedIndex: effectiveIndex,
                            onSelect: selectAppointment,
                          ),
                  ),
                  if (showSideDetail) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: math
                          .min(360.0, constraints.maxWidth * 0.29)
                          .toDouble(),
                      child: _AppointmentDetailSheet(
                        appointment: selected,
                        onClose: () {
                          ref
                                  .read(
                                    appointmentDetailVisibleProvider.notifier,
                                  )
                                  .state =
                              false;
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
