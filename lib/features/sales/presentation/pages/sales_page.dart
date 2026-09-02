import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/retail_product_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final salesProductQueryProvider = StateProvider<String>((ref) => '');
final salesProductTypeProvider = StateProvider<String?>((ref) => null);
final salesProductRefreshNonceProvider = StateProvider<int>((ref) => 0);
final salesSelectedProductIndexProvider = StateProvider<int>((ref) => 0);

final salesFilteredProductsProvider = FutureProvider<List<RetailProductItem>>((ref) async {
  ref.watch(salesProductRefreshNonceProvider);
  final query = ref.watch(salesProductQueryProvider).trim();
  final type = ref.watch(salesProductTypeProvider);
  return ref.watch(retailProductsRepositoryProvider).fetchProducts(
        query: query.isEmpty ? null : query,
        type: type,
      );
});

class SalesPage extends ConsumerWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(salesFilteredProductsProvider);
    return productsState.when(
      loading: () => const PremiumLoadingState(label: 'Đang tải sản phẩm…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được sản phẩm',
        message: '$error',
        onRetry: () => ref.invalidate(salesFilteredProductsProvider),
      ),
      data: (items) => _SalesView(items: items),
    );
  }
}

class _SalesView extends ConsumerWidget {
  const _SalesView({required this.items});

  final List<RetailProductItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(salesSelectedProductIndexProvider);
    final effectiveIndex = items.isEmpty ? 0 : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final active = items.where((item) => item.isActive).length;
    final staffVisible = items.where((item) => item.isActive && !item.isHiddenFromStaff).length;
    final avgCommission = items.isEmpty
        ? 0.0
        : items.fold<double>(0, (sum, item) => sum + item.commissionPercent) / items.length;

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 760;
        final page = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumSectionCard(
              key: const Key('sales-premium-header'),
              child: PremiumPageHeader(
                icon: Icons.inventory_2_outlined,
                eyebrow: 'Bán lẻ tại salon',
                title: 'Sản phẩm',
                subtitle: 'Quản lý catalog bán lẻ, giá, hoa hồng và quyền hiển thị cho bàn nhân viên.',
                trailing: [
                  PremiumStatusPill(label: '${items.length} sản phẩm', tone: AppColors.copper),
                  FilledButton.icon(
                    onPressed: () => _openProductEditor(context, ref),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Thêm sản phẩm'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SalesStats(
              total: items.length,
              active: active,
              staffVisible: staffVisible,
              avgCommission: avgCommission,
            ),
            const SizedBox(height: 14),
            const _SalesToolbar(),
            const SizedBox(height: 14),
            if (shortViewport)
              SizedBox(
                height: 640,
                child: _SalesWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              )
            else
              Expanded(
                child: _SalesWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              ),
          ],
        );

        return shortViewport
            ? ListView(
                key: const Key('sales-premium-workspace'),
                primary: false,
                children: [page],
              )
            : KeyedSubtree(key: const Key('sales-premium-workspace'), child: page);
      },
    );
  }

  Future<void> _openProductEditor(
    BuildContext context,
    WidgetRef ref, {
    RetailProductItem? existing,
  }) async {
    final input = await showAppDialog<RetailProductUpsertInput>(
      context: context,
      builder: (_) => _RetailProductEditorDialog(existing: existing),
    );
    if (input == null || !context.mounted) return;

    final saved = await ref
        .read(retailProductsRepositoryProvider)
        .saveProduct(input, existingId: existing?.id);
    if (!context.mounted) return;

    ref.read(salesProductQueryProvider.notifier).state = saved.name;
    ref.read(salesSelectedProductIndexProvider.notifier).state = 0;
    ref.read(salesProductRefreshNonceProvider.notifier).state++;
    ref.invalidate(retailProductsViewProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(existing == null ? 'Đã thêm sản phẩm mới' : 'Đã cập nhật sản phẩm')),
    );
  }
}

class _SalesStats extends StatelessWidget {
  const _SalesStats({
    required this.total,
    required this.active,
    required this.staffVisible,
    required this.avgCommission,
  });

  final int total;
  final int active;
  final int staffVisible;
  final double avgCommission;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(icon: Icons.inventory_2_outlined, label: 'Tổng sản phẩm', value: '$total'),
      PremiumStatCard(
        icon: Icons.storefront_outlined,
        label: 'Đang kinh doanh',
        value: '$active',
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.badge_outlined,
        label: 'Staff nhìn thấy',
        value: '$staffVisible',
        tone: AppColors.info,
      ),
      PremiumStatCard(
        icon: Icons.percent_rounded,
        label: 'Hoa hồng trung bình',
        value: '${_percent(avgCommission)}%',
        tone: AppColors.warning,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120 ? 4 : constraints.maxWidth >= 620 ? 2 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        );
      },
    );
  }
}

