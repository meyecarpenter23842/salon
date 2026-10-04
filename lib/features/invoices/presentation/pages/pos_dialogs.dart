part of 'invoices_pos_page.dart';


const _newInvoiceEmployeeChoice = '__new_invoice_employee__';

List<Map<String, Object?>> _availableInvoiceEmployees(
  List<Map<String, Object?>> employees,
) {
  return employees.where((employee) {
    final status = employee['status']?.toString() ?? '';
    return status == 'Đang làm việc' || status == 'Sắp có lịch';
  }).toList(growable: false);
}

Future<String?> _chooseInvoiceEmployee(
  BuildContext context,
  WidgetRef ref, {
  String? selectedEmployeeId,
}) async {
  List<Map<String, Object?>> employees;
  try {
    employees = await ref.read(employeesViewProvider.future);
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không tải được nhân viên: $error')),
    );
    return null;
  }
  if (!context.mounted) return null;

  final choice = await showAppDialog<String>(
    context: context,
    builder: (_) => _InvoiceEmployeePickerDialog(
      employees: _availableInvoiceEmployees(employees),
      selectedEmployeeId: selectedEmployeeId,
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice != _newInvoiceEmployeeChoice) return choice;

  return _quickCreateInvoiceEmployee(context, ref);
}

Future<String?> _quickCreateInvoiceEmployee(
  BuildContext context,
  WidgetRef ref,
) async {
  final input = await showAppDialog<EmployeeUpsertInput>(
    context: context,
    builder: (_) => const _QuickInvoiceEmployeeDialog(),
  );
  if (input == null || !context.mounted) return null;

  try {
    final saved = await ref.read(employeesRepositoryProvider).saveEmployee(input);
    if (!context.mounted) return null;
    ref.invalidate(employeesViewProvider);
    final id = saved['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw StateError('Không đọc được mã nhân viên vừa tạo.');
    }
    ref.read(_invoiceServiceEmployeeIdProvider.notifier).state = id;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã thêm nhân viên ${saved['name'] ?? input.fullName} và chọn cho bill.',
        ),
      ),
    );
    return id;
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Không tạo được nhân viên: $error')),
    );
    return null;
  }
}

class _InvoiceEmployeePickerDialog extends StatelessWidget {
  const _InvoiceEmployeePickerDialog({
    required this.employees,
    required this.selectedEmployeeId,
  });

