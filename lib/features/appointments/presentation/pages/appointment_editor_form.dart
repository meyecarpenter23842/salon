part of 'appointments_page.dart';

class _AppointmentEditorDialog extends StatefulWidget {
  const _AppointmentEditorDialog({
    required this.customers,
    required this.services,
    required this.employees,
    required this.onCreateCustomer,
    this.appointment,
    this.initialEmployeeId,
    this.initialTimeLabel,
    this.initialDayLabel,
    this.mode = AppointmentEditorMode.appointment,
  });

  final AppointmentEntry? appointment;
  final List<CustomerProfile> customers;
  final List<ServiceCatalogItem> services;
  final List<Map<String, Object?>> employees;
  final Future<CustomerProfile> Function(CustomerUpsertInput input)
      onCreateCustomer;
  final String? initialEmployeeId;
  final String? initialTimeLabel;
  final String? initialDayLabel;
  final AppointmentEditorMode mode;

  @override
  State<_AppointmentEditorDialog> createState() =>
      _AppointmentEditorDialogState();
}

class _AppointmentEditorDialogState
    extends State<_AppointmentEditorDialog> {
  static const _statusOptions = [
    'Chờ xác nhận',
    'Đã đặt',
    'Đã đến',
    'Đang làm',
    'Hoàn thành',
    'Đã hủy',
  ];
  static const _dayOptions = ['Hôm nay', 'Ngày mai'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _durationController;
  late final TextEditingController _slotController;
  late final TextEditingController _timeController;
  late final TextEditingController _noteController;
  late List<CustomerProfile> _customers;
  String? _selectedCustomerId;
  late List<String> _selectedServiceIds;
  String? _selectedEmployeeId;
  late String _status;
  late String _dayLabel;
  bool _isSubmitting = false;

  bool get _isReceive =>
      widget.mode == AppointmentEditorMode.receive && widget.appointment == null;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    _customers = List<CustomerProfile>.of(widget.customers);
    _selectedServiceIds = _resolveInitialServiceIds(appointment);
    _selectedEmployeeId =
        _resolveInitialEmployeeId(appointment) ?? widget.initialEmployeeId;
    _selectedCustomerId = _resolveInitialCustomerId(appointment);
    _durationController = TextEditingController(
      text: _selectedServicesDuration.toString(),
    );
    _slotController = TextEditingController(
      text: appointment?.slotLabel ?? 'Ghế VIP 1',
    );
    _timeController = TextEditingController(
      text: appointment?.timeLabel ?? widget.initialTimeLabel ?? '10:00',
    );
    _noteController =
        TextEditingController(text: appointment?.note ?? '');
    _status = _isReceive
        ? 'Đã đặt'
        : _statusOptions.contains(appointment?.status)
            ? appointment!.status
            : 'Chờ xác nhận';
    final requestedDay =
        appointment?.dateLabel ?? widget.initialDayLabel ?? 'Hôm nay';
    _dayLabel = _isReceive
        ? 'Hôm nay'
        : _dayOptions.contains(requestedDay)
            ? requestedDay
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
    final selectedEmployee = _selectedEmployee;
    final selectedServices = _selectedServices;
    final title = isEditing
        ? 'Sửa lịch hẹn'
        : _isReceive
            ? 'Nhận khách'
            : 'Tạo lịch hẹn';

    return AlertDialog(
      key: const Key('appointment-editor-dialog'),
      title: Row(
        children: [
          PremiumIconBadge(
            icon: isEditing
                ? Icons.edit_calendar_outlined
                : _isReceive
                    ? Icons.person_add_alt_1_outlined
                    : Icons.add_task_rounded,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 620),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khách hàng',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                ),
                const SizedBox(height: 7),
                KeyedSubtree(
                  key: const Key('appointment-customer-field'),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'appointment-customer-${_selectedCustomerId ?? 'none'}',
                    ),
                    initialValue: _selectedCustomerId,
                    isExpanded: true,
                    hint: const Text('Chọn khách hàng'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: _customers
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
                        ? 'Chọn khách hàng'
                        : null,
                    onChanged: (value) =>
                        setState(() => _selectedCustomerId = value),
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('appointment-customer-search-action'),
                      onPressed: _isSubmitting ? null : _searchCustomer,
                      icon: const Icon(Icons.search_rounded, size: 17),
                      label: const Text('Tìm khách'),
                    ),
                    TextButton.icon(
                      key: const Key('appointment-customer-new-action'),
                      onPressed: _isSubmitting ? null : _createCustomer,
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                      label: const Text('Khách mới'),
                    ),
                  ],
                ),
                if (selectedCustomer != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'SĐT ${selectedCustomer.phone} • Hạng ${selectedCustomer.tier}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Dịch vụ',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                ),
                const SizedBox(height: 7),
                FormField<List<String>>(
                  initialValue: _selectedServiceIds,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Chọn ít nhất một dịch vụ có sẵn'
                      : null,
                  builder: (field) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.fieldShell,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: field.hasError
                            ? AppColors.danger
                            : AppColors.controlBorder,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final service
                            in widget.services.where(
                              (service) => service.isActive,
                            ))
                          Material(
                            color: Colors.transparent,
                            child: CheckboxListTile(
                              value: _selectedServiceIds.contains(service.id),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: Text(
                                service.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${service.category} • ${service.durationLabel} • ${service.priceLabel}',
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    if (!_selectedServiceIds
                                        .contains(service.id)) {
                                      _selectedServiceIds = [
                                        ..._selectedServiceIds,
                                        service.id,
                                      ];
                                    }
                                  } else {
                                    _selectedServiceIds = _selectedServiceIds
                                        .where((id) => id != service.id)
                                        .toList(growable: false);
                                  }
                                  _durationController.text =
                                      _selectedServicesDuration.toString();
                                  field.didChange(_selectedServiceIds);
                                });
                              },
                            ),
                          ),
                        if (field.hasError)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                10,
                                4,
                                10,
                                6,
                              ),
                              child: Text(
                                field.errorText!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (selectedServices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${selectedServices.length} dịch vụ • $_selectedServicesPriceLabel • $_selectedServicesDuration phút',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.copper,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmployeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nhân viên phụ trách',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: widget.employees
                      .where(_isSchedulableEmployee)
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
                  onChanged: (value) =>
                      setState(() => _selectedEmployeeId = value),
                ),
                if (selectedEmployee != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ca ${selectedEmployee['shift']} • ${selectedEmployee['role']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final Widget dateField = _isReceive
                        ? InputDecorator(
                            key: const Key('appointment-receive-day'),
                            decoration:
                                const InputDecoration(labelText: 'Ngày'),
                            child: const Text('Hôm nay'),
                          )
                        : DropdownButtonFormField<String>(
                            initialValue: _dayLabel,
                            decoration: const InputDecoration(
                              labelText: 'Ngày hẹn',
                            ),
                            items: _dayOptions
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _dayLabel = value);
                              }
                            },
                          );
                    final timeField = TextFormField(
                      key: const Key('appointment-time-field'),
                      controller: _timeController,
                      decoration: InputDecoration(
                        labelText: _isReceive ? 'Giờ vào' : 'Giờ hẹn',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Nhập giờ';
                        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) {
                          return 'Dùng HH:mm';
                        }
                        return null;
                      },
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          dateField,
                          const SizedBox(height: 10),
                          timeField,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: dateField),
                        const SizedBox(width: 10),
                        Expanded(child: timeField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final duration = TextFormField(
                      controller: _durationController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Thời lượng (phút)',
                        helperText: 'Tự tính theo tổng thời lượng dịch vụ đã chọn.',
                      ),
                    );
                    final slot = TextFormField(
                      controller: _slotController,
                      decoration: const InputDecoration(
                        labelText: 'Khu vực / ghế',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Nhập khu vực phục vụ'
                              : null,
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          duration,
                          const SizedBox(height: 10),
                          slot,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: duration),
                        const SizedBox(width: 10),
                        Expanded(child: slot),
                      ],
                    );
                  },
                ),
                if (!_isReceive) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: const Key('appointment-status-field'),
                    initialValue: _status,
                    decoration:
                        const InputDecoration(labelText: 'Trạng thái'),
                    items: _statusOptions
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _status = value);
                    },
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            isEditing
                ? 'Lưu lịch'
                : _isReceive
                    ? 'Nhận khách'
                    : 'Tạo lịch',
          ),
        ),
      ],
    );
  }

  Future<void> _searchCustomer() async {
    final controller = TextEditingController();
    var query = '';
    final selected = await showDialog<CustomerProfile>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final filtered = _customers.where((customer) {
            if (normalized.isEmpty) return true;
            return customer.fullName.toLowerCase().contains(normalized) ||
                customer.phone.toLowerCase().contains(normalized);
          }).toList(growable: false);

          return AlertDialog(
            title: const Text('Tìm khách'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    key: const Key('appointment-customer-search-field'),
                    controller: controller,
                    autofocus: true,
                    onChanged: (value) {
                      setDialogState(() => query = value);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Nhập tên hoặc số điện thoại',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Không tìm thấy khách'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const PremiumDivider(indent: 42),
                            itemBuilder: (context, index) {
                              final customer = filtered[index];
                              return ListTile(
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(customer),
                                leading: const Icon(Icons.person_outline),
                                title: Text(customer.fullName),
                                subtitle: Text(customer.phone),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (selected == null || !mounted) return;
    setState(() => _selectedCustomerId = selected.id);
  }

  Future<void> _createCustomer() async {
    final input = await showDialog<CustomerUpsertInput>(
      context: context,
      builder: (_) => const _AppointmentQuickCustomerDialog(),
    );
    if (input == null || !mounted) return;

    try {
      final saved = await widget.onCreateCustomer(input);
      if (!mounted) return;
      setState(() {
        _customers = [
          ..._customers.where((customer) => customer.id != saved.id),
          saved,
        ];
        _selectedCustomerId = saved.id;
      });
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Không thể thêm khách'),
          content: Text(_appointmentSaveErrorMessage(error)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final customer = _selectedCustomer;
    final services = _selectedServices;
    final employee = _selectedEmployee;
    if (customer == null || services.isEmpty || employee == null) return;
    setState(() => _isSubmitting = true);

    Navigator.of(context).pop(
      AppointmentUpsertInput(
        customerId: customer.id,
        serviceIds:
            services.map((service) => service.id).toList(growable: false),
        employeeId: employee['id']!.toString(),
        customerName: customer.fullName,
        customerPhone: customer.phone,
        serviceName:
            services.map((service) => service.name).join(' + '),
        staffName: employee['name']!.toString(),
        status: _status,
        durationMinutes: _selectedServicesDuration,
        slotLabel: _slotController.text.trim(),
        note: _noteController.text.trim(),
        dayLabel: _dayLabel,
        timeLabel: _timeController.text.trim(),
      ),
    );
  }

  String? _resolveInitialCustomerId(AppointmentEntry? appointment) {
    if (appointment == null) return null;
    for (final customer in widget.customers) {
      if (customer.id == appointment.customerId) return customer.id;
    }
    return null;
  }

  List<String> _resolveInitialServiceIds(AppointmentEntry? appointment) {
    if (appointment == null) return const [];
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
    if (appointment == null) return null;
    for (final employee in widget.employees) {
      if (!_isSchedulableEmployee(employee)) continue;
      if (employee['id']?.toString() == appointment.employeeId ||
          employee['name']?.toString() == appointment.staffName) {
        return employee['id']?.toString();
      }
    }
    return null;
  }

  bool _isSchedulableEmployee(Map<String, Object?> employee) {
    final status = employee['status']?.toString() ?? '';
    return status == 'Đang làm việc' || status == 'Sắp có lịch';
  }

  CustomerProfile? get _selectedCustomer {
    final id = _selectedCustomerId;
    if (id == null) return null;
    for (final customer in _customers) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  List<ServiceCatalogItem> get _selectedServices {
    final ids = _selectedServiceIds.toSet();
    return widget.services
        .where((service) => ids.contains(service.id))
        .toList(growable: false);
  }

  int get _selectedServicesDuration {
    final services = _selectedServices;
    if (services.isEmpty) return 90;
    return services.fold<int>(
      0,
      (sum, service) => sum + service.durationMinutes,
    );
  }

  String get _selectedServicesPriceLabel {
    final price = _selectedServices.fold<int>(
      0,
      (sum, service) => sum + service.price,
    );
    return _currency(price);
  }

  Map<String, Object?>? get _selectedEmployee {
    final id = _selectedEmployeeId;
    if (id == null) return null;
    for (final employee in widget.employees) {
      if (employee['id']?.toString() == id) return employee;
    }
    return null;
  }
}

class _AppointmentQuickCustomerDialog extends StatefulWidget {
  const _AppointmentQuickCustomerDialog();

  @override
  State<_AppointmentQuickCustomerDialog> createState() =>
      _AppointmentQuickCustomerDialogState();
}

class _AppointmentQuickCustomerDialogState
    extends State<_AppointmentQuickCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('appointment-quick-customer-dialog'),
      title: const Text('Thêm khách mới'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('appointment-quick-customer-name'),
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập họ và tên khách hàng'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('appointment-quick-customer-phone'),
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Số điện thoại'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập số điện thoại'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          key: const Key('appointment-quick-customer-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              CustomerUpsertInput(
                fullName: _nameController.text.trim(),
                phone: _phoneController.text.trim(),
                email: '',
                tier: 'Member',
                favoriteService: '',
                hairProfile: '',
                note: '',
              ),
            );
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('Lưu khách'),
        ),
      ],
    );
  }
}
