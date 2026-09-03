part of 'appointments_page.dart';

class _AppointmentDayPanel extends ConsumerWidget {
  const _AppointmentDayPanel({
    required this.items,
    required this.employees,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<AppointmentEntry> items;
  final AsyncValue<List<Map<String, Object?>>> employees;
  final int selectedIndex;
  final ValueChanged<AppointmentEntry> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tooSmallToRenderBoard = constraints.maxHeight < 120;
        return Container(
          key: const Key('appointments-day-board'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: AppColors.surfaceShadow,
          ),
          child: tooSmallToRenderBoard
              ? const SizedBox.expand()
              : Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        child: Row(
                          children: [
                            PremiumIconBadge(
                              icon: Icons.calendar_view_week_outlined,
                              size: 32,
                            ),
                            const SizedBox(width: 9),
                            const Expanded(
                              child: Text(
                                'Lịch theo giờ × nhân viên',
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
                      child: employees.when(
                        loading: () => const PremiumLoadingState(
                          label: 'Đang tải nhân viên…',
                        ),
                        error: (error, _) => PremiumErrorState(
                          title: 'Không tải được nhân viên',
                          message: '$error',
                          onRetry: () =>
                              ref.invalidate(appointmentEmployeesProvider),
                        ),
                        data: (staff) {
                          final selectedEmployeeId =
                              ref.watch(appointmentEmployeeFilterProvider);
                          final visibleStaff = staff
                              .where(
                                (employee) =>
                                    (employee['id']?.toString() ?? '')
                                        .isNotEmpty &&
                                    (selectedEmployeeId == 'all' ||
                                        employee['id']?.toString() ==
                                            selectedEmployeeId),
                              )
                              .toList(growable: false);
                          if (visibleStaff.isEmpty) {
                            return const PremiumEmptyState(
                              icon: Icons.groups_outlined,
                              title: 'Chưa có nhân viên',
                              message:
                                  'Thêm nhân viên trước khi phân lịch theo cột.',
                            );
                          }
                          return _AppointmentDayGrid(
                            items: items,
                            employees: visibleStaff,
                            selectedIndex: selectedIndex,
                            onSelect: onSelect,
                            onCreate: (employee, slotMinutes) {
                              _openAppointmentEditor(
                                context,
                                ref,
                                initialEmployeeId:
                                    employee['id']?.toString(),
                                initialTimeLabel:
                                    _minutesLabel(slotMinutes),
                                initialDayLabel:
                                    ref.read(appointmentDayFilterProvider),
                              );
                            },
                            onMenuAction: (appointment, action) {
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
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        '$count lịch',
        style: TextStyle(
          color: AppColors.info,
          fontSize: 10,
          fontWeight: FontWeight.w800,
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
    required this.onCreate,
    required this.onMenuAction,
  });

  static const double _timeColumnWidth = 66;
  static const double _minEmployeeColumnWidth = 190;
  static const double _headerHeight = 56;
  static const double _rowHeight = 88;

  final List<AppointmentEntry> items;
  final List<Map<String, Object?>> employees;
  final int selectedIndex;
  final ValueChanged<AppointmentEntry> onSelect;
  final void Function(Map<String, Object?> employee, int slotMinutes)
      onCreate;
  final void Function(
    AppointmentEntry appointment,
    _AppointmentMenuAction action,
  ) onMenuAction;

  @override
  Widget build(BuildContext context) {
    final slots = _dayBoardSlots(items, employees);
    final selectedId = items.isEmpty
        ? null
        : items[selectedIndex.clamp(0, items.length - 1)].id;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableForEmployees = math
            .max(0.0, constraints.maxWidth - _timeColumnWidth)
            .toDouble();
        final employeeWidth = math
            .max(
              _minEmployeeColumnWidth,
              availableForEmployees / employees.length,
            )
            .toDouble();
        final totalWidth =
            _timeColumnWidth + employees.length * employeeWidth;

        return SingleChildScrollView(
          primary: false,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(totalWidth, constraints.maxWidth).toDouble(),
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      Container(
                        width: _timeColumnWidth,
                        alignment: Alignment.center,
                        color: AppColors.featureSurface,
                        child: Text(
                          'Thời gian',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final employee in employees)
                        _DayEmployeeHeader(
                          employee: employee,
                          width: employeeWidth,
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: AppColors.workspaceDivider),
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
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 12),
                              decoration: BoxDecoration(
                                color: AppColors.featureSurface,
                                border: Border(
                                  right: BorderSide(
                                    color: AppColors.workspaceDivider,
                                  ),
                                ),
                              ),
                              child: Text(
                                _minutesLabel(slot),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            for (final employee in employees)
                              _DayScheduleCell(
                                width: employeeWidth,
                                appointments: _appointmentsForCell(
                                  items: items,
                                  employee: employee,
                                  slotMinutes: slot,
                                ),
                                selectedAppointmentId: selectedId,
                                onSelect: onSelect,
                                onCreate: () => onCreate(employee, slot),
                                onMenuAction: onMenuAction,
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
      },
    );
  }
}

class _DayEmployeeHeader extends StatelessWidget {
  const _DayEmployeeHeader({
    required this.employee,
    required this.width,
  });

  final Map<String, Object?> employee;
  final double width;

  @override
  Widget build(BuildContext context) {
    final name = employee['name']?.toString() ?? 'Nhân viên';
    final initials = employee['initials']?.toString() ?? _initials(name);
    final role = employee['role']?.toString() ?? '';
    final shift = employee['shift']?.toString() ?? '';

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        border: Border(
          left: BorderSide(color: AppColors.workspaceDivider),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.iconSurface,
            foregroundColor: AppColors.copper,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shift.isEmpty ? role : '$role • $shift',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
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
