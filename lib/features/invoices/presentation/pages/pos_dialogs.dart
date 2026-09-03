part of 'invoices_pos_page.dart';

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
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Giảm giá (đ)',
              helperText: 'Tối đa ${_currency(widget.maxDiscount)}',
              prefixIcon: const Icon(Icons.sell_outlined),
            ),
            validator: (value) {
              final amount = int.tryParse(value?.trim() ?? '');
              return amount == null || amount < 0
                  ? 'Nhập số tiền hợp lệ'
                  : null;
            },
            onFieldSubmitted: (_) => _submit(),
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

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = int.parse(_controller.text.trim());
    Navigator.of(context).pop(
      amount > widget.maxDiscount ? widget.maxDiscount : amount,
    );
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
