part of 'appointments_page.dart';

class _DayScheduleCell extends StatelessWidget {
  const _DayScheduleCell({
    required this.width,
    required this.appointments,
    required this.selectedAppointmentId,
    required this.onSelect,
    required this.onCreate,
    required this.onMenuAction,
  });

  final double width;
  final List<AppointmentEntry> appointments;
  final String? selectedAppointmentId;
  final ValueChanged<AppointmentEntry> onSelect;
  final VoidCallback onCreate;
  final void Function(
    AppointmentEntry appointment,
    _AppointmentMenuAction action,
  ) onMenuAction;

  @override
  Widget build(BuildContext context) {
    final appointment = appointments.firstOrNull;
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.workspaceDivider),
          bottom: BorderSide(color: AppColors.workspaceDivider),
        ),
      ),
      child: appointment == null
          ? Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: onCreate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.cardBorder.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: AppColors.textMuted.withValues(alpha: 0.42),
                  ),
                ),
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _DayAppointmentCard(
                    appointment: appointment,
                    selected: appointment.id == selectedAppointmentId,
                    onTap: () => onSelect(appointment),
                    onMenuAction: (action) =>
                        onMenuAction(appointment, action),
                  ),
                ),
                if (appointments.length > 1)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.panelRaised,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        '+${appointments.length - 1}',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

enum _AppointmentMenuAction {
  advance,
  edit,
  checkout,
  cancel,
  undo,
}

class _DayAppointmentCard extends StatelessWidget {
  const _DayAppointmentCard({
    required this.appointment,
    required this.selected,
    required this.onTap,
    required this.onMenuAction,
  });

  final AppointmentEntry appointment;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<_AppointmentMenuAction> onMenuAction;

  @override
  Widget build(BuildContext context) {
    final tone = _statusColor(appointment.status);

    return Tooltip(
      message:
          '${appointment.slotLabel} • ${appointment.durationLabel} • ${appointment.status}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            key: Key('appointment-day-card-${appointment.id}'),
            padding: const EdgeInsets.fromLTRB(8, 5, 2, 5),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                tone.withValues(alpha: selected ? 0.15 : 0.09),
                AppColors.panelRaised,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: 0.72)
                    : tone.withValues(alpha: 0.26),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appointment.timeRangeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: appointment.status,
                            child: _MiniStatusBadge(
                              label: _compactAppointmentStatus(
                                appointment.status,
                              ),
                              tone: tone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        appointment.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              appointment.servicesSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.schedule_outlined,
                            size: 10,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            appointment.durationLabel,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: PopupMenuButton<_AppointmentMenuAction>(
                    tooltip: 'Thao tác nhanh',
                    padding: EdgeInsets.zero,
                    onSelected: onMenuAction,
                    itemBuilder: (context) =>
                        _appointmentMenuItems(appointment),
                    child: const Center(
                      child: Icon(Icons.more_vert_rounded, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _compactAppointmentStatus(String status) {
  switch (status) {
    case 'Chờ xác nhận':
      return 'Chờ';
    case 'Đã đặt':
      return 'Đặt';
    case 'Đã đến':
      return 'Đến';
    case 'Đang làm':
      return 'Làm';
    case 'Hoàn thành':
      return 'Xong';
    case 'Đã hủy':
      return 'Hủy';
    default:
      return status;
  }
}
