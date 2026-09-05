from pathlib import Path


def replace_block(text: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:]


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise RuntimeError(f'marker not found: {old[:120]!r}')
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Appointments: compact command bar + status counters, board gets the height.
# ---------------------------------------------------------------------------
path = Path('lib/features/appointments/presentation/pages/appointments_page.dart')
text = path.read_text()
old = '''            _AppointmentCommandBar(
              key: const Key('appointments-premium-header'),
              day: day,
              onCreate: () => _openAppointmentEditor(context, ref),
            ),
            const SizedBox(height: 10),
            _AppointmentStatsStrip(items: items),
            const SizedBox(height: 10),
            _AppointmentToolbar(
              status: status,
              day: day,
              board: board,
              employees: employees,
            ),
            const SizedBox(height: 10),
'''
new = '''            _AppointmentCommandBar(
              key: const Key('appointments-premium-header'),
              day: day,
              board: board,
              employees: employees,
              onCreate: () => _openAppointmentEditor(context, ref),
            ),
            const SizedBox(height: 8),
            _AppointmentToolbar(
              status: status,
              day: day,
            ),
            const SizedBox(height: 8),
'''
text = replace_once(text, old, new)
path.write_text(text)


path = Path('lib/features/appointments/presentation/pages/appointments_controls.dart')
text = path.read_text()
command_bar = r'''class _AppointmentCommandBar extends ConsumerWidget {
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
                          .state = 0;
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
                          .state = 0;
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
                      ref
                          .read(selectedAppointmentIndexProvider.notifier)
                          .state = 0;
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
                            .state = 0;
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
                          ref.read(appointmentDayFilterProvider.notifier).state =
                              value;
                          ref
                              .read(selectedAppointmentIndexProvider.notifier)
                              .state = 0;
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

'''
text = replace_block(
    text,
    'class _AppointmentCommandBar extends ConsumerWidget {',
    'class _AppointmentStatsStrip extends StatelessWidget {',
    command_bar,
)

status_toolbar = r'''class _AppointmentToolbar extends ConsumerWidget {
  const _AppointmentToolbar({
    required this.status,
    required this.day,
  });

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
    const displayLabels = <String, String>{
      'Đang làm': 'Đang phục vụ',
    };

    final employeeFilter = ref.watch(appointmentEmployeeFilterProvider);
    final query = ref.watch(appointmentSearchQueryProvider).trim().toLowerCase();
    final allState = ref.watch(appointmentsViewProvider);
    final allItems = allState.asData?.value ?? const <AppointmentEntry>[];
    final relevant = allItems.where((item) {
      final matchesDay = day == 'Tất cả' || item.dateLabel == day;
      final matchesEmployee =
          employeeFilter == 'all' || item.employeeId == employeeFilter;
      final matchesQuery = query.isEmpty ||
          [
            item.customerName,
            item.serviceName,
            item.staffName,
            item.customerPhone,
          ].any((value) => value.toLowerCase().contains(query));
      return matchesDay && matchesEmployee && matchesQuery;
    }).toList(growable: false);

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
                label:
                    '${displayLabels[option] ?? option} ${countFor(option)}',
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

'''
text = replace_block(
    text,
    'class _AppointmentStatsStrip extends StatelessWidget {',
    'class _DayFilterDropdown extends StatelessWidget {',
    status_toolbar,
)
path.write_text(text)


