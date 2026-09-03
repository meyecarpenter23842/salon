part of 'appointments_page.dart';

List<PopupMenuEntry<_AppointmentMenuAction>> _appointmentMenuItems(
  AppointmentEntry appointment,
) {
  final items = <PopupMenuEntry<_AppointmentMenuAction>>[];
  final actionLabel = _statusActionLabel(appointment.status);
  if (actionLabel != null) {
    items.add(
      PopupMenuItem(
        value: _AppointmentMenuAction.advance,
        child: _PopupActionRow(
          icon: _statusActionIcon(appointment.status),
          label: actionLabel,
        ),
      ),
    );
  }
  if (appointment.status == 'Hoàn thành') {
    items.add(
      const PopupMenuItem(
        value: _AppointmentMenuAction.undo,
        child: _PopupActionRow(
          icon: Icons.undo_outlined,
          label: 'Hoàn tác',
        ),
      ),
    );
  }
  items.add(
    const PopupMenuItem(
      value: _AppointmentMenuAction.edit,
      child: _PopupActionRow(
        icon: Icons.edit_outlined,
        label: 'Chỉnh sửa',
      ),
    ),
  );
  if (appointment.status != 'Chờ xác nhận' &&
      appointment.status != 'Đã hủy') {
    items.add(
      const PopupMenuItem(
        value: _AppointmentMenuAction.checkout,
        child: _PopupActionRow(
          icon: Icons.payments_outlined,
          label: 'Gửi thanh toán',
        ),
      ),
    );
  }
  if (appointment.status != 'Đã hủy') {
    items.add(
      const PopupMenuItem(
        value: _AppointmentMenuAction.cancel,
        child: _PopupActionRow(
          icon: Icons.event_busy_outlined,
          label: 'Hủy lịch',
          danger: true,
        ),
      ),
    );
  }
  return items;
}

class _PopupActionRow extends StatelessWidget {
  const _PopupActionRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tone = danger ? AppColors.danger : AppColors.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 17, color: tone),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: tone)),
      ],
    );
  }
}

class _MiniStatusBadge extends StatelessWidget {
  const _MiniStatusBadge({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
