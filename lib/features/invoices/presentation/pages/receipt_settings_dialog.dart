part of 'invoices_pos_page.dart';

class _ReceiptSettingsDialog extends StatefulWidget {
  const _ReceiptSettingsDialog({required this.fallbackSalonName});

  final String fallbackSalonName;

  @override
  State<_ReceiptSettingsDialog> createState() => _ReceiptSettingsDialogState();
}

class _ReceiptSettingsDialogState extends State<_ReceiptSettingsDialog> {
  late ReceiptTemplateConfig _config;
  late final TextEditingController _salonNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _taglineController;
  late final TextEditingController _footerMessageController;
  late final TextEditingController _footerNoteController;

  List<Printer> _printers = const [];
  bool _loading = true;
  bool _saving = false;
  bool _printing = false;
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    _config = ReceiptTemplateConfig.defaults(salonName: widget.fallbackSalonName);
    _salonNameController = TextEditingController();
    _addressController = TextEditingController();
    _phoneController = TextEditingController();
    _taglineController = TextEditingController();
    _footerMessageController = TextEditingController();
    _footerNoteController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _salonNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _taglineController.dispose();
    _footerMessageController.dispose();
    _footerNoteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ReceiptTemplateStore.instance.load(
      fallbackSalonName: widget.fallbackSalonName,
    );
    List<Printer> printers = const [];
    try {
      printers = await Printing.listPrinters();
    } catch (_) {
      printers = const [];
    }
    if (!mounted) return;
    setState(() {
      _config = config;
      _printers = printers.where((printer) => printer.isAvailable).toList();
      _syncControllers();
      _loading = false;
    });
  }

  void _syncControllers() {
    _salonNameController.text = _config.salonName;
    _addressController.text = _config.address;
    _phoneController.text = _config.phone;
    _taglineController.text = _config.tagline;
    _footerMessageController.text = _config.footerMessage;
    _footerNoteController.text = _config.footerNote;
  }

  void _setConfig(ReceiptTemplateConfig config) {
    setState(() {
      _config = config;
      _previewRevision++;
    });
  }

  void _syncTextConfig() {
    _setConfig(
      _config.copyWith(
        salonName: _salonNameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        tagline: _taglineController.text.trim(),
        footerMessage: _footerMessageController.text.trim(),
        footerNote: _footerNoteController.text.trim(),
      ),
    );
  }

  Future<void> _chooseLogo() async {
    const imageGroup = XTypeGroup(
      label: 'Ảnh logo',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [imageGroup]);
    if (file == null || !mounted) return;
    _setConfig(_config.copyWith(logoPath: file.path, showLogo: true));
  }

  Future<void> _reset() async {
    final reset = await ReceiptTemplateStore.instance.reset(
      fallbackSalonName: widget.fallbackSalonName,
    );
    if (!mounted) return;
    setState(() {
      _config = reset;
      _syncControllers();
      _previewRevision++;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _syncTextConfig();
    setState(() => _saving = true);
    try {
      await ReceiptTemplateStore.instance.save(_config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu thiết lập phiếu in.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printTest() async {
    if (_printing) return;
    _syncTextConfig();
    setState(() => _printing = true);
    try {
      final bytes = await _buildReceiptPdfBytes(
        _previewInvoice,
        _previewCustomer,
        _config,
      );
      final result = await _sendReceiptToPrinter(
        bytes: bytes,
        config: _config,
        jobName: 'Phiếu in thử',
        availablePrinters: _printers,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result ? 'Đã gửi phiếu in thử.' : 'Đã hủy in thử.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('In thử thất bại: $error')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('receipt-settings-dialog'),
      backgroundColor: AppColors.workspaceBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1220,
          maxHeight: media.height * 0.93,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
              child: Row(
                children: [
                  const PremiumIconBadge(icon: Icons.receipt_long_outlined, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thiết lập phiếu in',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Nội dung phiếu đi theo backup; máy in, khổ giấy, số bản và đường dẫn logo chỉ lưu trên máy này.',
                          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Đóng',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const PremiumDivider(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 900) {
                          return ListView(
                            padding: const EdgeInsets.all(14),
                            children: [
                              _buildEditor(),
                              const SizedBox(height: 14),
                              SizedBox(height: 620, child: _buildPreview()),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 470,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(14),
                                child: _buildEditor(),
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: _buildPreview(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const PremiumDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving || _printing ? null : _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Khôi phục mặc định'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    key: const Key('receipt-settings-print-test'),
                    onPressed: _saving || _printing ? null : _printTest,
                    icon: _printing
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: const Text('In thử'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('receipt-settings-save'),
                    onPressed: _saving || _printing ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Lưu thiết lập'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    final printerNames = _printers.map((printer) => printer.name).toSet().toList();
    final selectedPrinter = printerNames.contains(_config.printerName)
        ? _config.printerName
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReceiptSettingsSection(
          title: 'Máy in & khổ giấy',
          icon: Icons.print_outlined,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('receipt-paper-${_config.paperSize}'),
                initialValue: _config.paperSize,
                decoration: const InputDecoration(labelText: 'Khổ giấy'),
                items: ReceiptTemplateConfig.paperSizes
                    .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) _setConfig(_config.copyWith(paperSize: value));
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('receipt-printer-$selectedPrinter-${printerNames.length}'),
                initialValue: selectedPrinter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Máy in'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Hỏi máy in khi bấm In'),
                  ),
                  for (final name in printerNames)
                    DropdownMenuItem(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) =>
                    _setConfig(_config.copyWith(printerName: value ?? '')),
              ),
              if (_printers.isEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Windows chưa trả về danh sách máy in. App vẫn mở hộp thoại in khi cần.',
                    style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: ValueKey('receipt-copies-${_config.copies}'),
                initialValue: _config.copies,
                decoration: const InputDecoration(labelText: 'Số bản'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 bản')),
                  DropdownMenuItem(value: 2, child: Text('2 bản')),
                  DropdownMenuItem(value: 3, child: Text('3 bản')),
                ],
                onChanged: (value) {
                  if (value != null) _setConfig(_config.copyWith(copies: value));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReceiptSettingsSection(
          title: 'Đầu phiếu',
          icon: Icons.storefront_outlined,
          child: Column(
            children: [
              TextField(
                controller: _salonNameController,
                decoration: const InputDecoration(labelText: 'Tên salon'),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'SĐT salon'),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _taglineController,
                decoration: const InputDecoration(labelText: 'Dòng phụ'),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _config.showLogo,
                onChanged: (value) => _setConfig(_config.copyWith(showLogo: value)),
                title: const Text('Hiện logo'),
                subtitle: Text(
                  _config.logoPath.trim().isEmpty
                      ? 'Chưa chọn ảnh'
                      : path.basename(_config.logoPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _chooseLogo,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Chọn logo'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReceiptSettingsSection(
          title: 'Thông tin trên phiếu',
          icon: Icons.tune_rounded,
          child: Column(
            children: [
              _receiptSwitch('Mã hóa đơn', _config.showInvoiceId,
                  (value) => _config.copyWith(showInvoiceId: value)),
              _receiptSwitch('Ngày giờ', _config.showDateTime,
                  (value) => _config.copyWith(showDateTime: value)),
              _receiptSwitch('Tên khách', _config.showCustomerName,
                  (value) => _config.copyWith(showCustomerName: value)),
              _receiptSwitch('SĐT khách', _config.showCustomerPhone,
                  (value) => _config.copyWith(showCustomerPhone: value)),
              _receiptSwitch('Phương thức thanh toán', _config.showPaymentMethod,
                  (value) => _config.copyWith(showPaymentMethod: value)),
              const PremiumDivider(),
              _receiptSwitch('Số lượng', _config.showQuantity,
                  (value) => _config.copyWith(showQuantity: value)),
              _receiptSwitch('Đơn giá', _config.showUnitPrice,
                  (value) => _config.copyWith(showUnitPrice: value)),
              _receiptSwitch('Giảm giá', _config.showDiscount,
                  (value) => _config.copyWith(showDiscount: value)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReceiptSettingsSection(
          title: 'Kiểu hiển thị',
          icon: Icons.text_fields_rounded,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('receipt-font-${_config.fontSize}'),
                initialValue: _config.fontSize,
                decoration: const InputDecoration(labelText: 'Cỡ chữ'),
                items: const [
                  DropdownMenuItem(
                    value: ReceiptTemplateConfig.fontSmall,
                    child: Text('Nhỏ'),
                  ),
                  DropdownMenuItem(
                    value: ReceiptTemplateConfig.fontMedium,
                    child: Text('Vừa'),
                  ),
                  DropdownMenuItem(
                    value: ReceiptTemplateConfig.fontLarge,
                    child: Text('Lớn'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) _setConfig(_config.copyWith(fontSize: value));
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('receipt-layout-${_config.layoutStyle}'),
                initialValue: _config.layoutStyle,
                decoration: const InputDecoration(labelText: 'Bố cục'),
                items: const [
                  DropdownMenuItem(
                    value: ReceiptTemplateConfig.layoutCompact,
                    child: Text('Gọn'),
                  ),
                  DropdownMenuItem(
                    value: ReceiptTemplateConfig.layoutStandard,
                    child: Text('Tiêu chuẩn'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _setConfig(_config.copyWith(layoutStyle: value));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ReceiptSettingsSection(
          title: 'Cuối phiếu',
          icon: Icons.notes_rounded,
          child: Column(
            children: [
              TextField(
                controller: _footerMessageController,
                decoration: const InputDecoration(labelText: 'Lời cảm ơn'),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _footerNoteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú / chính sách',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => _syncTextConfig(),
              ),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _config.showQr,
                onChanged: (value) => _setConfig(_config.copyWith(showQr: value)),
                title: const Text('Hiện QR cuối phiếu'),
                subtitle: const Text('QR chứa mã hóa đơn để tra cứu nội bộ.'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _receiptSwitch(
    String title,
    bool value,
    ReceiptTemplateConfig Function(bool value) update,
  ) {
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: (next) => _setConfig(update(next)),
      title: Text(title),
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.panelRaised,
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 17),
                const SizedBox(width: 7),
                const Text(
                  'Xem trước phiếu thật',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                PremiumStatusPill(
                  label: '${_config.paperLabel} · ${_config.layoutStyleLabel}',
                  tone: AppColors.copper,
                ),
              ],
            ),
          ),
          Expanded(
            child: PdfPreview(
              key: ValueKey('receipt-preview-$_previewRevision'),
              build: (_) => _buildReceiptPdfBytes(
                _previewInvoice,
                _previewCustomer,
                _config,
              ),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
              pdfFileName: 'receipt-preview.pdf',
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptSettingsSection extends StatelessWidget {
  const _ReceiptSettingsSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.copper),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 11),
          child,
        ],
      ),
    );
  }
}

final _previewCustomer = CustomerProfile(
  id: 'preview-customer',
  fullName: 'Chị Lan',
  phone: '0909 123 456',
  tier: 'Member',
  favoriteService: 'Phục hồi tóc',
  hairProfile: '',
  note: '',
  loyaltyPoints: 0,
  visitCount: 1,
  totalSpent: 1468000,
  createdAt: DateTime(2026, 9, 5, 14),
  updatedAt: DateTime(2026, 9, 5, 14, 25),
);

final _previewInvoice = InvoiceDraft(
  id: 'HD-00125',
  customerId: _previewCustomer.id,
  discountAmount: 100000,
  paymentMethod: 'Tiền mặt',
  paidAt: DateTime(2026, 9, 5, 14, 25),
  createdAt: DateTime(2026, 9, 5, 14),
  updatedAt: DateTime(2026, 9, 5, 14, 25),
  lines: [
    InvoiceDraftLine(
      id: 'preview-1',
      invoiceId: 'HD-00125',
      itemType: 'service',
      serviceId: 'service-1',
      title: 'Gội đầu thư giãn',
      quantity: 1,
      unitPrice: 150000,
      discountAmount: 0,
      totalPrice: 150000,
    ),
    InvoiceDraftLine(
      id: 'preview-2',
      invoiceId: 'HD-00125',
      itemType: 'service',
      serviceId: 'service-2',
      title: 'Phục hồi tóc',
      quantity: 1,
      unitPrice: 500000,
      discountAmount: 0,
      totalPrice: 500000,
    ),
    InvoiceDraftLine(
      id: 'preview-3',
      invoiceId: 'HD-00125',
      itemType: 'product',
      productId: 'product-1',
      title: 'Collagen',
      quantity: 2,
      unitPrice: 459000,
      discountAmount: 0,
      totalPrice: 918000,
    ),
  ],
);
