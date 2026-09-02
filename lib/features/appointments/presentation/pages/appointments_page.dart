import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/appointment_upsert_input.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final appointmentStatusFilterProvider = StateProvider<String>(
  (ref) => 'Tất cả',
);

final appointmentDayFilterProvider = StateProvider<String>((ref) => 'Hôm nay');

final appointmentSearchQueryProvider = StateProvider<String>((ref) => '');

final appointmentBoardFilterProvider = StateProvider<String>(
  (ref) => 'Lịch hẹn',
);

final selectedAppointmentIndexProvider = StateProvider<int>((ref) => 0);

final filteredAppointmentsProvider = FutureProvider<List<AppointmentEntry>>((
  ref,
) async {
  final allItems = await ref
      .watch(appointmentsRepositoryProvider)
      .fetchAppointmentsView();
  final status = ref.watch(appointmentStatusFilterProvider);
  final day = ref.watch(appointmentDayFilterProvider);
  final query = ref.watch(appointmentSearchQueryProvider).trim().toLowerCase();
  final board = ref.watch(appointmentBoardFilterProvider);

  return allItems.where((item) {
    final matchesStatus = status == 'Tất cả' || item.status == status;
    final matchesDay = day == 'Tất cả' || item.dateLabel == day;
    final matchesQuery =
        query.isEmpty ||
        [
          item.customerName,
          item.serviceName,
          item.staffName,
          item.customerPhone,
        ].any((value) => value.toString().toLowerCase().contains(query));

    final matchesBoard = board != 'Đang làm' || item.status == 'Đang làm';
    return matchesStatus && matchesDay && matchesQuery && matchesBoard;
  }).toList();
});

Future<void> _openAppointmentEditor(
  BuildContext context,
  WidgetRef ref, {
  AppointmentEntry? appointment,
}) async {
  final customers = await ref
      .read(customersRepositoryProvider)
      .fetchCustomersView();
  final services = await ref
      .read(servicesRepositoryProvider)
      .fetchServicesView();
  final employees = await ref
      .read(employeesRepositoryProvider)
      .fetchEmployeesView();
  if (!context.mounted) {
    return;
  }

  final input = await showDialog<AppointmentUpsertInput>(
    context: context,
    builder: (dialogContext) => _AppointmentEditorDialog(
      appointment: appointment,
      customers: customers,
      services: services,
      employees: employees,
    ),
  );

  if (input == null || !context.mounted) {
    return;
  }

  AppointmentEntry savedAppointment;
  try {
    savedAppointment = await ref
        .read(appointmentsRepositoryProvider)
        .saveAppointment(input, existingId: appointment?.id);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_appointmentSaveErrorMessage(error))),
    );
    return;
  }

  if (!context.mounted) {
    return;
  }

  ref.read(appointmentSearchQueryProvider.notifier).state =
      savedAppointment.customerName;
  ref.read(appointmentDayFilterProvider.notifier).state =
      savedAppointment.dateLabel;
  ref.read(appointmentStatusFilterProvider.notifier).state =
      savedAppointment.status;
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
  if (nextStatus == null) {
    return;
  }

  final updatedAppointment = await ref
      .read(appointmentsRepositoryProvider)
      .updateAppointmentStatus(appointment.id, nextStatus);

  if (!context.mounted) {
    return;
  }

  ref.read(appointmentSearchQueryProvider.notifier).state =
      updatedAppointment.customerName;
  ref.read(appointmentDayFilterProvider.notifier).state =
      updatedAppointment.dateLabel;
  ref.read(appointmentStatusFilterProvider.notifier).state =
      updatedAppointment.status;
  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  ref.invalidate(filteredAppointmentsProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Đã chuyển lịch sang trạng thái ${updatedAppointment.status}',
      ),
    ),
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

  if (shouldCancel != true) {
    return;
  }

  final updatedAppointment = await ref
      .read(appointmentsRepositoryProvider)
      .updateAppointmentStatus(appointment.id, 'Đã hủy');

  if (!context.mounted) {
    return;
  }

  ref.read(appointmentSearchQueryProvider.notifier).state =
      updatedAppointment.customerName;
  ref.read(appointmentDayFilterProvider.notifier).state =
      updatedAppointment.dateLabel;
  ref.read(appointmentStatusFilterProvider.notifier).state =
      updatedAppointment.status;
  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
  ref.invalidate(filteredAppointmentsProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Đã hủy lịch của ${updatedAppointment.customerName}'),
    ),
  );
}