# Appointment detail: actions in header, no fixed action footer.
path = Path('lib/features/appointments/presentation/pages/appointments_detail_sheet.dart')
text = path.read_text()
detail_class = r'''class _AppointmentDetailSheet extends ConsumerWidget {
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
    final invoice =
        ref.watch(appointmentInvoiceHistoryProvider(appointment.id));

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
                      onPressed: () => _updateAppointmentStatus(
                        context,
                        ref,
                        appointment,
                      ),
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
                        onPressed: () =>
                            openCustomerProfileFromAppointment(ref, appointment),
                        icon: const Icon(Icons.person_outline_rounded, size: 16),
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _ServiceSummaryBlock(appointment: appointment),
                  const SizedBox(height: 12),
                  Text(
                    'Ghi chú',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
                      onPressed: () => _sendAppointmentToInvoice(
                        context,
                        ref,
                        appointment,
                      ),
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

'''
text = replace_block(
    text,
    'class _AppointmentDetailSheet extends ConsumerWidget {',
    'Color _selectedBorderColor(Color tone)',
    detail_class,
)
path.write_text(text)


# ---------------------------------------------------------------------------
# POS: remove duplicated inner hero, keep 3 operation zones, compact totals.
# ---------------------------------------------------------------------------
path = Path('lib/features/invoices/presentation/pages/invoices_pos_page.dart')
text = path.read_text()
text = replace_once(
    text,
    '            _PosHeader(draft: draft, dense: dense),',
    '''            _PosHeader(
              draft: draft,
              history: history,
              customers: customers,
              dense: dense,
            ),''',
)
text = replace_once(
    text,
    '''                    child: _CheckoutPanel(
                      draft: draft,
                      history: history,
                      customers: customers,
                      selectedCustomer: selectedCustomer,
                      dense: dense,
                    ),''',
    '''                    child: _CheckoutPanel(
                      draft: draft,
                      customers: customers,
                      selectedCustomer: selectedCustomer,
                      dense: dense,
                    ),''',
)
header_class = r'''class _PosHeader extends StatelessWidget {
  const _PosHeader({
    required this.draft,
    required this.history,
    required this.customers,
    required this.dense,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('billing-premium-header'),
      height: 42,
      child: Row(
        children: [
          PremiumStatusPill(
            label: draft.isPaid ? 'Đã thanh toán' : 'Đang lập bill',
            tone: draft.isPaid ? AppColors.success : AppColors.copper,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${draft.lines.length} mục · ${_currency(draft.subtotal)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!dense) ...[
            const SizedBox(width: 8),
            Text(
              '• ${draft.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
            ),
          ],
          const Spacer(),
          OutlinedButton.icon(
            key: const Key('billing-history-action'),
            onPressed: () => _showInvoiceHistoryDialog(
              context,
              history,
              customers,
            ),
            icon: const Icon(Icons.history_rounded, size: 17),
            label: const Text('Lịch sử hóa đơn'),
          ),
        ],
      ),
    );
  }
}

'''
text = replace_block(text, 'class _PosHeader extends StatelessWidget {', 'String _currency(int value)', header_class)
path.write_text(text)


path = Path('lib/features/invoices/presentation/pages/pos_bill_panel.dart')
text = path.read_text()
bill_panel = r'''Future<void> _clearInvoiceDraft(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
  if (draft.isPaid || draft.lines.isEmpty) return;
  final repository = ref.read(invoicesRepositoryProvider);
  for (final line in List<InvoiceDraftLine>.from(draft.lines)) {
    await repository.removeInvoiceLine(line.id);
  }
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Đã xóa toàn bộ mục khỏi bill')),
  );
}

class _InvoiceDraftPanel extends ConsumerWidget {
  const _InvoiceDraftPanel({required this.draft, required this.dense});

  final InvoiceDraft draft;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      key: const Key('billing-pos-bill'),
      icon: Icons.receipt_long_outlined,
      title: 'Bill',
      subtitle: draft.isPaid
          ? '${draft.lines.length} mục · đã khóa'
          : '${draft.lines.length} mục · chỉnh trực tiếp',
      padding: EdgeInsets.all(dense ? 12 : 14),
      trailing: draft.isPaid
          ? Tooltip(
              message: 'Hóa đơn đã thanh toán',
              child: Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            )
          : draft.lines.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => _clearInvoiceDraft(context, ref, draft),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Xóa tất cả'),
                ),
      child: draft.lines.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Bill đang trống',
              message: 'Chọn dịch vụ hoặc sản phẩm ở cột giữa để thêm nhanh.',
            )
          : Column(
              children: [
                const _InvoiceTableHeader(),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.separated(
                    primary: false,
                    itemCount: draft.lines.length,
                    separatorBuilder: (_, _) => const PremiumDivider(),
                    itemBuilder: (context, index) => _InvoiceLineRow(
                      line: draft.lines[index],
                      isLocked: draft.isPaid,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _BillFooter(draft: draft),
              ],
            ),
    );
  }
}

'''
text = replace_block(text, 'class _InvoiceDraftPanel extends ConsumerWidget {', 'class _InvoiceTableHeader extends StatelessWidget {', bill_panel)
path.write_text(text)


