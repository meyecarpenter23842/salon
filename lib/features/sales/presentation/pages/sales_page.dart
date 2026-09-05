import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/catalog_option.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/retail_product_upsert_input.dart';
import '../../../../core/providers/catalog_options_providers.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/catalog_option_picker.dart';
import '../../../../shared/widgets/compact_management.dart';
import '../../../../shared/widgets/premium_workspace.dart';
import '../widgets/product_performance_panel.dart';

final salesProductQueryProvider = StateProvider<String>((ref) => '');
final salesProductTypeProvider = StateProvider<String?>((ref) => null);
final salesProductStatusProvider = StateProvider<String>((ref) => 'Tất cả');
final salesProductRefreshNonceProvider = StateProvider<int>((ref) => 0);
final salesSelectedProductIndexProvider = StateProvider<int>((ref) => 0);

final salesFilteredProductsProvider = FutureProvider<List<RetailProductItem>>((
  ref,
) async {
  ref.watch(salesProductRefreshNonceProvider);
  final query = ref.watch(salesProductQueryProvider).trim();
  final type = ref.watch(salesProductTypeProvider);
  final status = ref.watch(salesProductStatusProvider);
  final products = await ref
      .watch(retailProductsRepositoryProvider)
      .fetchProducts(query: query.isEmpty ? null : query, type: type);
  return products
      .where((item) {
        if (status == 'Đang bán') return item.isActive;
        if (status == 'Tạm ẩn') return !item.isActive;
        return true;
      })
      .toList(growable: false);
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
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];

    return KeyedSubtree(
      key: const Key('sales-premium-workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompactManagementHeader(
            key: const Key('sales-premium-header'),
            title: 'Sản phẩm',
            subtitle:
                'Catalog bán lẻ, giá và trạng thái. Hoa hồng bán lẻ chưa được tính.',
            actionLabel: 'Thêm sản phẩm',
            actionIcon: Icons.add_box_outlined,
            onAction: () => _openProductEditor(context, ref),
          ),
          const SizedBox(height: 12),
          const _SalesToolbar(),
          const SizedBox(height: 12),
          Expanded(
            child: _SalesWorkspace(
              items: items,
              selectedIndex: effectiveIndex,
              selected: selected,
            ),
          ),
        ],
      ),
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
      SnackBar(
        content: Text(
          existing == null ? 'Đã thêm sản phẩm mới' : 'Đã cập nhật sản phẩm',
        ),
      ),
    );
  }
}