Future<void> _sendAppointmentToInvoice(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  await ref
      .read(invoicesRepositoryProvider)
      .prefillDraftFromAppointment(appointment);

  if (!context.mounted) {
    return;
  }

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

String _appointmentSaveErrorMessage(Object error) {
  final rawMessage = error.toString().trim();
  const statePrefix = 'Bad state: ';
  if (rawMessage.startsWith(statePrefix)) {
    return rawMessage.substring(statePrefix.length).trim();
  }
  return rawMessage;
}

class AppointmentsPage extends ConsumerWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointments = ref.watch(filteredAppointmentsProvider);

    return appointments.when(
      data: (items) => _AppointmentsView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được lịch hẹn: $error')),
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
    final selectedAppointment = items.isEmpty ? null : items[effectiveIndex];
    final status = ref.watch(appointmentStatusFilterProvider);
    final day = ref.watch(appointmentDayFilterProvider);
    final board = ref.watch(appointmentBoardFilterProvider);

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
                      child: _AppointmentsListPanel(
                        items: items,
                        selectedIndex: effectiveIndex,
                      ),
                    ),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(
                      flex: 4,
                      child: _AppointmentDetailPanel(
                        appointment: selectedAppointment,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _AppointmentsListPanel(
                      items: items,
                      selectedIndex: effectiveIndex,
                    ),
                  ),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(
                    flex: 4,
                    child: _AppointmentDetailPanel(
                      appointment: selectedAppointment,
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
              const _AppointmentsHero(),
              const SizedBox(height: AppDimens.heroGap),
              _AppointmentsSummaryRow(items: items),
              const SizedBox(height: AppDimens.sectionGap),
              _AppointmentToolbar(status: status, day: day, board: board),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 680, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AppointmentsHero(),
            const SizedBox(height: AppDimens.heroGap),
            _AppointmentsSummaryRow(items: items),
            const SizedBox(height: AppDimens.sectionGap),
            _AppointmentToolbar(status: status, day: day, board: board),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _AppointmentsHero extends StatelessWidget {
  const _AppointmentsHero();

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
            'Lịch hẹn',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text(
            'Lịch hẹn hiện dùng typed flow và sẵn sàng backend SQLite ở runtime, giữ nguyên bộ lọc và desktop layout đã khóa.',
            style: TextStyle(color: AppColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _AppointmentsSummaryRow extends StatelessWidget {
  const _AppointmentsSummaryRow({required this.items});

  final List<AppointmentEntry> items;

  @override
  Widget build(BuildContext context) {
    final confirmed = items.where((item) => item.status == 'Đã đặt').length;
    final inProgress = items.where((item) => item.status == 'Đang làm').length;
    final waiting = items.where((item) => item.status == 'Chờ xác nhận').length;

    final cards = [
      _SummaryCard(label: 'Tổng lịch hiện thị', value: '${items.length}'),
      _SummaryCard(label: 'Đã đặt', value: '$confirmed'),
      _SummaryCard(label: 'Đang làm', value: '$inProgress'),
      _SummaryCard(label: 'Chờ xác nhận', value: '$waiting'),
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

class _AppointmentToolbar extends ConsumerWidget {
  const _AppointmentToolbar({
    required this.status,
    required this.day,
    required this.board,
  });

  final String status;
  final String day;
  final String board;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const statusOptions = [
      'Tất cả',
      'Đã đặt',
      'Đang làm',
      'Hoàn thành',
      'Chờ xác nhận',
      'Đã hủy',
    ];
    const dayOptions = ['Tất cả', 'Hôm nay', 'Ngày mai'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ChoiceChip(
              label: const Text('Lịch hẹn'),
              selected: board == 'Lịch hẹn',
              onSelected: (_) {
                ref.read(appointmentBoardFilterProvider.notifier).state =
                    'Lịch hẹn';
                ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
              },
            ),
            ChoiceChip(
              label: const Text('Đang làm'),
              selected: board == 'Đang làm',
              onSelected: (_) {
                ref.read(appointmentBoardFilterProvider.notifier).state =
                    'Đang làm';
                ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: ref.watch(appointmentSearchQueryProvider),
                onChanged: (value) {
                  ref.read(appointmentSearchQueryProvider.notifier).state =
                      value;
                  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm khách hàng, dịch vụ, thợ hoặc số điện thoại',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () => _openAppointmentEditor(context, ref),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Tạo lịch'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: dayOptions
              .map(
                (option) => ChoiceChip(
                  label: Text(option),
                  selected: option == day,
                  onSelected: (_) {
                    ref.read(appointmentDayFilterProvider.notifier).state =
                        option;
                    ref.read(selectedAppointmentIndexProvider.notifier).state =
                        0;
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: statusOptions
              .map(
                (option) => FilterChip(
                  label: Text(option),
                  selected: option == status,
                  onSelected: (_) {
                    ref.read(appointmentStatusFilterProvider.notifier).state =
                        option;
                    ref.read(selectedAppointmentIndexProvider.notifier).state =
                        0;
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _AppointmentsListPanel extends ConsumerWidget {
  const _AppointmentsListPanel({
    required this.items,
    required this.selectedIndex,
  });

  final List<AppointmentEntry> items;
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
                    'Danh sách lịch hẹn',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${items.length} lịch',
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
                      'Không có lịch hẹn phù hợp với bộ lọc hiện tại.',
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemCount: items.length,
                  itemBuilder: (context, index) => _AppointmentTile(
                    appointment: items[index],
                    selected: index == selectedIndex,
                    onTap: () {
                      ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state =
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

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    required this.selected,
    required this.onTap,
  });

  final AppointmentEntry appointment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(appointment.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.copper : AppColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 8,
          ),
          onTap: onTap,
          leading: Container(
            width: 58,
            decoration: BoxDecoration(
              color: AppColors.avatarFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  appointment.timeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  appointment.dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            appointment.customerName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${appointment.servicesSummary} • ${appointment.staffName}'),
                const SizedBox(height: 4),
                Text(
                  '${appointment.durationLabel} • ${appointment.slotLabel}',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              appointment.status,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppointmentDetailPanel extends ConsumerWidget {
  const _AppointmentDetailPanel({required this.appointment});

  final AppointmentEntry? appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appointment == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chọn một lịch hẹn để xem chi tiết.'),
        ),
      );
    }

    final statusColor = _statusColor(appointment!.status);
    final statusActionLabel = _statusActionLabel(appointment!.status);
    final canCancel = appointment!.status != 'Đã hủy';
    final canUndoComplete = appointment!.status == 'Hoàn thành';
    final linkedInvoice = ref.watch(
      appointmentInvoiceHistoryProvider(appointment!.id),
    );

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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appointment!.customerName,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                appointment!.customerPhone,
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            appointment!.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _AppointmentMetricCard(
                            label: 'Giờ hẹn',
                            value: appointment!.timeLabel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AppointmentMetricCard(
                            label: 'Thời lượng',
                            value: appointment!.durationLabel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AppointmentMetricCard(
                            label: 'Khu vực',
                            value: appointment!.slotLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Dịch vụ',
                      content: appointment!.servicesSummary,
                    ),
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Nhân viên phụ trách',
                      content: appointment!.staffName,
                    ),
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Ngày hẹn',
                      content: appointment!.dateLabel,
                    ),
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Ghi chú',
                      content: appointment!.note,
                    ),
                    const SizedBox(height: 12),
                    _AppointmentInvoiceSection(invoiceState: linkedInvoice),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: statusActionLabel == null
                            ? null
                            : () => _updateAppointmentStatus(
                                context,
                                ref,
                                appointment!,
                              ),
                        child: Text(statusActionLabel ?? 'Đã hoàn tất'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _openAppointmentEditor(
                          context,
                          ref,
                          appointment: appointment,
                        ),
                        child: const Text('Sửa lịch'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        appointment!.status == 'Chờ xác nhận' ||
                            appointment!.status == 'Đã hủy'
                        ? null
                        : () => _sendAppointmentToInvoice(
                            context,
                            ref,
                            appointment!,
                          ),
                    child: const Text('Đưa sang tính tiền'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canUndoComplete
                            ? () async {
                                await ref
                                    .read(appointmentsRepositoryProvider)
                                    .updateAppointmentStatus(
                                      appointment!.id,
                                      'Đang làm',
                                    );
                                if (!context.mounted) {
                                  return;
                                }
                                ref.invalidate(filteredAppointmentsProvider);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Đã hoàn tác về trạng thái Đang làm',
                                    ),
                                  ),
                                );
                              }
                            : null,
                        icon: const Icon(Icons.undo_outlined),
                        label: const Text('Hoàn tác hoàn thành'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canCancel
                            ? () =>
                                  _cancelAppointment(context, ref, appointment!)
                            : null,
                        icon: const Icon(Icons.event_busy_outlined),
                        label: const Text('Hủy lịch'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentInvoiceSection extends StatelessWidget {
  const _AppointmentInvoiceSection({required this.invoiceState});

  final AsyncValue<InvoiceDraft?> invoiceState;

  @override
  Widget build(BuildContext context) {
    return invoiceState.when(
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.panelRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _DetailSection(
        title: 'Hóa đơn liên quan',
        content: 'Không tải được thông tin hóa đơn: $error',
      ),
      data: (invoice) {
        if (invoice == null) {
          return const _DetailSection(
            title: 'Hóa đơn liên quan',
            content: 'Lịch hẹn này chưa có hóa đơn đã thanh toán.',
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.panelRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hóa đơn liên quan',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _AppointmentMetricCard(
                      label: 'Đã thu',
                      value: _currency(invoice.totalAmount),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AppointmentMetricCard(
                      label: 'Thanh toán',
                      value: invoice.paymentMethod,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AppointmentMetricCard(
                      label: 'Số dịch vụ',
                      value: '${invoice.lines.length}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DetailSection(
                title: 'Thời điểm chốt hóa đơn',
                content: invoice.paidAt == null
                    ? 'Chưa thanh toán'
                    : _dateTime(invoice.paidAt!),
              ),
              const SizedBox(height: 12),
              _DetailSection(
                title: 'Dịch vụ đã chốt',
                content: invoice.lines
                    .map((line) => '${line.title} x${line.quantity}')
                    .join(', '),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppointmentMetricCard extends StatelessWidget {
  const _AppointmentMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(20),
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
  State<_AppointmentEditorDialog> createState() =>
      _AppointmentEditorDialogState();
}

class _AppointmentEditorDialogState extends State<_AppointmentEditorDialog> {
  static const List<String> _statusOptions = [
    'Chờ xác nhận',
    'Đã đặt',
    'Đang làm',
    'Hoàn thành',
    'Đã hủy',
  ];

  static const List<String> _dayOptions = ['Hôm nay', 'Ngày mai'];

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
    _durationController = TextEditingController(
      text:
          appointment?.durationMinutes.toString() ??
          _selectedServicesDuration.toString(),
    );
    _slotController = TextEditingController(
      text: appointment?.slotLabel ?? 'Gh? VIP 1',
    );
    _timeController = TextEditingController(
      text: appointment?.timeLabel ?? '10:00',
    );
    _noteController = TextEditingController(text: appointment?.note ?? '');
    _selectedCustomerId = _resolveInitialCustomerId(appointment);
    _status = _statusOptions.contains(appointment?.status)
        ? appointment!.status
        : 'Chờ xác nhận';
    _dayLabel = _dayOptions.contains(appointment?.dateLabel)
        ? appointment!.dateLabel
        : 'Hôm nay';
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
    final selectedServices = _selectedServices;
    final selectedEmployee = _selectedEmployee;

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(isEditing ? 'Sửa lịch hẹn' : 'Tạo lịch hẹn'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 560),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedCustomerId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Khách hàng'),
                  items: widget.customers
                      .map(
                        (customer) => DropdownMenuItem(
                          value: customer.id,
                          child: Text(
                            '${customer.fullName} • ${customer.phone}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Chọn khách hàng có sẵn'
                      : null,
                  onChanged: (value) {
                    setState(() {
                      _selectedCustomerId = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.panelRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    selectedCustomer == null
                        ? 'Chỉ có thể tạo lịch cho khách hàng đã tồn tại trong hệ thống.'
                        : 'SĐT: ${selectedCustomer.phone} • Hạng: ${selectedCustomer.tier}',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),
                FormField<List<String>>(
                  initialValue: _selectedServiceIds,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Chọn ít nhất một dịch vụ có sẵn'
                      : null,
                  builder: (field) {
                    return InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Dịch vụ / gói đã đặt',
                        errorText: field.errorText,
                      ),
                      child: Column(
                        children: [
                          for (final service in widget.services.where(
                            (service) => service.isActive,
                          ))
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _selectedServiceIds.contains(service.id),
                              title: Text(
                                '${service.name} • ${service.priceLabel}',
                              ),
                              subtitle: Text(
                                '${service.category} • ${service.durationLabel}',
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    if (!_selectedServiceIds.contains(
                                      service.id,
                                    )) {
                                      _selectedServiceIds = [
                                        ..._selectedServiceIds,
                                        service.id,
                                      ];
                                    }
                                  } else {
                                    _selectedServiceIds = _selectedServiceIds
                                        .where(
                                          (serviceId) =>
                                              serviceId != service.id,
                                        )
                                        .toList(growable: false);
                                  }
                                  _durationController.text =
                                      _selectedServicesDuration.toString();
                                  field.didChange(_selectedServiceIds);
                                });
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.panelRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    selectedServices.isEmpty
                        ? 'Chỉ có thể đặt lịch bằng dịch vụ đã có trong danh mục.'
                        : 'Đã chọn ${selectedServices.length} dịch vụ • Tổng giá gợi ý $_selectedServicesPriceLabel • Tổng thời lượng $_selectedServicesDuration phút',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmployeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nhân viên phụ trách',
                  ),
                  items: widget.employees
                      .map(
                        (employee) => DropdownMenuItem(
                          value: employee['id']?.toString(),
                          child: Text(
                            '${employee['name']} • ${employee['role']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Chọn nhân viên có sẵn'
                      : null,
                  onChanged: (value) {
                    setState(() {
                      _selectedEmployeeId = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.panelRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    selectedEmployee == null
                        ? 'Chỉ có thể gán lịch cho nhân viên đã có trong hệ thống.'
                        : 'Ca: ${selectedEmployee['shift']} • Vai trò: ${selectedEmployee['role']}',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _dayLabel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Ngày hẹn',
                        ),
                        items: _dayOptions
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
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _dayLabel = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _timeController,
                        decoration: const InputDecoration(labelText: 'Giờ hẹn'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nhập giờ hẹn';
                          }
                          if (!RegExp(
                            r'^\d{2}:\d{2}$',
                          ).hasMatch(value.trim())) {
                            return 'Dùng định dạng HH:mm';
                          }
                          return null;
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
                        controller: _durationController,
                        decoration: const InputDecoration(
                          labelText: 'Thời lượng (phút)',
                        ),
                        validator: (value) {
                          final minutes = int.tryParse(value?.trim() ?? '');
                          if (minutes == null || minutes <= 0) {
                            return 'Nhập số phút hợp lệ';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _slotController,
                        decoration: const InputDecoration(
                          labelText: 'Khu vực / ghế',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Nhập khu vực phục vụ'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: _statusOptions
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      _status = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(isEditing ? 'Lưu lịch' : 'Tạo lịch'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedCustomer = _selectedCustomer;
    final selectedServices = _selectedServices;
    final selectedEmployee = _selectedEmployee;
    if (selectedCustomer == null ||
        selectedServices.isEmpty ||
        selectedEmployee == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    Navigator.of(context).pop(
      AppointmentUpsertInput(
        customerId: selectedCustomer.id,
        serviceIds: selectedServices
            .map((service) => service.id)
            .toList(growable: false),
        employeeId: selectedEmployee['id']!.toString(),
        customerName: selectedCustomer.fullName,
        customerPhone: selectedCustomer.phone,
        serviceName: selectedServices
            .map((service) => service.name)
            .join(' + '),
        staffName: selectedEmployee['name']!.toString(),
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
    if (appointment == null) {
      return widget.customers.isEmpty ? null : widget.customers.first.id;
    }

    for (final customer in widget.customers) {
      if (customer.id == appointment.customerId) {
        return customer.id;
      }
    }

    return widget.customers.isEmpty ? null : widget.customers.first.id;
  }

  List<String> _resolveInitialServiceIds(AppointmentEntry? appointment) {
    if (appointment == null) {
      return const [];
    }

    if (appointment.services.isNotEmpty) {
      return appointment.services
          .map((service) => service.serviceId)
          .toList(growable: false);
    }

    for (final service in widget.services) {
      if (service.id == appointment.serviceId ||
          service.name == appointment.serviceName) {
        return [service.id];
      }
    }

    return const [];
  }

  String? _resolveInitialEmployeeId(AppointmentEntry? appointment) {
    if (appointment == null) {
      final firstEmployee = widget.employees.firstOrNull;
      return firstEmployee?['id']?.toString();
    }

    for (final employee in widget.employees) {
      if (employee['id']?.toString() == appointment.employeeId ||
          employee['name']?.toString() == appointment.staffName) {
        return employee['id']?.toString();
      }
    }

    final firstEmployee = widget.employees.firstOrNull;
    return firstEmployee?['id']?.toString();
  }

  CustomerProfile? get _selectedCustomer {
    final customerId = _selectedCustomerId;
    if (customerId == null) {
      return null;
    }

    for (final customer in widget.customers) {
      if (customer.id == customerId) {
        return customer;
      }
    }

    return null;
  }

  List<ServiceCatalogItem> get _selectedServices {
    final selectedIds = _selectedServiceIds.toSet();
    return widget.services
        .where((service) => selectedIds.contains(service.id))
        .toList(growable: false);
  }

  int get _selectedServicesDuration {
    final selectedServices = _selectedServices;
    if (selectedServices.isEmpty) {
      return 90;
    }

    return selectedServices.fold<int>(
      0,
      (sum, service) => sum + service.durationMinutes,
    );
  }

  String get _selectedServicesPriceLabel {
    final totalPrice = _selectedServices.fold<int>(
      0,
      (sum, service) => sum + service.price,
    );
    return _currency(totalPrice);
  }

  Map<String, Object?>? get _selectedEmployee {
    final employeeId = _selectedEmployeeId;
    if (employeeId == null) {
      return null;
    }

    for (final employee in widget.employees) {
      if (employee['id']?.toString() == employeeId) {
        return employee;
      }
    }

    return null;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'Đang làm':
      return AppColors.warning;
    case 'Hoàn thành':
      return AppColors.success;
    case 'Đã hủy':
      return AppColors.textMuted;
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

final NumberFormat _currencyFormatter = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: '₫',
  decimalDigits: 0,
);

final DateFormat _dateTimeFormatter = DateFormat('dd/MM HH:mm');

String _currency(int value) =>
    _currencyFormatter.format(value).replaceAll(',', '.');

String _dateTime(DateTime value) => _dateTimeFormatter.format(value);
