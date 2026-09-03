part of 'appointments_page.dart';

class _AppointmentEditorDialog extends StatefulWidget {
  const _AppointmentEditorDialog({
    required this.customers,
    required this.services,
    required this.employees,
    this.appointment,
    this.initialEmployeeId,
    this.initialTimeLabel,
    this.initialDayLabel,
  });

  final AppointmentEntry? appointment;
  final List<CustomerProfile> customers;
  final List<ServiceCatalogItem> services;
  final List<Map<String, Object?>> employees;
  final String? initialEmployeeId;
  final String? initialTimeLabel;
  final String? initialDayLabel;

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
    _selectedEmployeeId =
        _resolveInitialEmployeeId(appointment) ?? widget.initialEmployeeId;
    _selectedCustomerId = _resolveInitialCustomerId(appointment);
    _durationController = TextEditingController(
      text: appointment?.durationMinutes.toString() ??
          _selectedServicesDuration.toString(),
    );
    _slotController = TextEditingController(
      text: appointment?.slotLabel ?? 'Ghế VIP 1',
    );
    _timeController = TextEditingController(
      text: appointment?.timeLabel ?? widget.initialTimeLabel ?? '10:00',
    );
    _noteController =
        TextEditingController(text: appointment?.note ?? '');
    _status = _statusOptions.contains(appointment?.status)
        ? appointment!.status
        : 'Chờ xác nhận';
    final requestedDay =
        appointment?.dateLabel ?? widget.initialDayLabel ?? 'Hôm nay';
    _dayLabel =
        _dayOptions.contains(requestedDay) ? requestedDay : 'Hôm nay';
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

    return AlertDialog(
      title: Row(
        children: [
          PremiumIconBadge(
            icon: isEditing
                ? Icons.edit_calendar_outlined
                : Icons.add_task_rounded,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(isEditing ? 'Sửa lịch hẹn' : 'Tạo lịch hẹn'),
          ),
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
                DropdownButtonFormField<String>(
                  initialValue: _selectedCustomerId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline),
                  ),
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
                  onChanged: (value) =>
                      setState(() => _selectedCustomerId = value),
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
                          CheckboxListTile(
                            value: _selectedServiceIds.contains(service.id),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            title: Text(
                              service.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
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
                    final dateField = DropdownButtonFormField<String>(
                      initialValue: _dayLabel,
                      decoration:
                          const InputDecoration(labelText: 'Ngày hẹn'),
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
                      controller: _timeController,
                      decoration:
                          const InputDecoration(labelText: 'Giờ hẹn'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Nhập giờ hẹn';
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
                      decoration: const InputDecoration(
                        labelText: 'Thời lượng (phút)',
                      ),
                      validator: (value) {
                        final minutes = int.tryParse(value?.trim() ?? '');
                        return minutes == null || minutes <= 0
                            ? 'Nhập số phút hợp lệ'
                            : null;
                      },
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
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
          label: Text(isEditing ? 'Lưu lịch' : 'Tạo lịch'),
        ),
      ],
    );
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
      if (customer.id == appointment.customerId) return customer.id;
    }
    return widget.customers.isEmpty ? null : widget.customers.first.id;
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
      if (employee['id']?.toString() == appointment.employeeId ||
          employee['name']?.toString() == appointment.staffName) {
        return employee['id']?.toString();
      }
    }
    return null;
  }

  CustomerProfile? get _selectedCustomer {
    final id = _selectedCustomerId;
    if (id == null) return null;
    for (final customer in widget.customers) {
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