class _SalesToolbar extends ConsumerWidget {
  const _SalesToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedStatus = ref.watch(salesProductStatusProvider);
    final groupNamesState = ref.watch(
      catalogOptionNamesProvider(CatalogOptionKind.productGroup),
    );
    final groupNames =
        groupNamesState.value ?? CatalogOptionKind.productGroup.defaultNames;
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
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Tất cả nhóm'),
        ),
        ...groupNames.map(
          (item) => DropdownMenuItem<String?>(value: item, child: Text(item)),
        ),
      ],
      onChanged: (value) {
        ref.read(salesProductTypeProvider.notifier).state = value;
        ref.read(salesSelectedProductIndexProvider.notifier).state = 0;
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (constraints.maxWidth >= 760)
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: 230, child: picker),
                ],
              )
            else ...[
              search,
              const SizedBox(height: 8),
              picker,
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final status in const ['Tất cả', 'Đang bán', 'Tạm ẩn'])
                  FilterChip(
                    label: Text(status),
                    selected: selectedStatus == status,
                    showCheckmark: false,
                    onSelected: (_) {
                      ref.read(salesProductStatusProvider.notifier).state =
                          status;
                      ref
                              .read(salesSelectedProductIndexProvider.notifier)
                              .state =
                          0;
                    },
                  ),
              ],
            ),
          ],
        );
      },
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
    final list = _ProductList(items: items, selectedIndex: selectedIndex);
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(selected?.id ?? 'sales-product-empty'),
      child: _ProductDetail(product: selected),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView(
            primary: false,
            children: [
              SizedBox(height: 320, child: list),
              const SizedBox(height: 10),
              SizedBox(height: 380, child: detail),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 11, child: list),
            const SizedBox(width: 10),
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
                  onTap: () =>
                      ref
                              .read(salesSelectedProductIndexProvider.notifier)
                              .state =
                          index,
                  child: Row(
                    children: [
                      PremiumIconBadge(
                        icon: Icons.shopping_bag_outlined,
                        size: 36,
                        tone: item.isActive
                            ? AppColors.copper
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.productType}${item.brand.isEmpty ? '' : ' • ${item.brand}'}${item.volumeLabel.isEmpty ? '' : ' • ${item.volumeLabel}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.salePriceLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          PremiumStatusPill(
                            label: item.isActive ? 'Đang bán' : 'Tạm ẩn',
                            tone: item.isActive
                                ? AppColors.success
                                : AppColors.textMuted,
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
          message: 'Giá bán, hiệu suất và quyền hiển thị sẽ hiện ở đây.',
        ),
      );
    }

    final tone = item.isActive ? AppColors.success : AppColors.textMuted;
    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.shopping_bag_outlined,
                  size: 46,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.productType}${item.brand.isEmpty ? '' : ' • ${item.brand}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                PremiumStatusPill(
                  label: item.isActive ? 'Đang kinh doanh' : 'Tạm ngưng',
                  tone: tone,
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Sửa sản phẩm',
                  onPressed: () => _openProductEditor(context, ref, item),
                  icon: const Icon(Icons.edit_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Thêm thao tác',
                  onSelected: (value) async {
                    if (value != 'toggle') return;
                    await ref
                        .read(retailProductsRepositoryProvider)
                        .updateProductActive(item.id, !item.isActive);
                    if (!context.mounted) return;
                    ref.read(salesProductRefreshNonceProvider.notifier).state++;
                    ref.invalidate(retailProductsViewProvider);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          item.isActive
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        title: Text(item.isActive ? 'Tạm ẩn' : 'Bật lại'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const PremiumDivider(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _ProductMetricStrip(item: item),
                  const SizedBox(height: 10),
                  Expanded(child: ProductPerformancePanel(productId: item.id)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.featureSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _info(
                            icon: Icons.sell_outlined,
                            label: 'Giá bán',
                            value: item.salePriceLabel,
                          ),
                        ),
                        Expanded(
                          child: _info(
                            icon: Icons.badge_outlined,
                            label: 'Bàn nhân viên',
                            value: item.isHiddenFromStaff
                                ? 'Đang ẩn'
                                : 'Được bán',
                          ),
                        ),
                        Expanded(
                          child: _info(
                            icon: Icons.straighten_outlined,
                            label: 'Quy cách',
                            value: item.volumeLabel.isEmpty
                                ? 'Chưa khai báo'
                                : item.volumeLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.copper),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProductEditor(
    BuildContext context,
    WidgetRef ref,
    RetailProductItem existing,
  ) async {
    final input = await showAppDialog<RetailProductUpsertInput>(
      context: context,
      builder: (_) => _RetailProductEditorDialog(existing: existing),
    );
    if (input == null || !context.mounted) return;

    await ref
        .read(retailProductsRepositoryProvider)
        .saveProduct(input, existingId: existing.id);
    if (!context.mounted) return;
    ref.read(salesProductRefreshNonceProvider.notifier).state++;
    ref.invalidate(retailProductsViewProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Đã cập nhật sản phẩm')));
  }
}

class _ProductMetricStrip extends StatelessWidget {
  const _ProductMetricStrip({required this.item});

  final RetailProductItem item;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Giá bán', item.salePriceLabel),
      ('Staff', item.isHiddenFromStaff ? 'Ẩn' : 'Hiển thị'),
      ('Hoa hồng bán lẻ', 'Chưa hỗ trợ'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var index = 0; index < metrics.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Text(
                    metrics[index].$1,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    metrics[index].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            if (index < metrics.length - 1)
              Container(
                width: 1,
                height: 32,
                color: AppColors.workspaceDivider,
              ),
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
  State<_RetailProductEditorDialog> createState() =>
      _RetailProductEditorDialogState();
}

class _RetailProductEditorDialogState
    extends State<_RetailProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _volumeController;
  late final TextEditingController _priceController;
  late final TextEditingController _commissionController;
  late String _brand;
  late String _type;
  late bool _isActive;
  late bool _isHiddenFromStaff;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _brand = existing?.brand ?? '';
    _volumeController = TextEditingController(
      text: existing?.volumeLabel ?? '',
    );
    _priceController = TextEditingController(
      text: existing?.salePrice.toString() ?? '',
    );
    _commissionController = TextEditingController(
      text: existing == null ? '0' : _percent(existing.commissionPercent),
    );
    _type =
        existing?.productType ?? RetailProductUpsertInput.productTypes.first;
    _isActive = existing?.isActive ?? true;
    _isHiddenFromStaff = existing?.isHiddenFromStaff ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập tên sản phẩm'
                      : null,
                ),
                const SizedBox(height: 12),
                CatalogOptionPicker(
                  kind: CatalogOptionKind.productBrand,
                  labelText: 'Thương hiệu',
                  value: _brand.isEmpty ? null : _brand,
                  allowEmpty: true,
                  emptyLabel: 'Không thương hiệu',
                  onChanged: (value) => setState(() => _brand = value ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _volumeController,
                  decoration: const InputDecoration(
                    labelText: 'Dung tích/Quy cách',
                  ),
                ),
                const SizedBox(height: 12),
                CatalogOptionPicker(
                  kind: CatalogOptionKind.productGroup,
                  labelText: 'Nhóm sản phẩm',
                  value: _type,
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
                    return parsed == null || parsed <= 0
                        ? 'Nhập giá hợp lệ'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Hoa hồng bán lẻ chưa được tính trong phiên bản hiện tại.',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isHiddenFromStaff,
                  title: const Text('Ẩn với nhân viên'),
                  subtitle: const Text(
                    'Bật thì staff không thấy sản phẩm này trong cửa sổ Staff',
                  ),
                  onChanged: (value) =>
                      setState(() => _isHiddenFromStaff = value),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      RetailProductUpsertInput(
        name: _nameController.text.trim(),
        brand: _brand,
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