  final List<Map<String, Object?>> employees;
  final String? selectedEmployeeId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('billing-employee-picker'),
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.badge_outlined, size: 36),
          SizedBox(width: 9),
          Text('Chọn nhân viên thực hiện'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        height: employees.isEmpty ? 180 : 380,
        child: employees.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.group_off_outlined,
                title: 'Chưa có nhân viên đang làm',
                message:
                    'Có thể để Chưa gán nhân viên hoặc thêm nhân viên nhanh ngay tại bill.',
              )
            : ListView.separated(
                itemCount: employees.length,
                separatorBuilder: (_, _) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final employee = employees[index];
                  final id = employee['id']?.toString() ?? '';
                  final selected = id == selectedEmployeeId;
                  return PremiumInteractiveSurface(
                    selected: selected,
                    onTap: id.isEmpty ? null : () => Navigator.of(context).pop(id),
                    child: Row(
                      children: [
                        PremiumIconBadge(
                          icon: Icons.person_outline_rounded,
                          size: 34,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                employee['name']?.toString() ?? 'Nhân viên',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${employee['role'] ?? ''} · ${employee['status'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: AppColors.copper,
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('billing-employee-picker-unassigned'),
          onPressed: () => Navigator.of(context).pop(''),
          icon: const Icon(Icons.person_off_outlined),
          label: const Text('Không gán nhân viên'),
        ),
        TextButton.icon(
          key: const Key('billing-employee-picker-add'),
          onPressed: () =>
              Navigator.of(context).pop(_newInvoiceEmployeeChoice),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Thêm nhân viên nhanh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class _QuickInvoiceEmployeeDialog extends StatefulWidget {
  const _QuickInvoiceEmployeeDialog();

  @override
  State<_QuickInvoiceEmployeeDialog> createState() =>
      _QuickInvoiceEmployeeDialogState();
}

class _QuickInvoiceEmployeeDialogState
    extends State<_QuickInvoiceEmployeeDialog> {
  static const _roles = [
    'Stylist chính',
    'Barber',
    'Chăm sóc tóc',
    'Lễ tân',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _role = _roles.first;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.person_add_alt_1_outlined, size: 36),
          SizedBox(width: 9),
          Text('Thêm nhân viên nhanh'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 460),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('billing-quick-employee-name'),
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Họ tên'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập họ tên nhân viên'
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Vai trò'),
                items: _roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _role = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại (không bắt buộc)',
                ),
                keyboardType: TextInputType.phone,
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
        FilledButton(
          key: const Key('billing-quick-employee-save'),
          onPressed: _submit,
          child: const Text('Lưu & chọn'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      EmployeeUpsertInput(
        fullName: _nameController.text.trim(),
        role: _role,
        status: 'Đang làm việc',
        phone: _phoneController.text.trim(),
        shift: '',
        specialty: '',
        commissionLabel: '0%',
        todaySchedule: '',
        servicesDone: 0,
        monthlyRevenue: '',
        rating: '',
        note: 'Tạo nhanh từ Bill',
      ),
    );
  }
}

Future<void> _showCustomerPickerDialog(
  BuildContext context,
  WidgetRef ref,
  List<CustomerProfile> customers,
  String selectedCustomerId,
) async {
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => _CustomerPickerDialog(
      customers: customers,
      selectedCustomerId: selectedCustomerId,
      onSelected: (customer) async {
        await _selectInvoiceCustomer(context, ref, customer);
        if (!dialogContext.mounted) return;
        Navigator.of(dialogContext).pop();
      },
    ),
  );
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    required this.customers,
    required this.selectedCustomerId,
    required this.onSelected,
  });

  final List<CustomerProfile> customers;
  final String selectedCustomerId;
  final Future<void> Function(CustomerProfile customer) onSelected;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _queryController = TextEditingController();
  String _query = '';
  bool _selecting = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = widget.customers.where((customer) {
      if (query.isEmpty) return true;
      return customer.fullName.toLowerCase().contains(query) ||
          customer.phone.toLowerCase().contains(query);
    }).toList(growable: false);

    return AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.person_search_outlined, size: 36),
          SizedBox(width: 9),
          Text('Chọn khách cho bill'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 520),
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Tìm tên hoặc số điện thoại',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa tìm kiếm',
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: visible.isEmpty
                  ? const PremiumEmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Không tìm thấy khách',
                      message: 'Thử lại bằng tên hoặc số điện thoại khác.',
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, _) =>
                          const PremiumDivider(indent: 48),
                      itemBuilder: (context, index) {
                        final customer = visible[index];
                        final selected =
                            customer.id == widget.selectedCustomerId;
                        return PremiumInteractiveSurface(
                          selected: selected,
                          onTap: _selecting
                              ? null
                              : () async {
                                  setState(() => _selecting = true);
                                  try {
                                    await widget.onSelected(customer);
                                  } finally {
                                    if (mounted) {
                                      setState(() => _selecting = false);
                                    }
                                  }
                                },
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.iconSurface,
                                foregroundColor: AppColors.copper,
                                child: Text(
                                  customer.initials,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      customer.fullName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${customer.phone} · ${customer.tier}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: AppColors.copper,
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
      actions: [
        TextButton(
          onPressed: _selecting ? null : () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

enum _DiscountInputMode { amount, percent }

class _InvoiceDiscountDialog extends StatefulWidget {
  const _InvoiceDiscountDialog({
    required this.currentDiscount,
    required this.maxDiscount,
  });

  final int currentDiscount;
  final int maxDiscount;

  @override
  State<_InvoiceDiscountDialog> createState() => _InvoiceDiscountDialogState();
}

class _InvoiceDiscountDialogState extends State<_InvoiceDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  _DiscountInputMode _mode = _DiscountInputMode.amount;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentDiscount.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewDiscount = _discountFromInput();

    return AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.local_offer_outlined, size: 36),
          SizedBox(width: 9),
          Text('Cập nhật giảm giá'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_DiscountInputMode>(
                segments: const [
                  ButtonSegment(
                    value: _DiscountInputMode.amount,
                    icon: Icon(Icons.payments_outlined, size: 16),
                    label: Text('Số tiền'),
                  ),
                  ButtonSegment(
                    value: _DiscountInputMode.percent,
                    icon: Icon(Icons.percent_rounded, size: 16),
                    label: Text('Phần trăm'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    _changeMode(selection.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: _mode == _DiscountInputMode.percent
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.number,
                decoration: InputDecoration(
                  labelText: _mode == _DiscountInputMode.percent
                      ? 'Giảm giá (%)'
                      : 'Giảm giá (đ)',
                  helperText: _mode == _DiscountInputMode.percent
                      ? 'Quy đổi ${_currency(previewDiscount)} · tối đa 100%'
                      : 'Tối đa ${_currency(widget.maxDiscount)}',
                  prefixIcon: Icon(
                    _mode == _DiscountInputMode.percent
                        ? Icons.percent_rounded
                        : Icons.sell_outlined,
                  ),
                ),
                validator: _validateInput,
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _submit(),
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
        FilledButton(onPressed: _submit, child: const Text('Lưu giảm giá')),
      ],
    );
  }

  String? _validateInput(String? value) {
    if (_mode == _DiscountInputMode.percent) {
      final percent = _parsePercent(value ?? '');
      if (percent == null || percent < 0 || percent > 100) {
        return 'Nhập phần trăm từ 0 đến 100';
      }
      return null;
    }

    final amount = _parseAmount(value ?? '');
    if (amount == null || amount < 0) {
      return 'Nhập số tiền hợp lệ';
    }
    return null;
  }

  void _changeMode(_DiscountInputMode nextMode) {
    if (nextMode == _mode) return;
    final currentDiscount = _discountFromInput();

    setState(() {
      _mode = nextMode;
      if (_mode == _DiscountInputMode.percent) {
        final percent = widget.maxDiscount <= 0
            ? 0.0
            : currentDiscount * 100 / widget.maxDiscount;
        _controller.text = _formatPercent(percent);
      } else {
        _controller.text = currentDiscount.toString();
      }
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  int _discountFromInput() {
    if (_mode == _DiscountInputMode.percent) {
      final percent = _parsePercent(_controller.text) ?? 0;
      final normalized = percent < 0
          ? 0.0
          : percent > 100
              ? 100.0
              : percent;
      return (widget.maxDiscount * normalized / 100).round();
    }

    final amount = _parseAmount(_controller.text) ?? 0;
    if (amount < 0) return 0;
    if (amount > widget.maxDiscount) return widget.maxDiscount;
    return amount;
  }

  int? _parseAmount(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.startsWith('-')) return null;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  double? _parsePercent(String raw) {
    final value = raw.trim().replaceAll(',', '.');
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  String _formatPercent(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.01) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_discountFromInput());
  }
}

class _RetailProductEditorDialog extends StatefulWidget {
  const _RetailProductEditorDialog({required this.onSave});

  final Future<RetailProductItem> Function(RetailProductUpsertInput input) onSave;

  @override
  State<_RetailProductEditorDialog> createState() =>
      _RetailProductEditorDialogState();
}

class _RetailProductEditorDialogState extends State<_RetailProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _volumeController = TextEditingController();
  final _priceController = TextEditingController();
  String _type = RetailProductUpsertInput.productTypes.first;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _volumeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.add_box_outlined, size: 36),
          SizedBox(width: 9),
          Text('Thêm sản phẩm bán lẻ'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên sản phẩm'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(labelText: 'Thương hiệu'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _volumeController,
                  decoration: const InputDecoration(
                    labelText: 'Dung tích / quy cách',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Nhóm sản phẩm'),
                  items: RetailProductUpsertInput.productTypes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Giá bán (đ)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed <= 0
                        ? 'Nhập giá hợp lệ'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Đang lưu…' : 'Lưu & thêm vào bill'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final input = RetailProductUpsertInput(
        name: _nameController.text.trim(),
        brand: _brandController.text.trim(),
        volumeLabel: _volumeController.text.trim(),
        productType: _type,
        salePrice: int.parse(_priceController.text.trim()),
        commissionPercent: 0,
        isHiddenFromStaff: false,
        isActive: true,
      );
      final created = await widget.onSave(input);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      rethrow;
    }
  }
}
