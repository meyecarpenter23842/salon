import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/inventory_item.dart';
import '../../../../core/providers/inventory_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/compact_management.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String _query = '';
  String? _selectedProductId;

  @override
  Widget build(BuildContext context) {
    final productsState = ref.watch(inventoryProductsViewProvider);
    final movementsState = ref.watch(inventoryMovementsViewProvider);

    return productsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _InventoryErrorState(
        message: '$error',
        onRetry: () => ref.invalidate(inventoryProductsViewProvider),
      ),
      data: (products) {
        final normalizedQuery = _query.trim().toLowerCase();
        final filteredProducts = normalizedQuery.isEmpty
            ? products
            : products
                  .where(
                    (item) => [
                      item.name,
                      item.brand,
                      item.productType,
                      item.volumeLabel,
                    ].any(
                      (value) => value.toLowerCase().contains(normalizedQuery),
                    ),
                  )
                  .toList(growable: false);
        final selected = _resolveSelected(filteredProducts);
        final movements = movementsState.value ?? const <InventoryMovementItem>[];
        final selectedMovements = selected == null
            ? const <InventoryMovementItem>[]
            : movements
                  .where((item) => item.productId == selected.id)
                  .toList(growable: false);
        final totalUnits = products.fold<int>(
          0,
          (sum, item) => sum + item.stockOnHand,
        );
        final lowStockCount = products.where((item) => item.isLowStock).length;
        final outOfStockCount = products.where((item) => item.isOutOfStock).length;

        return KeyedSubtree(
          key: const Key('inventory-premium-workspace'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompactManagementHeader(
                key: const Key('inventory-premium-header'),
                title: 'Kho hàng',
                subtitle:
                    'Theo dõi tồn nội bộ, nhập kho và điều chỉnh nhanh. Không chặn bán hàng.',
                actionLabel: 'Nhập kho',
                actionIcon: Icons.add_box_outlined,
                onAction: selected == null
                    ? () => _showNoProductMessage(context)
                    : () => _openMutationDialog(
                        context,
                        selected,
                        _InventoryMutationMode.receive,
                      ),
              ),
              const SizedBox(height: 10),
              CompactManagementSummary(
                items: [
                  '${products.length} sản phẩm',
                  '$totalUnits đơn vị tồn',
                  '$lowStockCount sắp hết',
                  '$outOfStockCount hết hàng',
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                  hintText: 'Tìm tên, thương hiệu, nhóm hoặc dung tích…',
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = _InventoryListPanel(
                      products: filteredProducts,
                      selectedProductId: selected?.id,
                      onSelect: (item) {
                        setState(() => _selectedProductId = item.id);
                      },
                      onReceive: (item) => _openMutationDialog(
                        context,
                        item,
                        _InventoryMutationMode.receive,
                      ),
                      onAdjust: (item) => _openMutationDialog(
                        context,
                        item,
                        _InventoryMutationMode.adjust,
                      ),
                    );
                    final detail = _InventoryDetailPanel(
                      product: selected,
                      movements: selectedMovements,
                      movementsLoading: movementsState.isLoading,
                      movementsError: movementsState.hasError,
                      onReceive: selected == null
                          ? null
                          : () => _openMutationDialog(
                              context,
                              selected,
                              _InventoryMutationMode.receive,
                            ),
                      onAdjust: selected == null
                          ? null
                          : () => _openMutationDialog(
                              context,
                              selected,
                              _InventoryMutationMode.adjust,
                            ),
                    );

                    if (constraints.maxWidth < 920) {
                      return Column(
                        children: [
                          Expanded(flex: 11, child: list),
                          const SizedBox(height: 10),
                          Expanded(flex: 9, child: detail),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 12, child: list),
                        const SizedBox(width: 10),
                        Expanded(flex: 8, child: detail),
                      ],
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

  InventoryProductItem? _resolveSelected(List<InventoryProductItem> products) {
    if (products.isEmpty) return null;
    final selectedId = _selectedProductId;
    if (selectedId == null) return products.first;
    for (final product in products) {
      if (product.id == selectedId) return product;
    }
    return products.first;
  }

  Future<void> _openMutationDialog(
    BuildContext context,
    InventoryProductItem product,
    _InventoryMutationMode mode,
  ) async {
    setState(() => _selectedProductId = product.id);
    final input = await showDialog<_InventoryMutationInput>(
      context: context,
      builder: (_) => _InventoryMutationDialog(product: product, mode: mode),
    );
    if (input == null || !mounted) return;

    try {
      final repository = ref.read(inventoryRepositoryProvider);
      if (mode == _InventoryMutationMode.receive) {
        await repository.receiveStock(
          productId: product.id,
          quantity: input.quantity,
          note: input.note,
        );
      } else {
        await repository.adjustStock(
          productId: product.id,
          newQuantity: input.quantity,
          note: input.note,
        );
      }
      if (!context.mounted) return;
      ref.read(inventoryRefreshNonceProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == _InventoryMutationMode.receive
                ? 'Đã nhập ${input.quantity} đơn vị ${product.name}'
                : 'Đã điều chỉnh tồn ${product.name} về ${input.quantity}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật được tồn kho: $error')),
      );
    }
  }

  void _showNoProductMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chưa có sản phẩm để nhập kho.')),
    );
  }
}

class _InventoryListPanel extends StatelessWidget {
  const _InventoryListPanel({
    required this.products,
    required this.selectedProductId,
    required this.onSelect,
    required this.onReceive,
    required this.onAdjust,
  });

  final List<InventoryProductItem> products;
  final String? selectedProductId;
  final ValueChanged<InventoryProductItem> onSelect;
  final ValueChanged<InventoryProductItem> onReceive;
  final ValueChanged<InventoryProductItem> onAdjust;

  @override
  Widget build(BuildContext context) {
    return _InventorySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Icon(Icons.warehouse_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tồn hiện tại',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${products.length} dòng',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('Không có sản phẩm phù hợp.'))
                : ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: AppColors.border.withValues(alpha: 0.55),
                    ),
                    itemBuilder: (context, index) {
                      final item = products[index];
                      return _InventoryProductRow(
                        product: item,
                        selected: item.id == selectedProductId,
                        onSelect: () => onSelect(item),
                        onReceive: () => onReceive(item),
                        onAdjust: () => onAdjust(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InventoryProductRow extends StatelessWidget {
  const _InventoryProductRow({
    required this.product,
    required this.selected,
    required this.onSelect,
    required this.onReceive,
    required this.onAdjust,
  });

  final InventoryProductItem product;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onReceive;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final stockTone = product.isOutOfStock
        ? AppColors.danger
        : product.isLowStock
        ? AppColors.warning
        : AppColors.success;

    return Material(
      color: selected ? AppColors.selectedSurface : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: stockTone.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 17,
                    color: stockTone,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.metaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${product.stockOnHand}',
                      style: TextStyle(
                        color: stockTone,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      product.isOutOfStock
                          ? 'Hết hàng'
                          : product.isLowStock
                          ? 'Sắp hết'
                          : 'Còn hàng',
                      style: TextStyle(
                        color: stockTone,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Nhập kho',
                onPressed: onReceive,
                icon: const Icon(Icons.add_box_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Điều chỉnh tồn',
                onPressed: onAdjust,
                icon: const Icon(Icons.tune_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryDetailPanel extends StatelessWidget {
  const _InventoryDetailPanel({
    required this.product,
    required this.movements,
    required this.movementsLoading,
    required this.movementsError,
    required this.onReceive,
    required this.onAdjust,
  });

  final InventoryProductItem? product;
  final List<InventoryMovementItem> movements;
  final bool movementsLoading;
  final bool movementsError;
  final VoidCallback? onReceive;
  final VoidCallback? onAdjust;

  @override
  Widget build(BuildContext context) {
    final item = product;
    if (item == null) {
      return const _InventorySurface(
        child: Center(child: Text('Chọn một sản phẩm để xem biến động tồn.')),
      );
    }

    return _InventorySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.metaLabel} • Tồn ${item.stockOnHand}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onReceive,
                        icon: const Icon(Icons.add_box_outlined, size: 17),
                        label: const Text('Nhập kho'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onAdjust,
                        icon: const Icon(Icons.tune_rounded, size: 17),
                        label: const Text('Điều chỉnh'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              'Biến động gần đây',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: movementsLoading
                ? const Center(child: CircularProgressIndicator())
                : movementsError
                ? const Center(child: Text('Không tải được lịch sử tồn.'))
                : movements.isEmpty
                ? const Center(child: Text('Chưa có biến động tồn kho.'))
                : ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    itemCount: movements.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) =>
                        _MovementRow(item: movements[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.item});

  final InventoryMovementItem item;

  @override
  Widget build(BuildContext context) {
    final tone = item.isReceipt
        ? AppColors.success
        : item.quantityDelta < 0
        ? AppColors.warning
        : AppColors.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.65)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isReceipt ? Icons.move_to_inbox_outlined : Icons.tune_rounded,
            color: tone,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.movementLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      item.quantityDeltaLabel,
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.stockBefore} → ${item.stockAfter} • ${DateFormat('dd/MM HH:mm').format(item.createdAt)}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                ),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.note.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventorySurface extends StatelessWidget {
  const _InventorySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _InventoryErrorState extends StatelessWidget {
  const _InventoryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 36),
          const SizedBox(height: 10),
          const Text(
            'Không tải được kho hàng',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

enum _InventoryMutationMode { receive, adjust }

class _InventoryMutationInput {
  const _InventoryMutationInput({required this.quantity, required this.note});

  final int quantity;
  final String note;
}

class _InventoryMutationDialog extends StatefulWidget {
  const _InventoryMutationDialog({required this.product, required this.mode});

  final InventoryProductItem product;
  final _InventoryMutationMode mode;

  @override
  State<_InventoryMutationDialog> createState() =>
      _InventoryMutationDialogState();
}

class _InventoryMutationDialogState extends State<_InventoryMutationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.mode == _InventoryMutationMode.adjust
          ? widget.product.stockOnHand.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReceive = widget.mode == _InventoryMutationMode.receive;
    return AlertDialog(
      title: Text(isReceive ? 'Nhập kho' : 'Điều chỉnh tồn'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Tồn hiện tại: ${widget.product.stockOnHand}',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _quantityController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isReceive ? 'Số lượng nhập' : 'Tồn thực tế mới',
                  prefixIcon: Icon(
                    isReceive ? Icons.add_box_outlined : Icons.tune_rounded,
                  ),
                ),
                validator: (value) {
                  final quantity = int.tryParse(value?.trim() ?? '');
                  if (quantity == null) return 'Nhập một số nguyên hợp lệ';
                  if (isReceive && quantity <= 0) {
                    return 'Số lượng nhập phải lớn hơn 0';
                  }
                  if (!isReceive && quantity < 0) {
                    return 'Tồn kho không được âm';
                  }
                  if (!isReceive && quantity == widget.product.stockOnHand) {
                    return 'Tồn mới đang bằng tồn hiện tại';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (không bắt buộc)',
                  hintText: 'Ví dụ: nhập từ nhà cung cấp / kiểm kê cuối ngày',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Kho chỉ dùng để theo dõi nội bộ; thao tác này không khóa hay thay đổi luồng tính tiền.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
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
          onPressed: _submit,
          child: Text(isReceive ? 'Xác nhận nhập' : 'Lưu điều chỉnh'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _InventoryMutationInput(
        quantity: int.parse(_quantityController.text.trim()),
        note: _noteController.text.trim(),
      ),
    );
  }
}
