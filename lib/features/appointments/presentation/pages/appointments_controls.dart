part of 'appointments_page.dart';

class _AppointmentCommandBar extends ConsumerWidget {
  const _AppointmentCommandBar({
    super.key,
    required this.day,
    required this.board,
    required this.employees,
    required this.onCreate,
  });

  final String day;
  final String board;
  final AsyncValue<List<Map<String, Object?>>> employees;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeFilter = ref.watch(appointmentEmployeeFilterProvider);
    final query = ref.watch(appointmentSearchQueryProvider);

    Widget dateNavigator() {
      final targetDate = _dateForDayLabel(day);
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2),
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
                      ref.read(appointmentDayFilterProvider.notifier).state =
                          'Hôm nay';
                      ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state =
                          0;
                    },
              icon: const Icon(Icons.chevron_left_rounded),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
            const Icon(Icons.calendar_today_outlined, size: 14),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                day == 'Tất cả' ? 'Tất cả ngày' : _displayDate(targetDate),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ngày mai',
              onPressed: day == 'Ngày mai'
                  ? null
                  : () {
                      ref.read(appointmentDayFilterProvider.notifier).state =
                          'Ngày mai';
                      ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state =
                          0;
                    },
              icon: const Icon(Icons.chevron_right_rounded),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    Widget todayButton() => SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: day == 'Hôm nay'
            ? null
            : () {
                ref.read(appointmentDayFilterProvider.notifier).state =
                    'Hôm nay';
                ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
              },
        child: const Text('Hôm nay'),
      ),
    );

    Widget viewToggle() => SizedBox(
      height: 40,
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'Ngày',
            icon: Icon(Icons.calendar_view_day_outlined, size: 16),
            label: Text('Ngày'),
          ),
          ButtonSegment(
            value: 'Danh sách',
            icon: Icon(Icons.view_agenda_outlined, size: 16),
            label: Text('Danh sách'),
          ),
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
      ),
    );

    Widget employeePicker() => _EmployeeFilterDropdown(
      employees: employees,
      selectedId: employeeFilter,
      onChanged: (value) {
        ref.read(appointmentEmployeeFilterProvider.notifier).state = value;
        ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
      },
    );

    Widget searchField() => TextFormField(
      key: ValueKey(query),
      initialValue: query,
      onChanged: (value) {
        ref.read(appointmentSearchQueryProvider.notifier).state = value;
        ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
      },
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        hintText: 'Tìm khách, dịch vụ, thợ hoặc số điện thoại…',
        suffixIcon: query.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () {
                  ref.read(appointmentSearchQueryProvider.notifier).state = '';
                  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                },
                icon: const Icon(Icons.close_rounded, size: 17),
              ),
      ),
    );

    Widget createButton() => SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Tạo lịch'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final singleRow = constraints.maxWidth >= 1180;
        if (singleRow) {
          return SizedBox(
            height: 42,
            child: Row(
              children: [
                SizedBox(width: 220, child: dateNavigator()),
                const SizedBox(width: 8),
                todayButton(),
                const SizedBox(width: 8),
                SizedBox(width: 210, child: viewToggle()),
                if (board == 'Danh sách') ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: _DayFilterDropdown(
                      selectedDay: day,
                      onChanged: (value) {
                        ref.read(appointmentDayFilterProvider.notifier).state =
                            value;
                        ref
                                .read(selectedAppointmentIndexProvider.notifier)
                                .state =
                            0;
                      },
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                SizedBox(width: 180, child: employeePicker()),
                const SizedBox(width: 8),
                Expanded(child: searchField()),
                const SizedBox(width: 8),
                createButton(),
              ],
            ),
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  SizedBox(width: 220, child: dateNavigator()),
                  const SizedBox(width: 8),
                  todayButton(),
                  const SizedBox(width: 8),
                  SizedBox(width: 210, child: viewToggle()),
                  const Spacer(),
                  createButton(),
                ],
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  if (board == 'Danh sách') ...[
                    SizedBox(
                      width: 120,
                      child: _DayFilterDropdown(
                        selectedDay: day,
                        onChanged: (value) {
                          ref
                                  .read(appointmentDayFilterProvider.notifier)
                                  .state =
                              value;
                          ref
                                  .read(
                                    selectedAppointmentIndexProvider.notifier,
                                  )
                                  .state =
                              0;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  SizedBox(width: 190, child: employeePicker()),
                  const SizedBox(width: 8),
                  Expanded(child: searchField()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppointmentToolbar extends ConsumerWidget {
  const _AppointmentToolbar({required this.status, required this.day});

  final String status;
  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const statuses = [
      'Tất cả',
      'Đã đặt',
      'Chờ xác nhận',
      'Đã đến',
      'Đang làm',
      'Hoàn thành',
      'Đã hủy',
    ];
    const displayLabels = <String, String>{'Đang làm': 'Đang phục vụ'};

    final employeeFilter = ref.watch(appointmentEmployeeFilterProvider);
    final query = ref
        .watch(appointmentSearchQueryProvider)
        .trim()
        .toLowerCase();
    final allState = ref.watch(appointmentsViewProvider);
    final allItems = allState.asData?.value ?? const <AppointmentEntry>[];
    final relevant = allItems
        .where((item) {
          final matchesDay = day == 'Tất cả' || item.dateLabel == day;
          final matchesEmployee =
              employeeFilter == 'all' || item.employeeId == employeeFilter;
          final matchesQuery =
              query.isEmpty ||
              [
                item.customerName,
                item.serviceName,
                item.staffName,
                item.customerPhone,
              ].any((value) => value.toLowerCase().contains(query));
          return matchesDay && matchesEmployee && matchesQuery;
        })
        .toList(growable: false);

    int countFor(String option) => option == 'Tất cả'
        ? relevant.length
        : relevant.where((item) => item.status == option).length;

    return SizedBox(
      key: const Key('appointments-ux-toolbar'),
      height: 34,
      child: SingleChildScrollView(
        primary: false,
        scrollDirection: Axis.horizontal,
        child: Row(
          key: const Key('appointments-status-strip'),
          children: [
            for (final option in statuses) ...[
              _StatusFilterChip(
                label: '${displayLabels[option] ?? option} ${countFor(option)}',
                selected: option == status,
                tone: option == 'Tất cả'
                    ? AppColors.copper
                    : _statusColor(option),
                onTap: () {
                  ref.read(appointmentStatusFilterProvider.notifier).state =
                      option;
                  ref.read(selectedAppointmentIndexProvider.notifier).state = 0;
                },
              ),
              const SizedBox(width: 7),
            ],
          ],
        ),
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
                child: Text(option, overflow: TextOverflow.ellipsis),
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
            value: staff.any((item) => item['id']?.toString() == selectedId)
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
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
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
