import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/inventory_item.dart';
import '../../../../core/providers/inventory_providers.dart';
import '../../../../core/repositories/inventory_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/compact_management.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  String _query = '';
  String? _groupFilter;
  String? _brandFilter;
  String? _selectedProductId;
  final Set<String> _checkedProductIds = <String>{};

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
        final groupNames = products
            .map((item) => item.productType.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final brandNames = products
            .map((item) => item.brand.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        final normalizedQuery = _query.trim().toLowerCase();
        final filteredProducts = products.where((item) {
          final queryOk = normalizedQuery.isEmpty ||
              [item.name, item.brand, item.productType, item.volumeLabel].any(
                (value) => value.toLowerCase().contains(normalizedQuery),
              );
          final groupOk =
              _groupFilter == null || item.productType == _groupFilter;
          final brandOk = _brandFilter == null || item.brand == _brandFilter;
          return queryOk && groupOk && brandOk;
        }).toList(growable: false);
        final selected = _resolveSelected(filteredProducts);
        final checkedProducts = products
            .where((item) => _checkedProductIds.contains(item.id))
            .toList(growable: false);
        final movements =
            movementsState.value ?? const <InventoryMovementItem>[];
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
        final outOfStockCount =
            products.where((item) => item.isOutOfStock).length;

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
                actionLabel: 'Nhập hàng',
                actionIcon: Icons.add_box_outlined,
                onAction: () => _startBatchMutation(
                  context,
                  checkedProducts,
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
                onChanged: (value) => setState(() {
                  _query = value;
                  _selectedProductId = null;
                  _checkedProductIds.clear();
                }),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 19),
                  hintText: 'Tìm tên, thương hiệu, nhóm hoặc dung tích…',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _groupFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.category_outlined, size: 18),
                        labelText: 'Nhóm sản phẩm',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả nhóm'),
                        ),
                        ...groupNames.map(
                          (value) => DropdownMenuItem<String?>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _groupFilter = value;
                        _selectedProductId = null;
                        _checkedProductIds.clear();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _brandFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.sell_outlined, size: 18),
                        labelText: 'Thương hiệu',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả thương hiệu'),
                        ),
                        ...brandNames.map(
                          (value) => DropdownMenuItem<String?>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _brandFilter = value;
                        _selectedProductId = null;
                        _checkedProductIds.clear();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BatchActionBar(
                visibleProducts: filteredProducts,
                checkedProductIds: _checkedProductIds,
                onToggleAll: () => _toggleAll(filteredProducts),
                onReceive: () => _startBatchMutation(
                  context,
                  checkedProducts,
                  _InventoryMutationMode.receive,
                ),
                onAdjust: () => _startBatchMutation(
                  context,
                  checkedProducts,
                  _InventoryMutationMode.adjust,
                ),
                onClear: () => setState(_checkedProductIds.clear),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = _InventoryListPanel(
                      products: filteredProducts,
                      selectedProductId: selected?.id,
                      checkedProductIds: _checkedProductIds,
                      onSelect: (item) =>
                          setState(() => _selectedProductId = item.id),
                      onToggleChecked: (item, checked) => setState(() {
                        if (checked) {
                          _checkedProductIds.add(item.id);
                        } else {
                          _checkedProductIds.remove(item.id);
                        }
                      }),
                      onReceive: (item) => _startBatchMutation(
                        context,
                        [item],
                        _InventoryMutationMode.receive,
                      ),
                      onAdjust: (item) => _startBatchMutation(
                        context,
                        [item],
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
                          : () => _startBatchMutation(
                                context,
                                [selected],
                                _InventoryMutationMode.receive,
                              ),
                      onAdjust: selected == null
                          ? null
                          : () => _startBatchMutation(
                                context,
                                [selected],
                                _InventoryMutationMode.adjust,
                              ),
                    );

                    if (constraints.maxWidth < 920) {
                      return Column(
                        children: [
                          Expanded(flex: 10, child: list),
                          const SizedBox(height: 10),
                          Expanded(flex: 10, child: detail),
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

  void _toggleAll(List<InventoryProductItem> products) {
    final ids = products.map((item) => item.id).toSet();
    final allChecked = ids.isNotEmpty && ids.every(_checkedProductIds.contains);
    setState(() {
      if (allChecked) {
        _checkedProductIds.removeAll(ids);
      } else {
        _checkedProductIds.addAll(ids);
      }
    });
  }

  Future<void> _startBatchMutation(
    BuildContext context,
    List<InventoryProductItem> products,
    _InventoryMutationMode mode,
  ) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chọn ít nhất một sản phẩm trước khi thao tác.'),
        ),
      );
      return;
    }

    final input = await showDialog<_InventoryBatchInput>(
      context: context,
      builder: (_) => _InventoryBatchMutationDialog(
        products: products,
        mode: mode,
      ),
    );
    if (input == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _InventoryConfirmDialog(
        products: products,
        input: input,
        mode: mode,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final repository = ref.read(inventoryRepositoryProvider);
      final batchLines = [
        for (final line in input.lines)
          InventoryStockBatchLine(
            productId: line.productId,
            quantity: line.quantity,
          ),
      ];
      if (mode == _InventoryMutationMode.receive) {
        await repository.receiveStockBatch(lines: batchLines, note: input.note);
      } else {
        await repository.adjustStockBatch(lines: batchLines, note: input.note);
      }
      if (!context.mounted) return;
      ref.read(inventoryRefreshNonceProvider.notifier).state++;
      setState(_checkedProductIds.clear);
      final total = input.lines.fold<int>(0, (sum, line) => sum + line.quantity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == _InventoryMutationMode.receive
                ? 'Đã nhập ${input.lines.length} sản phẩm, tổng $total đơn vị.'
                : 'Đã điều chỉnh tồn ${input.lines.length} sản phẩm.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ref.read(inventoryRefreshNonceProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật được tồn kho: $error')),
      );
    }
  }
}

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.visibleProducts,
    required this.checkedProductIds,
    required this.onToggleAll,
    required this.onReceive,
    required this.onAdjust,
    required this.onClear,
  });

  final List<InventoryProductItem> visibleProducts;
  final Set<String> checkedProductIds;
  final VoidCallback onToggleAll;
  final VoidCallback onReceive;
  final VoidCallback onAdjust;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final visibleIds = visibleProducts.map((item) => item.id).toSet();
    final visibleChecked =
        visibleIds.where(checkedProductIds.contains).length;
    final allChecked =
        visibleIds.isNotEmpty && visibleChecked == visibleIds.length;
    final someChecked = visibleChecked > 0 && !allChecked;

    return Container(
      key: const Key('inventory-batch-actions'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: allChecked ? true : (someChecked ? null : false),
            onChanged: visibleProducts.isEmpty ? null : (_) => onToggleAll(),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              checkedProductIds.isEmpty
                  ? 'Chọn sản phẩm để nhập hoặc điều chỉnh cùng lúc'
                  : 'Đã chọn ${checkedProductIds.length} sản phẩm',
              style: TextStyle(
                color: checkedProductIds.isEmpty
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
          if (checkedProductIds.isNotEmpty) ...[
            TextButton(onPressed: onClear, child: const Text('Bỏ chọn')),
            const SizedBox(width: 4),
          ],
          FilledButton.tonalIcon(
            key: const Key('inventory-batch-receive'),
            onPressed: checkedProductIds.isEmpty ? null : onReceive,
            icon: const Icon(Icons.add_box_outlined, size: 17),
            label: const Text('Nhập hàng'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            key: const Key('inventory-batch-adjust'),
            onPressed: checkedProductIds.isEmpty ? null : onAdjust,
            icon: const Icon(Icons.tune_rounded, size: 17),
            label: const Text('Điều chỉnh'),
          ),
        ],
      ),
    );
  }
}

