part of 'invoices_pos_page.dart';

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
          SizedBox(height: dense ? 4 : 12),
          SizedBox(
            width: double.infinity,
            height: dense ? 38 : 44,
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
          const SizedBox(height: 4),
          _CheckoutQuickActions(
            draft: draft,
            selectedCustomer: selectedCustomer,
            dense: dense,
          ),
        ],
      ),
    );
  }
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

class _CheckoutQuickActions extends StatelessWidget {
  const _CheckoutQuickActions({
    required this.draft,
    required this.selectedCustomer,
    required this.dense,
  });

  final InvoiceDraft draft;
  final CustomerProfile? selectedCustomer;
  final bool dense;

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
        width: adaptiveDialogWidth(dialogContext, 520),
        height: 360,
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
                      : '${paidAt.day.toString().padLeft(2, '0')}/'
                            '${paidAt.month.toString().padLeft(2, '0')} '
                            '${paidAt.hour.toString().padLeft(2, '0')}:'
                            '${paidAt.minute.toString().padLeft(2, '0')}';
                  return ListTile(
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
                    subtitle: Text('$time · ${invoice.paymentMethod}'),
                    trailing: Text(
                      _currency(invoice.totalAmount),
                      style: TextStyle(
                        color: AppColors.copper,
                        fontWeight: FontWeight.w800,
                      ),
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

String _customerNameFor(String id, List<CustomerProfile> customers) {
  for (final customer in customers) {
    if (customer.id == id) return customer.fullName;
  }
  return id;
}
