part of 'appointments_page.dart';

Future<void> _showAppointmentDetailDialog(
  BuildContext context,
  WidgetRef ref,
  AppointmentEntry appointment,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 680),
        child: _AppointmentDetailSheet(
          appointment: appointment,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

class _AppointmentDetailSheet extends ConsumerWidget {
  const _AppointmentDetailSheet({
    required this.appointment,
    required this.onClose,
  });

  final AppointmentEntry appointment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = _statusColor(appointment.status);
    final statusAction = _statusActionLabel(appointment.status);
    final invoice = ref.watch(
      appointmentInvoiceHistoryProvider(appointment.id),
    );

    return Container(
      key: const Key('appointments-detail-sheet'),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _selectedBorderColor(tone)),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 7, 8),
            child: Row(
              children: [
                _MiniStatusBadge(label: appointment.status, tone: tone),
                const Spacer(),
                if (statusAction != null)
                  Tooltip(
                    message: statusAction,
                    child: IconButton.filledTonal(
                      key: const Key('appointment-status-action'),
                      onPressed: () =>
                          _updateAppointmentStatus(context, ref, appointment),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _statusActionIcon(appointment.status),
                        size: 17,
                      ),
                    ),
                  ),
                IconButton(
                  key: const Key('appointment-edit-action'),
                  tooltip: 'Chỉnh sửa lịch',
                  onPressed: () => _openAppointmentEditor(
                    context,
                    ref,
                    appointment: appointment,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
                if (appointment.status != 'Đã hủy')
                  PopupMenuButton<String>(
                    tooltip: 'Thêm thao tác',
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    onSelected: (value) {
                      if (value == 'undo') {
                        _undoAppointmentComplete(context, ref, appointment);
                      } else if (value == 'cancel') {
                        _cancelAppointment(context, ref, appointment);
                      }
                    },
                    itemBuilder: (_) => [
                      if (appointment.status == 'Hoàn thành')
                        const PopupMenuItem(
                          value: 'undo',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.undo_outlined),
                            title: Text('Hoàn tác về Đang làm'),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.event_busy_outlined,
                            color: AppColors.danger,
                          ),
                          title: Text(
                            'Hủy lịch',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  tooltip: 'Đóng chi tiết',
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.workspaceDivider),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.customerName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _IconValue(
                    icon: Icons.phone_outlined,
                    text: appointment.customerPhone,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('appointment-open-customer'),
                        onPressed: () => openCustomerProfileFromAppointment(
                          ref,
                          appointment,
                        ),
                        icon: const Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                        ),
                        label: const Text('Hồ sơ khách'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('appointment-open-employee'),
                        onPressed: () => openEmployeeProfileFromAppointment(
                          context,
                          ref,
                          appointment,
                        ),
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: const Text('Nhân viên'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('appointment-open-service'),
                        onPressed: () => openServiceFromAppointment(
                          context,
                          ref,
                          appointment,
                        ),
                        icon: const Icon(Icons.content_cut_rounded, size: 16),
                        label: const Text('Dịch vụ'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _DetailInfoTile(
                    icon: Icons.calendar_today_outlined,
                    label: 'Ngày hẹn',
                    value: appointment.dateLabel,
                  ),
                  _DetailInfoTile(
                    icon: Icons.schedule_outlined,
                    label: 'Thời gian',
                    value:
                        '${appointment.timeRangeLabel} (${appointment.durationLabel})',
                  ),
                  _DetailInfoTile(
                    icon: Icons.badge_outlined,
                    label: 'Nhân viên',
                    value: appointment.staffName,
                  ),
                  _DetailInfoTile(
                    icon: Icons.chair_outlined,
                    label: 'Khu vực / ghế',
                    value: appointment.slotLabel,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Dịch vụ',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _ServiceSummaryBlock(appointment: appointment),
                  const SizedBox(height: 12),
                  Text(
                    'Ghi chú',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.featureSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Text(
                      appointment.note.trim().isEmpty
                          ? 'Không có ghi chú'
                          : appointment.note,
                      style: TextStyle(
                        color: appointment.note.trim().isEmpty
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        height: 1.4,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AppointmentInvoiceSummary(invoiceState: invoice),
                  if (appointment.status != 'Chờ xác nhận' &&
                      appointment.status != 'Đã hủy') ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const Key('appointment-open-checkout'),
                      onPressed: () =>
                          _sendAppointmentToInvoice(context, ref, appointment),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Mở tính tiền'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _selectedBorderColor(Color tone) =>
    tone.withValues(alpha: AppColors.isLight ? 0.32 : 0.42);

class _IconValue extends StatelessWidget {
  const _IconValue({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _DetailInfoTile extends StatelessWidget {
  const _DetailInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.iconSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: AppColors.copper),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSummaryBlock extends StatelessWidget {
  const _ServiceSummaryBlock({required this.appointment});

  final AppointmentEntry appointment;

  @override
  Widget build(BuildContext context) {
    final total = appointment.services.fold<int>(
      0,
      (sum, service) => sum + service.totalPrice,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          if (appointment.services.isEmpty)
            Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.content_cut_rounded,
                  size: 32,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    appointment.serviceName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          else
            for (
              var index = 0;
              index < appointment.services.length;
              index++
            ) ...[
              Row(
                children: [
                  const PremiumIconBadge(
                    icon: Icons.content_cut_rounded,
                    size: 30,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      appointment.services[index].title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _currency(appointment.services[index].totalPrice),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (index != appointment.services.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Divider(height: 1, color: AppColors.workspaceDivider),
                ),
            ],
          if (appointment.services.isNotEmpty && total > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _currency(total),
                style: TextStyle(
                  color: AppColors.copper,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