class _SalesToolbar extends ConsumerWidget {
  const _SalesToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextFormField(
            initialValue: ref.watch(salesProductQueryProvider),
            onChanged: (value) {
              ref.read(salesProductQueryProvider.notifier).state = value;
              ref.read(salesSelectedProductIndexProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Tìm tên, thương hiệu hoặc nhóm sản phẩm',
            ),
          );
          final picker = DropdownButtonFormField<String?>(
            initialValue: ref.watch(salesProductTypeProvider),
            isExpanded: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.category_outlined),
              labelText: 'Nhóm sản phẩm',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Tất cả nhóm')),
              ...RetailProductUpsertInput.productTypes.map(
                (item) => DropdownMenuItem<String?>(value: item, child: Text(item)),
              ),
            ],
            onChanged: (value) {
              ref.read(salesProductTypeProvider.notifier).state = value;
              ref.read(salesSelectedProductIndexProvider.notifier).state = 0;
            },
          );
          if (constraints.maxWidth < 720) {
            return Column(children: [search, const SizedBox(height: 10), picker]);
          }
          return Row(
            children: [
              Expanded(flex: 5, child: search),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: picker),
            ],
          );
        },
      ),
    );
  }
}

class _SalesWorkspace extends StatelessWidget {
  const _SalesWorkspace({
    required this.items,
    required this.selectedIndex,
    required this.selected,
  });

  final List<RetailProductItem> items;
  final int selectedIndex;
  final RetailProductItem? selected;

  @override
  Widget build(BuildContext context) {
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(selected?.id ?? 'sales-product-empty'),
      child: _ProductDetail(product: selected),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            primary: false,
            children: [
              SizedBox(height: 300, child: _ProductList(items: items, selectedIndex: selectedIndex)),
              const SizedBox(height: 12),
              SizedBox(height: 360, child: detail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 11, child: _ProductList(items: items, selectedIndex: selectedIndex)),
            const SizedBox(width: 12),
            Expanded(flex: 9, child: detail),
          ],
        );
      },
    );
  }
}

class _ProductList extends ConsumerWidget {
  const _ProductList({required this.items, required this.selectedIndex});

  final List<RetailProductItem> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.shelves,
      title: 'Catalog bán lẻ',
      subtitle: '${items.length} sản phẩm phù hợp bộ lọc',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Chưa có sản phẩm',
              message: 'Tạo sản phẩm đầu tiên để bắt đầu bán lẻ tại salon.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 54),
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return PremiumInteractiveSurface(
                  selected: selected,
                  onTap: () => ref.read(salesSelectedProductIndexProvider.notifier).state = index,
                  child: Row(
                    children: [
                      PremiumIconBadge(
                        icon: Icons.shopping_bag_outlined,
                        size: 36,
                        tone: item.isActive ? AppColors.copper : AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              '${item.productType}${item.brand.isEmpty ? '' : ' • ${item.brand}'}${item.volumeLabel.isEmpty ? '' : ' • ${item.volumeLabel}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(item.salePriceLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          PremiumStatusPill(
                            label: item.isActive ? 'Đang bán' : 'Tạm ẩn',
                            tone: item.isActive ? AppColors.success : AppColors.textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ProductDetail extends ConsumerWidget {
  const _ProductDetail({required this.product});

  final RetailProductItem? product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = product;
    if (item == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Chọn một sản phẩm',
          message: 'Giá bán, hoa hồng và quyền hiển thị sẽ hiện ở đây.',
        ),
      );
    }

    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const PremiumIconBadge(icon: Icons.shopping_bag_outlined, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('${item.productType}${item.brand.isEmpty ? '' : ' • ${item.brand}'}', style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                PremiumStatusPill(
                  label: item.isActive ? 'Đang kinh doanh' : 'Tạm ngưng',
                  tone: item.isActive ? AppColors.success : AppColors.textMuted,
                ),
              ],
            ),
          ),
          const PremiumDivider(),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _ProductMetricStrip(item: item),
                  const SizedBox(height: 10),
                  PremiumInfoRow(icon: Icons.sell_outlined, label: 'Giá bán', value: item.salePriceLabel),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.percent_rounded,
                    label: 'Hoa hồng nhân viên',
                    value: '${_percent(item.commissionPercent)}%',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Hiển thị ở bàn nhân viên',
                    value: item.isHiddenFromStaff ? 'Đang ẩn với staff' : 'Staff có thể thấy và bán thêm',
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.straighten_outlined,
                    label: 'Dung tích / quy cách',
                    value: item.volumeLabel.isEmpty ? 'Chưa khai báo' : item.volumeLabel,
                  ),
                ],
              ),
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openProductEditor(context, ref, item),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Sửa sản phẩm'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(retailProductsRepositoryProvider).updateProductActive(item.id, !item.isActive);
                    if (!context.mounted) return;
                    ref.read(salesProductRefreshNonceProvider.notifier).state++;
                    ref.invalidate(retailProductsViewProvider);
                  },
                  icon: Icon(item.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  label: Text(item.isActive ? 'Tạm ẩn' : 'Bật lại'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProductEditor(BuildContext context, WidgetRef ref, RetailProductItem existing) async {
    final input = await showAppDialog<RetailProductUpsertInput>(
      context: context,
      builder: (_) => _RetailProductEditorDialog(existing: existing),
    );
    if (input == null || !context.mounted) return;
    final saved = await ref.read(retailProductsRepositoryProvider).saveProduct(input, existingId: existing.id);
    if (!context.mounted) return;
    ref.read(salesProductQueryProvider.notifier).state = saved.name;
    ref.read(salesSelectedProductIndexProvider.notifier).state = 0;
    ref.read(salesProductRefreshNonceProvider.notifier).state++;
    ref.invalidate(retailProductsViewProvider);
  }
}

class _ProductMetricStrip extends StatelessWidget {
  const _ProductMetricStrip({required this.item});

  final RetailProductItem item;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Giá bán', item.salePriceLabel),
      ('Hoa hồng', '${_percent(item.commissionPercent)}%'),
      ('Staff', item.isHiddenFromStaff ? 'Ẩn' : 'Hiển thị'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.featureSurface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(metrics[index].$1, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 5),
                  Text(metrics[index].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (index < metrics.length - 1) Container(width: 1, height: 32, color: AppColors.workspaceDivider),
          ],
        ],
      ),
    );
  }
}

