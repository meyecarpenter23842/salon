part of 'invoices_pos_page.dart';

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
      trailing: Tooltip(
        message: draft.isPaid
            ? 'Hóa đơn đã thanh toán'
            : 'Thêm dịch vụ hoặc sản phẩm ở cột giữa',
        child: Icon(
          draft.isPaid ? Icons.lock_outline_rounded : Icons.touch_app_outlined,
          size: 18,
          color: AppColors.textMuted,
        ),
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

class _InvoiceTableHeader extends StatelessWidget {
  const _InvoiceTableHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 470) return const SizedBox.shrink();
        final style = Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(flex: 6, child: Text('Mục', style: style)),
              Expanded(flex: 3, child: Text('Đơn giá', style: style)),
              Expanded(flex: 3, child: Text('SL', style: style)),
              Expanded(
                flex: 4,
                child: Text(
                  'Thành tiền',
                  textAlign: TextAlign.right,
                  style: style,
                ),
              ),
              const SizedBox(width: 30),
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceLineRow extends ConsumerWidget {
  const _InvoiceLineRow({required this.line, required this.isLocked});

  final InvoiceDraftLine line;
  final bool isLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 470;
        final icon = line.isProduct
            ? Icons.shopping_bag_outlined
            : Icons.content_cut_rounded;
        final tone = line.isProduct ? AppColors.info : AppColors.copper;

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Column(
              children: [
                Row(
                  children: [
                    PremiumIconBadge(icon: icon, size: 31, tone: tone),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currency(line.unitPrice),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _InvoiceLineMenu(line: line, isLocked: isLocked),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _QuantityControl(
                      quantity: line.quantity,
                      isLocked: isLocked,
                      onMinus: line.quantity <= 1
                          ? null
                          : () => _updateInvoiceLineQuantity(
                                context,
                                ref,
                                line,
                                line.quantity - 1,
                              ),
                      onPlus: () => _updateInvoiceLineQuantity(
                        context,
                        ref,
                        line,
                        line.quantity + 1,
                      ),
                    ),
                    if (line.discountAmount > 0) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Giảm dòng ${_currency(line.discountAmount)}',
                        child: Icon(
                          Icons.local_offer_outlined,
                          size: 15,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _currency(line.totalPrice),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.copper,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              Expanded(
                flex: 6,
                child: Row(
                  children: [
                    PremiumIconBadge(icon: icon, size: 31, tone: tone),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (line.discountAmount > 0)
                            Text(
                              'Giảm ${_currency(line.discountAmount)}',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  _currency(line.unitPrice),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _QuantityControl(
                    quantity: line.quantity,
                    isLocked: isLocked,
                    onMinus: line.quantity <= 1
                        ? null
                        : () => _updateInvoiceLineQuantity(
                              context,
                              ref,
                              line,
                              line.quantity - 1,
                            ),
                    onPlus: () => _updateInvoiceLineQuantity(
                      context,
                      ref,
                      line,
                      line.quantity + 1,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  _currency(line.totalPrice),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: _InvoiceLineMenu(line: line, isLocked: isLocked),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceLineMenu extends ConsumerWidget {
  const _InvoiceLineMenu({required this.line, required this.isLocked});

  final InvoiceDraftLine line;
  final bool isLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      enabled: !isLocked,
      tooltip: isLocked ? 'Hóa đơn đã khóa' : 'Thao tác dòng',
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: AppColors.textMuted,
      ),
      onSelected: (value) {
        if (value == 'discount') {
          _openLineDiscountEditor(context, ref, line);
        } else if (value == 'remove') {
          _removeInvoiceLine(context, ref, line);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'discount',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.local_offer_outlined),
            title: Text(
              line.discountAmount > 0 ? 'Sửa giảm giá' : 'Giảm giá dòng',
            ),
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Xóa khỏi bill'),
          ),
        ),
      ],
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.quantity,
    required this.isLocked,
    this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final bool isLocked;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyIcon(
            icon: Icons.remove_rounded,
            tooltip: 'Giảm số lượng',
            onTap: isLocked ? null : onMinus,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 25),
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ),
          _QtyIcon(
            icon: Icons.add_rounded,
            tooltip: 'Tăng số lượng',
            onTap: isLocked ? null : onPlus,
          ),
        ],
      ),
    );
  }
}

class _QtyIcon extends StatelessWidget {
  const _QtyIcon({required this.icon, required this.tooltip, this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final action = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: 24,
        height: 26,
        child: Icon(
          icon,
          size: 13,
          color: onTap == null ? AppColors.textMuted : AppColors.textPrimary,
        ),
      ),
    );
    return Tooltip(message: tooltip, child: action);
  }
}

class _BillFooter extends StatelessWidget {
  const _BillFooter({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Row(
        children: [
          Text(
            'Tạm tính',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const Spacer(),
          Text(
            _currency(draft.subtotal),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
