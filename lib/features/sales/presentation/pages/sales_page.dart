import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/retail_product_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';

final salesProductQueryProvider = StateProvider<String>((ref) => '');
final salesProductTypeProvider = StateProvider<String?>((ref) => null);
final salesProductRefreshNonceProvider = StateProvider<int>((ref) => 0);

final salesFilteredProductsProvider = FutureProvider<List<RetailProductItem>>((
  ref,
) async {
  ref.watch(salesProductRefreshNonceProvider);
  final query = ref.watch(salesProductQueryProvider).trim();
  final type = ref.watch(salesProductTypeProvider);
  return ref
      .watch(retailProductsRepositoryProvider)
      .fetchProducts(query: query.isEmpty ? null : query, type: type);
});

class SalesPage extends ConsumerWidget {
  const SalesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsState = ref.watch(salesFilteredProductsProvider);

    return productsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được sản phẩm: $error')),
      data: (items) => _SalesView(items: items),
    );
  }
}

class _SalesView extends ConsumerWidget {
  const _SalesView({required this.items});

  final List<RetailProductItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(salesProductQueryProvider);
    final type = ref.watch(salesProductTypeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SalesHero(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: query,
                        onChanged: (value) {
                          ref.read(salesProductQueryProvider.notifier).state =
                              value;
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Tìm theo tên, thương hiệu, nhóm sản phẩm',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        initialValue: type,
                        decoration: const InputDecoration(
                          labelText: 'Nhóm sản phẩm',
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tất cả'),
                          ),
                          ...RetailProductUpsertInput.productTypes.map(
                            (item) => DropdownMenuItem<String?>(
                              value: item,
                              child: Text(item),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          ref.read(salesProductTypeProvider.notifier).state =
                              value;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _openProductEditor(context, ref),
                      icon: const Icon(Icons.add_box_outlined),
                      label: const Text('Thêm sản phẩm'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '${items.length} sản phẩm',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có sản phẩm. Bấm Thêm sản phẩm để tạo mới.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              Text('${item.productType} - ${item.brand}'),
                              Text('Gia: ${item.salePriceLabel}'),
                              Text(
                                'Hoa hồng: ${item.commissionPercent.toStringAsFixed(item.commissionPercent % 1 == 0 ? 0 : 1)}%',
                              ),
                              Text(
                                item.isHiddenFromStaff
                                    ? 'Ẩn với staff'
                                    : 'Hiển với staff',
                              ),
                            ],
                          ),
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            Switch.adaptive(
                              value: item.isActive,
                              onChanged: (value) async {
                                await ref
                                    .read(retailProductsRepositoryProvider)
                                    .updateProductActive(item.id, value);
                                if (!context.mounted) {
                                  return;
                                }
                                ref
                                    .read(
                                      salesProductRefreshNonceProvider.notifier,
                                    )
                                    .state++;
                                ref.invalidate(retailProductsViewProvider);
                              },
                            ),
                            IconButton(
                              onPressed: () => _openProductEditor(
                                context,
                                ref,
                                existing: item,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemCount: items.length,
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openProductEditor(
    BuildContext context,
    WidgetRef ref, {
    RetailProductItem? existing,
  }) async {
    final input = await showDialog<RetailProductUpsertInput>(
      context: context,
      builder: (_) => _RetailProductEditorDialog(existing: existing),
    );

    if (input == null || !context.mounted) {
      return;
    }

    await ref
        .read(retailProductsRepositoryProvider)
        .saveProduct(input, existingId: existing?.id);

    if (!context.mounted) {
      return;
    }

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

class _SalesHero extends StatelessWidget {
  const _SalesHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bán hàng',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text(
            'Quản lý sản phẩm bán lẻ, set hoa hồng và ẩn/hiển cho màn hình nhân viên.',
          ),
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
    _volumeController = TextEditingController(
      text: existing?.volumeLabel ?? '',
    );
    _priceController = TextEditingController(
      text: existing?.salePrice.toString() ?? '',
    );
    _commissionController = TextEditingController(
      text: existing == null
          ? '0'
          : existing.commissionPercent.toStringAsFixed(
              existing.commissionPercent % 1 == 0 ? 0 : 1,
            ),
    );
    _type =
        existing?.productType ?? RetailProductUpsertInput.productTypes.first;
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
      backgroundColor: AppColors.panel,
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Nhập tên sản phẩm'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(labelText: 'Thương hiệu'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _volumeController,
                  decoration: const InputDecoration(
                    labelText: 'Dung tích/Quy cách',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Nhóm sản phẩm'),
                  items: RetailProductUpsertInput.productTypes
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _type = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Giá bán (đ)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Nhập giá hợp lệ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _commissionController,
                  decoration: const InputDecoration(
                    labelText: 'Hoa hồng nhân viên (%)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed < 0 || parsed > 100) {
                      return 'Nhập phần trăm 0-100';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isHiddenFromStaff,
                  title: const Text('Ẩn với nhân viên'),
                  subtitle: const Text(
                    'Tắt thì staff không thấy trong cửa sổ Staff',
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
