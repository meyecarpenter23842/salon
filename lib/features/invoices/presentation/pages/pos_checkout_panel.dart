part of 'invoices_pos_page.dart';

final _invoiceCheckoutBusyProvider = StateProvider<bool>((ref) => false);

class _CheckoutPanel extends ConsumerWidget {
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
    final busy = ref.watch(_invoiceCheckoutBusyProvider);
    final customerLocked = draft.isPaid || draft.appointmentId != null || busy;

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
      child: SingleChildScrollView(
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
            SizedBox(height: dense ? 6 : 11),
            _CheckoutAmountSummary(draft: draft),
            SizedBox(height: dense ? 6 : 11),
            Text(
              'Phương thức thanh toán',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: dense ? 4 : 7),
            _PaymentMethodSelector(
              selected: draft.paymentMethod,
              locked: draft.isPaid || busy,
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
            SizedBox(height: dense ? 4 : 12),
            SizedBox(
              width: double.infinity,
              height: dense ? 38 : 44,
              child: FilledButton.icon(
                key: const Key('billing-checkout-action'),
                onPressed: busy || draft.isPaid || draft.lines.isEmpty
                    ? null
                    : () => _checkoutAndShowReceipt(
                        context,
                        ref,
                        draft,
                        selectedCustomer,
                        customers,
                      ),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        draft.isPaid
                            ? Icons.check_circle_outline_rounded
                            : Icons.payments_outlined,
                      ),
                label: Text(
                  busy
                      ? 'Đang thanh toán…'
                      : draft.isPaid
                      ? 'Đã thanh toán'
                      : 'Thanh toán ${_currency(draft.totalAmount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (selectedCustomer == null && draft.lines.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Chọn khách hàng trước khi thanh toán.',
                style: TextStyle(fontSize: 10.5, color: AppColors.warning),
              ),
            ],
            const SizedBox(height: 4),
            _CheckoutQuickActions(
              draft: draft,
              selectedCustomer: selectedCustomer,
              dense: dense,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _checkoutAndShowReceipt(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
  CustomerProfile? selectedCustomer,
  List<CustomerProfile> customers,
) async {
  if (draft.customerId.trim().isEmpty || selectedCustomer == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chọn khách hàng trước khi thanh toán.')),
    );
    return;
  }
  if (draft.lines.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hóa đơn chưa có dịch vụ hoặc sản phẩm.')),
    );
    return;
  }

  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('checkout-confirm-dialog'),
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.payments_outlined, size: 38),
          SizedBox(width: 10),
          Text('Xác nhận thanh toán'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedCustomer.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _ReceiptInfoLine(
              label: 'Tổng tiền',
              value: _currency(draft.totalAmount),
            ),
            _ReceiptInfoLine(label: 'Thanh toán', value: draft.paymentMethod),
            _ReceiptInfoLine(
              label: 'Số hạng mục',
              value: '${draft.lines.length}',
            ),
            const SizedBox(height: 8),
            Text(
              'Sau khi xác nhận, hóa đơn sẽ được chốt và không sửa trực tiếp trên bill hiện tại.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Không'),
        ),
        FilledButton(
          key: const Key('checkout-confirm-yes'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Có, thanh toán'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  ref.read(_invoiceCheckoutBusyProvider.notifier).state = true;
  InvoiceDraft? paidInvoice;
  try {
    await ref.read(invoicesRepositoryProvider).checkoutInvoice();

    final recent = draft.appointmentId == null
        ? await ref
              .read(invoicesRepositoryProvider)
              .fetchRecentInvoices(limit: 5, customerId: draft.customerId)
        : await ref
              .read(invoicesRepositoryProvider)
              .fetchRecentInvoices(
                limit: 5,
                appointmentId: draft.appointmentId,
              );

    if (recent.isNotEmpty) {
      paidInvoice = recent.firstWhere(
        (invoice) =>
            invoice.totalAmount == draft.totalAmount &&
            invoice.customerId == draft.customerId,
        orElse: () => recent.first,
      );
    }

    if (!context.mounted) return;
    ref.invalidate(invoiceDraftProvider);
    ref.invalidate(invoiceHistoryProvider);
    ref.invalidate(customerInvoiceHistoryProvider(draft.customerId));
    if (draft.appointmentId != null) {
      ref.invalidate(appointmentInvoiceHistoryProvider(draft.appointmentId!));
    }
    ref.read(customersRefreshProvider.notifier).state++;
    ref.invalidate(customersRepositoryProvider);
    ref.invalidate(customersViewProvider);
    ref.invalidate(appointmentsRepositoryProvider);
    ref.invalidate(appointmentsViewProvider);
    ref.invalidate(overviewSummaryProvider);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Thanh toán thất bại: ${_friendlyCheckoutError(error)}',
        ),
      ),
    );
    return;
  } finally {
    ref.read(_invoiceCheckoutBusyProvider.notifier).state = false;
  }

