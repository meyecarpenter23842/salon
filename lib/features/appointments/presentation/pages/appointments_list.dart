part of 'appointments_page.dart';

class _AppointmentsListPanel extends ConsumerWidget {
  const _AppointmentsListPanel({
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<AppointmentEntry> items;
  final int selectedIndex;
  final ValueChanged<AppointmentEntry> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: [
                  PremiumIconBadge(
                    icon: Icons.view_agenda_outlined,
                    size: 32,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Danh sách lịch',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  _CountBadge(count: items.length),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.workspaceDivider),
          Expanded(
            child: items.isEmpty
                ? const PremiumEmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Chưa có lịch phù hợp',
                    message: 'Đổi bộ lọc hoặc tạo lịch mới để tiếp tục.',
                  )
                : ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final appointment = items[index];
                      return _AppointmentListRow(
                        appointment: appointment,
                        selected: index == selectedIndex,
                        onTap: () => onSelect(appointment),
                        onMenuAction: (action) {
                          _handleAppointmentMenuAction(
                            context,
                            ref,
                            appointment,
                            action,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentListRow extends StatelessWidget {
  const _AppointmentListRow({
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
    return PremiumInteractiveSurface(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.timeRangeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  appointment.dateLabel,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  size: 14,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    appointment.staffName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MiniStatusBadge(label: appointment.status, tone: tone),
          PopupMenuButton<_AppointmentMenuAction>(
            tooltip: 'Thao tác nhanh',
            icon: const Icon(Icons.more_horiz_rounded, size: 18),
            onSelected: onMenuAction,
            itemBuilder: (_) => _appointmentMenuItems(appointment),
          ),
        ],
      ),
    );
  }
}