class _RetailProductEditorDialog extends StatefulWidget {
  const _RetailProductEditorDialog({this.existing});

  final RetailProductItem? existing;

  @override
  State<_RetailProductEditorDialog> createState() => _RetailProductEditorDialogState();
}

class _RetailProductEditorDialogState extends State<_RetailProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _volumeController;
  late final TextEditingController _priceController;
  late final TextEditingController _commissionController;
  late String _type;
  late bool _isActive;
  late bool _isHiddenFromStaff;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _brandController = TextEditingController(text: existing?.brand ?? '');
    _volumeController = TextEditingController(text: existing?.volumeLabel ?? '');
    _priceController = TextEditingController(text: existing?.salePrice.toString() ?? '');
    _commissionController = TextEditingController(
      text: existing == null ? '0' : _percent(existing.commissionPercent),
    );
    _type = existing?.productType ?? RetailProductUpsertInput.productTypes.first;
    _isActive = existing?.isActive ?? true;
    _isHiddenFromStaff = existing?.isHiddenFromStaff ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _volumeController.dispose();
    _priceController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Nhập tên sản phẩm' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _brandController, decoration: const InputDecoration(labelText: 'Thương hiệu')),
                const SizedBox(height: 12),
                TextFormField(controller: _volumeController, decoration: const InputDecoration(labelText: 'Dung tích/Quy cách')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Nhóm sản phẩm'),
                  items: RetailProductUpsertInput.productTypes
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Giá bán (đ)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed <= 0 ? 'Nhập giá hợp lệ' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _commissionController,
                  decoration: const InputDecoration(labelText: 'Hoa hồng nhân viên (%)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed < 0 || parsed > 100 ? 'Nhập phần trăm 0-100' : null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isHiddenFromStaff,
                  title: const Text('Ẩn với nhân viên'),
                  subtitle: const Text('Bật thì staff không thấy sản phẩm này trong cửa sổ Staff'),
                  onChanged: (value) => setState(() => _isHiddenFromStaff = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  title: const Text('Đang kinh doanh'),
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      RetailProductUpsertInput(
        name: _nameController.text.trim(),
        brand: _brandController.text.trim(),
        volumeLabel: _volumeController.text.trim(),
        productType: _type,
        salePrice: int.parse(_priceController.text.trim()),
        commissionPercent: double.parse(_commissionController.text.trim()),
        isActive: _isActive,
        isHiddenFromStaff: _isHiddenFromStaff,
      ),
    );
  }
}

String _percent(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