  if (!context.mounted) return;
  if (paidInvoice == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Đã thanh toán nhưng chưa tải được phiếu. Mở Lịch sử hóa đơn để xem lại.',
        ),
      ),
    );
    return;
  }

  final receiptCustomer =
      _customerForInvoice(paidInvoice, customers) ?? selectedCustomer;
  await _showCheckoutSuccessDialog(context, paidInvoice, receiptCustomer);
}

String _friendlyCheckoutError(Object error) {
  final text = error.toString();
  if (text.startsWith('Bad state: ')) {
    return text.substring('Bad state: '.length);
  }
  return text;
}

class _CustomerSummaryCard extends StatelessWidget {
  const _CustomerSummaryCard({
    required this.customer,
    required this.locked,
    this.onChange,
  });

  final CustomerProfile? customer;
  final bool locked;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final customer = this.customer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.iconSurface,
            foregroundColor: AppColors.copper,
            child: customer == null
                ? const Icon(Icons.person_outline_rounded, size: 17)
                : Text(
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
                  customer?.fullName ?? 'Chưa chọn khách',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  customer == null
                      ? 'Chọn khách trước khi chốt bill'
                      : '${customer.phone} · ${customer.tier}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: locked ? 'Khách đang bị khóa' : 'Tìm và đổi khách',
            child: IconButton(
              onPressed: onChange,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.manage_search_rounded,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutAmountSummary extends ConsumerWidget {
  const _CheckoutAmountSummary({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    onPressed: () => _openDiscountEditor(context, ref, draft),
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
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

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({
    required this.selected,
    required this.locked,
    required this.onSelected,
  });

  final String selected;
  final bool locked;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        final compactLabels = constraints.maxWidth < 280;
        return Row(
          children: [
            SizedBox(
              width: width,
              child: AppChoiceButton(
                label: 'Tiền mặt',
                selected: selected == 'Tiền mặt',
                onTap: locked ? null : () => onSelected('Tiền mặt'),
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: width,
              child: Tooltip(
                message: 'Chuyển khoản',
                child: AppChoiceButton(
                  label: compactLabels ? 'CK' : 'Chuyển khoản',
                  selected: selected == 'Chuyển khoản',
                  onTap: locked ? null : () => onSelected('Chuyển khoản'),
                ),
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: width,
              child: AppChoiceButton(
                label: 'Thẻ',
                selected: selected == 'Thẻ',
                onTap: locked ? null : () => onSelected('Thẻ'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CheckoutQuickActions extends ConsumerWidget {
  const _CheckoutQuickActions({
    required this.draft,
    required this.selectedCustomer,
    required this.dense,
  });

  final InvoiceDraft draft;
  final CustomerProfile? selectedCustomer;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                ? () => _showConfiguredPaymentQrDialog(
                    context,
                    ref,
                    draft,
                    selectedCustomer,
                  )
                : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 30 : 40,
              height: dense ? 30 : 40,
            ),
            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
          ),
        ),
        Tooltip(
          message: 'Xuất PDF hóa đơn',
          child: IconButton(
            onPressed: enabled
                ? () => _exportInvoicePdf(context, draft, selectedCustomer)
                : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 30 : 40,
              height: dense ? 30 : 40,
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          ),
        ),
      ],
    );
  }
}

Future<void> _showConfiguredPaymentQrDialog(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
  CustomerProfile? customer,
) async {
  try {
    final config = await ref.read(paymentConfigProvider.future);
    if (!context.mounted) return;

    final customerPhone = customer?.phone ?? '';
    final transferContent = config.transferContentTemplate
        .replaceAll('Mã hóa đơn', draft.id)
        .replaceAll('SĐT khách', customerPhone)
        .trim();
    final uploadedPayload = config.uploadedQrPayload.trim();
    final preferUploaded =
        (config.qrMode == 'uploaded' || config.qrMode == 'both') &&
        uploadedPayload.isNotEmpty;
    final payload = preferUploaded
        ? uploadedPayload
        : config.hasRequiredBankFields
        ? 'BANK=${config.bankName}|ACCOUNT=${config.accountNumber}|HOLDER=${config.accountHolder}|AMOUNT=${draft.totalAmount}|CONTENT=$transferContent'
        : _buildPaymentQrPayload(draft, customer);

    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            PremiumIconBadge(icon: Icons.qr_code_2_rounded, size: 38),
            SizedBox(width: 10),
            Text('QR thanh toán'),
          ],
        ),
        content: SizedBox(
          width: adaptiveDialogWidth(dialogContext, 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _currency(draft.totalAmount),
                  style: Theme.of(dialogContext).textTheme.displayMedium
                      ?.copyWith(color: AppColors.copper),
                ),
                const SizedBox(height: 8),
                if (config.hasRequiredBankFields) ...[
                  _ReceiptInfoLine(label: 'Ngân hàng', value: config.bankName),
                  _ReceiptInfoLine(
                    label: 'Số tài khoản',
                    value: config.accountNumber,
                  ),
                  _ReceiptInfoLine(
                    label: 'Chủ tài khoản',
                    value: config.accountHolder,
                  ),
                  _ReceiptInfoLine(
                    label: 'Nội dung CK',
                    value: transferContent.isEmpty ? draft.id : transferContent,
                  ),
                ] else ...[
                  Text(
                    'Chưa cấu hình tài khoản ngân hàng. Đang dùng QR nội bộ của bill.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    await _showPaymentQrDialog(context, draft, customer);
  }
}

Future<void> _showCheckoutSuccessDialog(
  BuildContext context,
  InvoiceDraft invoice,
  CustomerProfile? customer,
) async {
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('checkout-success-dialog'),
      title: const Row(
        children: [
          PremiumIconBadge(
            icon: Icons.check_circle_outline_rounded,
            size: 40,
          ),
          SizedBox(width: 10),
          Text('Thanh toán thành công'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer?.fullName ?? invoice.customerId,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            _ReceiptInfoLine(label: 'Mã hóa đơn', value: invoice.id),
            _ReceiptInfoLine(
              label: 'Tổng tiền',
              value: _currency(invoice.totalAmount),
            ),
            _ReceiptInfoLine(
              label: 'Thanh toán',
              value: invoice.paymentMethod,
            ),
            _ReceiptInfoLine(
              label: 'Thời gian',
              value: _invoiceTimeLabel(invoice.paidAt ?? invoice.updatedAt),
            ),
            const SizedBox(height: 10),
            Text(
              'Hóa đơn đã được lưu. Có thể xem phiếu, in hoặc xuất PDF ngay bây giờ.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const Key('checkout-success-view-receipt'),
          onPressed: () =>
              _showInvoiceReceiptDialog(dialogContext, invoice, customer),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Xem phiếu'),
        ),
        TextButton.icon(
          onPressed: () => _printPaidInvoice(context, invoice, customer),
          icon: const Icon(Icons.print_outlined),
          label: const Text('In phiếu'),
        ),
        TextButton.icon(
          onPressed: () => _exportPaidInvoicePdf(context, invoice, customer),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Hóa đơn mới'),
        ),
      ],
    ),
  );
}

Future<void> _showInvoiceReceiptDialog(
  BuildContext context,
  InvoiceDraft invoice,
  CustomerProfile? customer,
) async {
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('invoice-receipt-dialog'),
      title: Row(
        children: [
          const PremiumIconBadge(
            icon: Icons.receipt_long_outlined,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phiếu thanh toán'),
                Text(
                  invoice.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 620),
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReceiptInfoLine(
              label: 'Khách hàng',
              value: customer?.fullName ?? invoice.customerId,
            ),
            _ReceiptInfoLine(label: 'SĐT', value: customer?.phone ?? '-'),
            _ReceiptInfoLine(
              label: 'Thanh toán',
              value:
                  '${invoice.paymentMethod} · ${_invoiceTimeLabel(invoice.paidAt ?? invoice.updatedAt)}',
            ),
            const SizedBox(height: 8),
            const PremiumDivider(),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: invoice.lines.length,
                separatorBuilder: (_, _) => const PremiumDivider(),
                itemBuilder: (context, index) {
                  final line = invoice.lines[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${line.quantity} × ${_currency(line.unitPrice)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _currency(line.totalPrice),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const PremiumDivider(),
            const SizedBox(height: 8),
            _ReceiptInfoLine(
              label: 'Tạm tính',
              value: _currency(invoice.subtotal),
            ),
            _ReceiptInfoLine(
              label: 'Giảm giá',
              value: _currency(invoice.discountAmount),
            ),
            _ReceiptInfoLine(
              label: 'TỔNG CỘNG',
              value: _currency(invoice.totalAmount),
              strong: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _printPaidInvoice(context, invoice, customer),
          icon: const Icon(Icons.print_outlined),
          label: const Text('In phiếu'),
        ),
        TextButton.icon(
          onPressed: () => _exportPaidInvoicePdf(context, invoice, customer),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Xuất PDF'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

class _ReceiptInfoLine extends StatelessWidget {
  const _ReceiptInfoLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: strong ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: strong ? AppColors.copper : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _invoiceTimeLabel(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

Future<({pw.Font regular, pw.Font bold})> _loadReceiptPdfFonts() async {
  final candidates = <({String regular, String bold})>[];

  if (Platform.isWindows) {
    final windowsDir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final fontsDir = path.join(windowsDir, 'Fonts');
    candidates.add((
      regular: path.join(fontsDir, 'segoeui.ttf'),
      bold: path.join(fontsDir, 'segoeuib.ttf'),
    ));
    candidates.add((
      regular: path.join(fontsDir, 'arial.ttf'),
      bold: path.join(fontsDir, 'arialbd.ttf'),
    ));
  } else if (Platform.isLinux) {
    candidates.add((
      regular: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      bold: '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ));
  } else if (Platform.isMacOS) {
    candidates.add((
      regular: '/System/Library/Fonts/Supplemental/Arial.ttf',
      bold: '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ));
  }

  for (final candidate in candidates) {
    final regularFile = File(candidate.regular);
    if (!await regularFile.exists()) continue;

    final regularBytes = await regularFile.readAsBytes();
    final regular = pw.Font.ttf(
      regularBytes.buffer.asByteData(
        regularBytes.offsetInBytes,
        regularBytes.lengthInBytes,
      ),
    );

    final boldFile = File(candidate.bold);
    if (!await boldFile.exists()) {
      return (regular: regular, bold: regular);
    }

    final boldBytes = await boldFile.readAsBytes();
    final bold = pw.Font.ttf(
      boldBytes.buffer.asByteData(
        boldBytes.offsetInBytes,
        boldBytes.lengthInBytes,
      ),
    );
    return (regular: regular, bold: bold);
  }

  final fallback = pw.Font.helvetica();
  return (regular: fallback, bold: fallback);
}

Future<File> _createInvoicePdfFile(
  InvoiceDraft invoice,
  CustomerProfile? customer,
) async {
  final fonts = await _loadReceiptPdfFonts();
  final document = pw.Document();
  final paidAt = invoice.paidAt ?? invoice.updatedAt;
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);

  document.addPage(
    pw.MultiPage(
      theme: theme,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text(
          'PHIẾU THANH TOÁN',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Mã hóa đơn: ${invoice.id}'),
        pw.Text('Khách hàng: ${customer?.fullName ?? invoice.customerId}'),
        pw.Text('SĐT: ${customer?.phone ?? '-'}'),
        pw.Text('Thanh toán: ${invoice.paymentMethod}'),
        pw.Text('Thời gian: ${_invoiceTimeLabel(paidAt)}'),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: const ['Hạng mục', 'SL', 'Đơn giá', 'Thành tiền'],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10.5),
          data: invoice.lines
              .map(
                (line) => [
                  line.title,
                  '${line.quantity}',
                  _currency(line.unitPrice),
                  _currency(line.totalPrice),
                ],
              )
              .toList(growable: false),
        ),
        pw.SizedBox(height: 18),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [pw.Text('Tạm tính: ${_currency(invoice.subtotal)}')],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Giảm giá: ${_currency(invoice.discountAmount)}'),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              'TỔNG CỘNG: ${_currency(invoice.totalAmount)}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  final docsDir = await getApplicationDocumentsDirectory();
  final invoicesDir = Directory(
    path.join(docsDir.path, 'HairSpaManager', 'invoices'),
  );
  if (!await invoicesDir.exists()) {
    await invoicesDir.create(recursive: true);
  }
  final safeId = invoice.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  final file = File(path.join(invoicesDir.path, '$safeId.pdf'));
  await file.writeAsBytes(await document.save());
  return file;
}

Future<void> _exportPaidInvoicePdf(
  BuildContext context,
  InvoiceDraft invoice,
  CustomerProfile? customer,
) async {
  try {
    final file = await _createInvoicePdfFile(invoice, customer);
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        ['/select,${file.path}'],
        mode: ProcessStartMode.detached,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xuất PDF hóa đơn: ${file.path}')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Xuất PDF thất bại: $error')),
    );
  }
}

Future<void> _printPaidInvoice(
  BuildContext context,
  InvoiceDraft invoice,
  CustomerProfile? customer,
) async {
  try {
    final file = await _createInvoicePdfFile(invoice, customer);
    final bytes = await file.readAsBytes();
    final printed = await Printing.layoutPdf(
      name: 'Phiếu thanh toán ${invoice.id}',
      onLayout: (_) async => bytes,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          printed ? 'Đã gửi phiếu tới máy in.' : 'Đã hủy in phiếu.',
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('In phiếu thất bại: $error')),
    );
  }
}

Future<void> _showInvoiceHistoryDialog(
  BuildContext context,
  List<InvoiceDraft> history,
  List<CustomerProfile> customers,
) async {
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.history_rounded, size: 36),
          SizedBox(width: 9),
          Text('Hóa đơn gần đây'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 560),
        height: 380,
        child: history.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Chưa có hóa đơn',
                message: 'Hóa đơn đã thanh toán sẽ xuất hiện tại đây.',
              )
            : ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, _) => const PremiumDivider(),
                itemBuilder: (context, index) {
                  final invoice = history[index];
                  final paidAt = invoice.paidAt;
                  final time = paidAt == null
                      ? ''
                      : _invoiceTimeLabel(paidAt);
                  final customer = _customerForInvoice(invoice, customers);
                  return ListTile(
                    key: Key('invoice-history-${invoice.id}'),
                    onTap: () => _showInvoiceReceiptDialog(
                      dialogContext,
                      invoice,
                      customer,
                    ),
                    leading: const PremiumIconBadge(
                      icon: Icons.receipt_long_outlined,
                      size: 34,
                    ),
                    title: Text(
                      _customerNameFor(invoice.customerId, customers),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '$time · ${invoice.paymentMethod}\n${invoice.id}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currency(invoice.totalAmount),
                          style: TextStyle(
                            color: AppColors.copper,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

CustomerProfile? _customerForInvoice(
  InvoiceDraft invoice,
  List<CustomerProfile> customers,
) {
  for (final customer in customers) {
    if (customer.id == invoice.customerId) return customer;
  }
  return null;
}

String _customerNameFor(String id, List<CustomerProfile> customers) {
  for (final customer in customers) {
    if (customer.id == id) return customer.fullName;
  }
  return id;
}