path = Path('lib/features/invoices/presentation/pages/pos_checkout_panel.dart')
text = path.read_text()
checkout_panel = r'''class _CheckoutPanel extends ConsumerWidget {
  const _CheckoutPanel({
    required this.draft,
    required this.customers,
    required this.selectedCustomer,
    required this.dense,
  });

  final InvoiceDraft draft;
  final List<CustomerProfile> customers;
  final CustomerProfile? selectedCustomer;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerLocked = draft.isPaid || draft.appointmentId != null;

    return PremiumSectionCard(
      key: const Key('billing-pos-checkout'),
      icon: Icons.account_balance_wallet_outlined,
      title: 'Khách + Thanh toán',
      subtitle: draft.appointmentId != null
          ? 'Khách đã khóa theo lịch hẹn'
          : 'Chọn khách và chốt bill tại đây',
      padding: EdgeInsets.all(dense ? 12 : 14),
      trailing: Tooltip(
        message: draft.appointmentId != null
            ? 'Bill được tạo từ lịch hẹn'
            : 'Thanh toán tại quầy',
        child: Icon(
          draft.appointmentId != null
              ? Icons.event_available_outlined
              : Icons.point_of_sale_outlined,
          size: 18,
          color: AppColors.textMuted,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CustomerSummaryCard(
            customer: selectedCustomer,
            locked: customerLocked,
            onChange: customerLocked
                ? null
                : () => _showCustomerPickerDialog(
                      context,
                      ref,
                      customers,
                      draft.customerId,
                    ),
          ),
          SizedBox(height: dense ? 9 : 11),
          _CheckoutAmountSummary(draft: draft),
          SizedBox(height: dense ? 9 : 11),
          Text(
            'Phương thức thanh toán',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 7),
          _PaymentMethodSelector(
            selected: draft.paymentMethod,
            locked: draft.isPaid,
            onSelected: (method) =>
                _updateInvoicePaymentMethod(context, ref, method),
          ),
          if (draft.paidAt != null) ...[
            const SizedBox(height: 9),
            PremiumStatusPill(
              label:
                  'Đã thanh toán ${draft.paidAt!.hour.toString().padLeft(2, '0')}:'
                  '${draft.paidAt!.minute.toString().padLeft(2, '0')}',
              tone: AppColors.success,
            ),
          ],
          SizedBox(height: dense ? 9 : 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: draft.isPaid || draft.lines.isEmpty
                  ? null
                  : () => _checkoutInvoice(context, ref, draft),
              icon: Icon(
                draft.isPaid
                    ? Icons.check_circle_outline_rounded
                    : Icons.payments_outlined,
              ),
              label: Text(
                draft.isPaid
                    ? 'Đã thanh toán'
                    : 'Thanh toán ${_currency(draft.totalAmount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 7),
          _CheckoutQuickActions(
            draft: draft,
            selectedCustomer: selectedCustomer,
          ),
        ],
      ),
    );
  }
}

'''
text = replace_block(text, 'class _CheckoutPanel extends ConsumerWidget {', 'class _CustomerSummaryCard extends StatelessWidget {', checkout_panel)

