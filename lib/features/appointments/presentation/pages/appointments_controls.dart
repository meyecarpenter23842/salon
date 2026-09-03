part of 'appointments_page.dart';

class _AppointmentCommandBar extends ConsumerWidget {
  const _AppointmentCommandBar({
    super.key,
    required this.day,
    required this.onCreate,
  });

  final String day;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDate = _dateForDayLabel(day);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.panelRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Hôm nay',
                  onPressed: day == 'Hôm nay'
                      ? null
                      : () {
                          ref
                              .read(appointmentDayFilterProvider.notifier)
                              .state = 'Hôm nay';
                          ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state = 0;
                        },
                  icon: const Icon(Icons.chevron_left_rounded),
                  iconSize: 19,
                  visualDensity: VisualDensity.compact,
                ),
                const Icon(Icons.calendar_today_outlined, size: 15),
                const SizedBox(width: 8),
                Text(
                  day == 'Tất cả' ? 'Tất cả ngày' : _displayDate(targetDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  tooltip: 'Ngày mai',
                  onPressed: day == 'Ngày mai'
                      ? null
                      : () {
                          ref
                              .read(appointmentDayFilterProvider.notifier)
                              .state = 'Ngày mai';
                          ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state = 0;
                        },
                  icon: const Icon(Icons.chevron_right_rounded),
                  iconSize: 19,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Tạo lịch'),
          ),
        ],
      ),
    );
  }
}

class _AppointmentStatsStrip extends StatelessWidget {
  const _AppointmentStatsStrip({required this.items});

  final List<AppointmentEntry> items;