class _InventoryListPanel extends StatelessWidget {
  const _InventoryListPanel({
    required this.products,
    required this.selectedProductId,
    required this.checkedProductIds,
    required this.onSelect,
    required this.onToggleChecked,
    required this.onReceive,
    required this.onAdjust,
  });

  final List<InventoryProductItem> products;
  final String? selectedProductId;
  final Set<String> checkedProductIds;
  final ValueChanged<InventoryProductItem> onSelect;
  final void Function(InventoryProductItem item, bool checked) onToggleChecked;
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
                        checked: checkedProductIds.contains(item.id),
                        onSelect: () => onSelect(item),
                        onChecked: (value) =>
                            onToggleChecked(item, value ?? false),
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
    required this.checked,
    required this.onSelect,
    required this.onChecked,
    required this.onReceive,
    required this.onAdjust,
  });

  final InventoryProductItem product;
  final bool selected;
  final bool checked;
  final VoidCallback onSelect;
  final ValueChanged<bool?> onChecked;
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Checkbox(value: checked, onChanged: onChecked),
              SizedBox(
                width: 32,
                height: 32,
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
              const SizedBox(width: 9),
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
              const SizedBox(width: 8),
              SizedBox(
                width: 62,
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
              IconButton(
                tooltip: 'Nhập riêng sản phẩm này',
                onPressed: onReceive,
                icon: const Icon(Icons.add_box_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Điều chỉnh riêng sản phẩm này',
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
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
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

class _InventoryBatchLine {
  const _InventoryBatchLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;
}

class _InventoryBatchInput {
  const _InventoryBatchInput({required this.lines, required this.note});

  final List<_InventoryBatchLine> lines;
  final String note;
}

class _InventoryBatchMutationDialog extends StatefulWidget {
  const _InventoryBatchMutationDialog({
    required this.products,
    required this.mode,
  });

  final List<InventoryProductItem> products;
  final _InventoryMutationMode mode;

  @override
  State<_InventoryBatchMutationDialog> createState() =>
      _InventoryBatchMutationDialogState();
}

class _InventoryBatchMutationDialogState
    extends State<_InventoryBatchMutationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  late final Map<String, TextEditingController> _quantityControllers;

  @override
  void initState() {
    super.initState();
    _quantityControllers = {
      for (final product in widget.products)
        product.id: TextEditingController(
          text: widget.mode == _InventoryMutationMode.adjust
              ? product.stockOnHand.toString()
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReceive = widget.mode == _InventoryMutationMode.receive;
    return AlertDialog(
      title: Text(
        isReceive
            ? 'Nhập hàng • ${widget.products.length} sản phẩm'
            : 'Điều chỉnh tồn • ${widget.products.length} sản phẩm',
      ),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height.clamp(360, 610).toDouble(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isReceive
                    ? 'Nhập số lượng cộng thêm cho từng sản phẩm đã chọn.'
                    : 'Nhập tồn thực tế mới cho từng sản phẩm đã chọn.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final product = widget.products[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.panelAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${product.metaLabel} • Tồn ${product.stockOnHand}',
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
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 155,
                            child: TextFormField(
                              key: Key('inventory-batch-quantity-${product.id}'),
                              controller: _quantityControllers[product.id],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: isReceive ? 'SL nhập' : 'Tồn mới',
                              ),
                              validator: (value) {
                                final quantity =
                                    int.tryParse(value?.trim() ?? '');
                                if (quantity == null) {
                                  return 'Nhập số nguyên';
                                }
                                if (isReceive && quantity <= 0) {
                                  return 'Phải > 0';
                                }
                                if (!isReceive && quantity < 0) {
                                  return 'Không được âm';
                                }
                                if (!isReceive &&
                                    quantity == product.stockOnHand) {
                                  return 'Chưa thay đổi';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Ghi chú chung (không bắt buộc)',
                  hintText: 'Ví dụ: nhập từ nhà cung cấp / kiểm kê cuối ngày',
                ),
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
          key: const Key('inventory-batch-submit'),
          onPressed: _submit,
          child: Text(isReceive ? 'Nhập hàng' : 'Lưu điều chỉnh'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final lines = widget.products
        .map(
          (product) => _InventoryBatchLine(
            productId: product.id,
            quantity: int.parse(
              _quantityControllers[product.id]!.text.trim(),
            ),
          ),
        )
        .toList(growable: false);
    Navigator.of(context).pop(
      _InventoryBatchInput(lines: lines, note: _noteController.text.trim()),
    );
  }
}

class _InventoryConfirmDialog extends StatelessWidget {
  const _InventoryConfirmDialog({
    required this.products,
    required this.input,
    required this.mode,
  });

  final List<InventoryProductItem> products;
  final _InventoryBatchInput input;
  final _InventoryMutationMode mode;

  @override
  Widget build(BuildContext context) {
    final isReceive = mode == _InventoryMutationMode.receive;
    final total = input.lines.fold<int>(0, (sum, line) => sum + line.quantity);
    final previewNames = products.take(4).map((item) => item.name).join(', ');
    final more = products.length > 4 ? ' và ${products.length - 4} sản phẩm khác' : '';

    return AlertDialog(
      key: const Key('inventory-final-confirm-dialog'),
      title: Text(isReceive ? 'Xác nhận nhập hàng?' : 'Xác nhận điều chỉnh tồn?'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isReceive
                  ? 'Sẽ nhập ${products.length} sản phẩm, tổng $total đơn vị.'
                  : 'Sẽ cập nhật tồn mới cho ${products.length} sản phẩm.',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('$previewNames$more'),
            const SizedBox(height: 10),
            Text(
              'Chọn Có để ghi thay đổi vào kho. Chọn Không để quay lại mà không cập nhật.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('inventory-confirm-no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Không'),
        ),
        FilledButton(
          key: const Key('inventory-confirm-yes'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Có'),
        ),
      ],
    );
  }
}