amount_summary = r'''class _CheckoutAmountSummary extends StatelessWidget {
  const _CheckoutAmountSummary({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('billing-pos-total-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _AmountLine(label: 'Tạm tính', value: _currency(draft.subtotal)),
          const SizedBox(height: 4),
          _AmountLine(
            label: 'Giảm giá',
            value: _currency(draft.discountAmount),
          ),
          const SizedBox(height: 6),
          const PremiumDivider(),
          const SizedBox(height: 7),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tổng cộng',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                _currency(draft.totalAmount),
                style: TextStyle(
                  color: AppColors.copper,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!draft.isPaid) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Sửa giảm giá toàn bill',
                  child: IconButton(
                    onPressed: () => _openDiscountEditor(context, refPlaceholder, draft),
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

'''
# Amount editor needs WidgetRef, so make the summary a ConsumerWidget before writing it.
amount_summary = amount_summary.replace(
    'class _CheckoutAmountSummary extends StatelessWidget {',
    'class _CheckoutAmountSummary extends ConsumerWidget {',
).replace(
    '  Widget build(BuildContext context) {',
    '  Widget build(BuildContext context, WidgetRef ref) {',
    1,
).replace('refPlaceholder', 'ref')
text = replace_block(text, 'class _TotalHero extends StatelessWidget {', 'class _AmountLine extends StatelessWidget {', amount_summary)

quick_actions = r'''class _CheckoutQuickActions extends StatelessWidget {
  const _CheckoutQuickActions({
    required this.draft,
    required this.selectedCustomer,
  });

  final InvoiceDraft draft;
  final CustomerProfile? selectedCustomer;

  @override
  Widget build(BuildContext context) {
    final enabled = draft.lines.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Text(
            draft.isPaid ? 'Bill đã khóa' : 'Công cụ nhanh',
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ),
        Tooltip(
          message: 'QR thanh toán',
          child: IconButton(
            onPressed: enabled
                ? () => _showPaymentQrDialog(context, draft, selectedCustomer)
                : null,
            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
          ),
        ),
        Tooltip(
          message: 'Xuất PDF hóa đơn',
          child: IconButton(
            onPressed: enabled
                ? () => _exportInvoicePdf(context, draft, selectedCustomer)
                : null,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          ),
        ),
      ],
    );
  }
}

'''
text = replace_block(text, 'class _CheckoutQuickActions extends StatelessWidget {', 'Future<void> _showInvoiceHistoryDialog(', quick_actions)
path.write_text(text)


# ---------------------------------------------------------------------------
# Regression expectations for the approved operational layout.
# ---------------------------------------------------------------------------
path = Path('test/operation_ui_batch_test.dart')
text = path.read_text()
text = replace_once(
    text,
    '''      expect(
        find.byKey(const Key('appointments-ux-toolbar')),
        findsOneWidget,
      );''',
    '''      expect(
        find.byKey(const Key('appointments-ux-toolbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appointments-status-strip')),
        findsOneWidget,
      );''',
)
text = replace_once(
    text,
    '''      expect(
        find.byKey(const Key('billing-premium-workspace')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);''',
    '''      expect(
        find.byKey(const Key('billing-premium-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('billing-history-action')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('billing-pos-total-summary')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);''',
)
path.write_text(text)

path = Path('test/invoices_pos_layout_test.dart')
text = path.read_text()
text = replace_once(
    text,
    '''      expect(find.text('Khách + Thanh toán'), findsOneWidget);
      expect(
        tester.takeException(),''',
    '''      expect(find.text('Khách + Thanh toán'), findsOneWidget);
      expect(find.text('Tính tiền'), findsNothing);
      expect(
        find.byKey(const Key('billing-pos-total-summary')),
        findsOneWidget,
      );
      expect(
        tester.takeException(),''',
)
path.write_text(text)