  @override
  Widget build(BuildContext context) {
    final stats = <_StatData>[
      _StatData(
        icon: Icons.event_available_outlined,
        label: 'Lịch hôm nay',
        value: items.length,
        tone: AppColors.copper,
      ),
      _StatData(
        icon: Icons.verified_outlined,
        label: 'Đã đặt',
        value: items.where((item) => item.status == 'Đã đặt').length,
        tone: AppColors.info,
      ),
      _StatData(
        icon: Icons.notifications_active_outlined,
        label: 'Chờ xác nhận',
        value: items.where((item) => item.status == 'Chờ xác nhận').length,
        tone: AppColors.warning,
      ),
      _StatData(
        icon: Icons.content_cut_rounded,
        label: 'Đang phục vụ',
        value: items.where((item) => item.status == 'Đang làm').length,
        tone: AppColors.info,
      ),
      _StatData(
        icon: Icons.task_alt_outlined,
        label: 'Hoàn thành',
        value: items.where((item) => item.status == 'Hoàn thành').length,
        tone: AppColors.success,
      ),
    ];

    return SizedBox(
      height: 68,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minCardWidth = constraints.maxWidth >= 1200 ? 160.0 : 150.0;
          return SingleChildScrollView(
            primary: false,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  SizedBox(
                    width: math.max(
                      minCardWidth,
                      (constraints.maxWidth - 40) / stats.length,
                    ).toDouble(),
                    child: _CompactStatCard(data: stats[index]),
                  ),
                  if (index != stats.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatData {
  const _StatData({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color tone;
}

class _CompactStatCard extends StatelessWidget {
  const _CompactStatCard({required this.data});

  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: Row(
        children: [
          PremiumIconBadge(icon: data.icon, size: 34, tone: data.tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.value}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
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

class _AppointmentToolbar extends ConsumerWidget {
  const _AppointmentToolbar({
    required this.status,
    required this.day,
    required this.board,
    required this.employees,
  });

  final String status;
  final String day;
  final String board;
  final AsyncValue<List<Map<String, Object?>>> employees;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const statuses = [
      'Tất cả',
      'Chờ xác nhận',
      'Đã đặt',
      'Đã đến',
      'Đang làm',
      'Hoàn thành',
      'Đã hủy',
    ];
    final employeeFilter = ref.watch(appointmentEmployeeFilterProvider);
    final query = ref.watch(appointmentSearchQueryProvider);
    final hasFilter = status != 'Tất cả' ||
        employeeFilter != 'all' ||
        query.trim().isNotEmpty ||
        day == 'Tất cả';

    return Container(
      key: const Key('appointments-ux-toolbar'),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(query),
                    initialValue: query,
                    onChanged: (value) {
                      ref
                          .read(appointmentSearchQueryProvider.notifier)
                          .state = value;
                      ref
                          .read(selectedAppointmentIndexProvider.notifier)
                          .state = 0;
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 19),
                      hintText: 'Tìm khách, dịch vụ, thợ hoặc số điện thoại…',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 220,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'Ngày',
                        icon: Icon(Icons.calendar_view_day_outlined, size: 17),
                        label: Text('Ngày'),
                      ),
                      ButtonSegment(
                        value: 'Danh sách',
                        icon: Icon(Icons.view_agenda_outlined, size: 17),
                        label: Text('Danh sách'),
                      ),
                    ],
                    selected: {board},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      final nextMode = selection.first;
                      ref
                          .read(appointmentBoardFilterProvider.notifier)
                          .state = nextMode;
                      if (nextMode == 'Ngày' && day == 'Tất cả') {
                        ref
                            .read(appointmentDayFilterProvider.notifier)
                            .state = 'Hôm nay';
                      }
                      ref
                          .read(selectedAppointmentIndexProvider.notifier)
                          .state = 0;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                if (board == 'Danh sách') ...[
                  SizedBox(
                    width: 120,
                    child: _DayFilterDropdown(
                      selectedDay: day,
                      onChanged: (value) {
                        ref
                            .read(appointmentDayFilterProvider.notifier)
                            .state = value;
                        ref
                            .read(selectedAppointmentIndexProvider.notifier)
                            .state = 0;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: 190,
                  child: _EmployeeFilterDropdown(
                    employees: employees,
                    selectedId: employeeFilter,
                    onChanged: (value) {
                      ref
                          .read(appointmentEmployeeFilterProvider.notifier)
                          .state = value;
                      ref
                          .read(selectedAppointmentIndexProvider.notifier)
                          .state = 0;
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: hasFilter ? 'Xóa bộ lọc' : 'Bộ lọc',
                  child: IconButton(
                    onPressed: hasFilter
                        ? () {
                            ref
                                .read(
                                  appointmentStatusFilterProvider.notifier,
                                )
                                .state = 'Tất cả';
                            ref
                                .read(
                                  appointmentDayFilterProvider.notifier,
                                )
                                .state =
                                    board == 'Danh sách' ? 'Tất cả' : 'Hôm nay';
                            ref
                                .read(
                                  appointmentEmployeeFilterProvider.notifier,
                                )
                                .state = 'all';
                            ref
                                .read(
                                  appointmentSearchQueryProvider.notifier,
                                )
                                .state = '';
                            ref
                                .read(
                                  selectedAppointmentIndexProvider.notifier,
                                )
                                .state = 0;
                          }
                        : null,
                    icon: Icon(
                      hasFilter
                          ? Icons.filter_alt_off_outlined
                          : Icons.filter_alt_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 30,
            child: SingleChildScrollView(
              primary: false,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in statuses) ...[
                    _StatusFilterChip(
                      label: option,
                      selected: option == status,
                      tone: option == 'Tất cả'
                          ? AppColors.copper
                          : _statusColor(option),
                      onTap: () {
                        ref
                            .read(appointmentStatusFilterProvider.notifier)
                            .state = option;
                        ref
                            .read(selectedAppointmentIndexProvider.notifier)
                            .state = 0;
                      },
                    ),
                    const SizedBox(width: 7),
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

class _DayFilterDropdown extends StatelessWidget {
  const _DayFilterDropdown({
    required this.selectedDay,
    required this.onChanged,
  });

  final String selectedDay;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const days = ['Tất cả', 'Hôm nay', 'Ngày mai'];
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AppColors.fieldShell,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: days.contains(selectedDay) ? selectedDay : 'Hôm nay',
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: [
            for (final option in days)
              DropdownMenuItem(
                value: option,
                child: Text(
                  option,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _EmployeeFilterDropdown extends StatelessWidget {
  const _EmployeeFilterDropdown({
    required this.employees,
    required this.selectedId,
    required this.onChanged,
  });

  final AsyncValue<List<Map<String, Object?>>> employees;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.fieldShell,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: employees.when(
        loading: () => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, _) => const Row(
          children: [
            Icon(Icons.person_outline, size: 17),
            SizedBox(width: 7),
            Expanded(child: Text('Nhân viên')),
          ],
        ),
        data: (staff) => DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: staff.any(
                    (item) => item['id']?.toString() == selectedId)
                ? selectedId
                : 'all',
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            items: [
              const DropdownMenuItem(
                value: 'all',
                child: Text('Tất cả nhân viên'),
              ),
              for (final employee in staff)
                DropdownMenuItem(
                  value: employee['id']?.toString(),
                  child: Text(
                    employee['name']?.toString() ?? 'Nhân viên',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? tone.withValues(alpha: AppColors.isLight ? 0.12 : 0.18)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != 'Tất cả') ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? tone : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
