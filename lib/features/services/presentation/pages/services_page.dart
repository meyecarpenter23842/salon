import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/models/service_formula_item.dart';
import '../../../../core/models/service_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final serviceSearchQueryProvider = StateProvider<String>((ref) => '');

final serviceCategoryFilterProvider = StateProvider<String>((ref) => 'Tất cả');

final selectedServiceIndexProvider = StateProvider<int>((ref) => 0);

final filteredServicesProvider = FutureProvider<List<ServiceCatalogItem>>((
  ref,
) async {
  final services = await ref
      .watch(servicesRepositoryProvider)
      .fetchServicesView();
  final query = ref.watch(serviceSearchQueryProvider).trim().toLowerCase();
  final category = ref.watch(serviceCategoryFilterProvider);

  return services.where((item) {
    final matchesCategory = category == 'Tất cả' || item.category == category;
    final matchesQuery =
        query.isEmpty ||
        [
          item.name,
          item.category,
          item.description,
        ].any((value) => value.toString().toLowerCase().contains(query));

    return matchesCategory && matchesQuery;
  }).toList();
});

Future<void> _openServiceEditor(
  BuildContext context,
  WidgetRef ref, {
  ServiceCatalogItem? service,
}) async {
  final allServices = await ref
      .read(servicesRepositoryProvider)
      .fetchServicesView();

  if (!context.mounted) {
    return;
  }

  final input = await showDialog<ServiceUpsertInput>(
    context: context,
    builder: (dialogContext) =>
        _ServiceEditorDialog(service: service, existingServices: allServices),
  );

  if (input == null || !context.mounted) {
    return;
  }

  final savedService = await ref
      .read(servicesRepositoryProvider)
      .saveService(input, existingId: service?.id);

  if (!context.mounted) {
    return;
  }

  ref.read(serviceSearchQueryProvider.notifier).state = savedService.name;
  ref.read(serviceCategoryFilterProvider.notifier).state =
      savedService.category;
  ref.read(selectedServiceIndexProvider.notifier).state = 0;
  ref.invalidate(filteredServicesProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        service == null
            ? 'Đã thêm dịch vụ ${savedService.name}'
            : 'Đã cập nhật dịch vụ ${savedService.name}',
      ),
    ),
  );
}

Future<void> _toggleServiceActive(
  BuildContext context,
  WidgetRef ref,
  ServiceCatalogItem service,
) async {
  final updatedService = await ref
      .read(servicesRepositoryProvider)
      .updateServiceActive(service.id, !service.isActive);

  if (!context.mounted) {
    return;
  }

  ref.read(serviceSearchQueryProvider.notifier).state = updatedService.name;
  ref.read(serviceCategoryFilterProvider.notifier).state =
      updatedService.category;
  ref.read(selectedServiceIndexProvider.notifier).state = 0;
  ref.invalidate(filteredServicesProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Đã chuyển ${updatedService.name} sang ${updatedService.statusLabel}',
      ),
    ),
  );
}

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(filteredServicesProvider);

    return services.when(
      data: (items) => _ServicesView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được dịch vụ: $error')),
    );
  }
}

class _ServicesView extends ConsumerWidget {
  const _ServicesView({required this.items});

  final List<ServiceCatalogItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedServiceIndexProvider);
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selectedService = items.isEmpty ? null : items[effectiveIndex];
    final category = ref.watch(serviceCategoryFilterProvider);

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 520;

        Widget buildBody() {
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1180;

              if (compact) {
                return Column(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _ServiceListPanel(
                        items: items,
                        selectedIndex: effectiveIndex,
                      ),
                    ),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(
                      flex: 4,
                      child: _ServiceDetailPanel(service: selectedService),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _ServiceListPanel(
                      items: items,
                      selectedIndex: effectiveIndex,
                    ),
                  ),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(
                    flex: 4,
                    child: _ServiceDetailPanel(service: selectedService),
                  ),
                ],
              );
            },
          );
        }

        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              const _ServicesHero(),
              const SizedBox(height: AppDimens.heroGap),
              _ServicesSummaryRow(items: items),
              const SizedBox(height: AppDimens.sectionGap),
              _ServicesToolbar(selectedCategory: category),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 680, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ServicesHero(),
            const SizedBox(height: AppDimens.heroGap),
            _ServicesSummaryRow(items: items),
            const SizedBox(height: AppDimens.sectionGap),
            _ServicesToolbar(selectedCategory: category),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _ServicesHero extends StatelessWidget {
  const _ServicesHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dịch vụ',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text(
            'Catalog dịch vụ hiện đã đi theo typed flow và runtime SQLite, giữ nguyên desktop layout để chuẩn bị cho bước CRUD thật tiếp theo.',
            style: TextStyle(color: AppColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _ServicesSummaryRow extends StatelessWidget {
  const _ServicesSummaryRow({required this.items});

  final List<ServiceCatalogItem> items;

  @override
  Widget build(BuildContext context) {
    final activeCount = items.where((item) => item.isActive).length;
    final hiddenCount = items.where((item) => !item.isActive).length;
    final topService = items
        .where((item) => item.popularityLabel == 'Bán chạy')
        .length;

    final cards = [
      _SummaryCard(label: 'Tổng dịch vụ', value: '${items.length}'),
      _SummaryCard(label: 'Đang áp dụng', value: '$activeCount'),
      _SummaryCard(label: 'Tạm ẩn', value: '$hiddenCount'),
      _SummaryCard(label: 'Bán chạy', value: '$topService'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        if (constraints.maxWidth < 1280) {
          final columns = constraints.maxWidth < 1080 ? 2 : 3;
          final cardWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card),
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicesToolbar extends ConsumerWidget {
  const _ServicesToolbar({required this.selectedCategory});

  final String selectedCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ['Tất cả', ...ServiceUpsertInput.categories];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: ref.watch(serviceSearchQueryProvider),
                onChanged: (value) {
                  ref.read(serviceSearchQueryProvider.notifier).state = value;
                  ref.read(selectedServiceIndexProvider.notifier).state = 0;
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm theo tên, nhóm dịch vụ hoặc mô tả...',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () => _openServiceEditor(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Thêm dịch vụ'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: categories
              .map(
                (item) => FilterChip(
                  label: Text(item),
                  selected: item == selectedCategory,
                  onSelected: (_) {
                    ref.read(serviceCategoryFilterProvider.notifier).state =
                        item;
                    ref.read(selectedServiceIndexProvider.notifier).state = 0;
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ServiceListPanel extends ConsumerWidget {
  const _ServiceListPanel({required this.items, required this.selectedIndex});

  final List<ServiceCatalogItem> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Danh mục dịch vụ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${items.length} mục',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (items.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Không có dịch vụ phù hợp với bộ lọc hiện tại.',
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ServiceTile(
                    service: items[index],
                    selected: index == selectedIndex,
                    onTap: () {
                      ref.read(selectedServiceIndexProvider.notifier).state =
                          index;
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final ServiceCatalogItem service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusColor = service.isActive
        ? AppColors.success
        : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.copper : AppColors.border,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        onTap: onTap,
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.avatarFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.content_cut_rounded, color: AppColors.copper),
        ),
        title: Text(
          service.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${service.category} • ${service.durationLabel}'),
              const SizedBox(height: 4),
              Text(
                service.popularityLabel,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              service.priceLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              service.statusLabel,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceDetailPanel extends ConsumerWidget {
  const _ServiceDetailPanel({required this.service});

  final ServiceCatalogItem? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (service == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chọn một dịch vụ để xem chi tiết.'),
        ),
      );
    }

    final statusColor = service!.isActive
        ? AppColors.success
        : AppColors.warning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            service!.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            service!.statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _DetailMetricCard(
                            label: 'Giá',
                            value: service!.priceLabel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailMetricCard(
                            label: 'Thời lượng',
                            value: service!.durationLabel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DetailMetricCard(
                            label: 'Nhóm',
                            value: service!.category,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _DetailSection(
                      title: 'Độ phổ biến',
                      content: service!.popularityLabel,
                    ),
                    const SizedBox(height: 12),
                    _DetailSection(
                      title: 'Mô tả',
                      content: service!.description,
                    ),
                    const SizedBox(height: 18),
                    _ServiceFormulaPanel(service: service!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () =>
                        _openServiceEditor(context, ref, service: service),
                    child: const Text('Sửa dịch vụ'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _toggleServiceActive(context, ref, service!),
                    child: Text(
                      service!.isActive ? 'Ẩn dịch vụ' : 'Bật dịch vụ',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailMetricCard extends StatelessWidget {
  const _DetailMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

// ?? Formula Panel ??????????????????????????????????????????????????????????????

class _ServiceFormulaPanel extends ConsumerWidget {
  const _ServiceFormulaPanel({required this.service});

  final ServiceCatalogItem service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formulasAsync = ref.watch(serviceFormulasViewProvider);

    return formulasAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (allFormulas) {
        final formula = allFormulas
            .where((f) => f.serviceId == service.id)
            .toList();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.panelRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Định lượng (chủ xem)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _openFormulaEditor(
                      context,
                      ref,
                      service: service,
                      existing: formula.isEmpty ? null : formula.first,
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    child: Text(formula.isEmpty ? 'Thêm' : 'Sửa'),
                  ),
                ],
              ),
              if (formula.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  formula.first.formulaText,
                  style: const TextStyle(height: 1.6),
                ),
                if (formula.first.isHiddenFromStaff) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Ẩn với nhân viên',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Chưa có định lượng.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFormulaEditor(
    BuildContext context,
    WidgetRef ref, {
    required ServiceCatalogItem service,
    ServiceFormulaItem? existing,
  }) async {
    final result = await showDialog<({String formulaText, bool hidden})>(
      context: context,
      builder: (_) =>
          _FormulaEditorDialog(service: service, existing: existing),
    );

    if (result == null || !context.mounted) {
      return;
    }

    await ref
        .read(serviceFormulaRepositoryProvider)
        .saveFormula(
          serviceId: service.id,
          serviceName: service.name,
          formulaText: result.formulaText,
          isHiddenFromStaff: result.hidden,
          existingFormulaId: existing?.id,
        );

    ref.invalidate(serviceFormulasViewProvider);
  }
}

class _FormulaEditorDialog extends StatefulWidget {
  const _FormulaEditorDialog({required this.service, this.existing});

  final ServiceCatalogItem service;
  final ServiceFormulaItem? existing;

  @override
  State<_FormulaEditorDialog> createState() => _FormulaEditorDialogState();
}

class _FormulaEditorDialogState extends State<_FormulaEditorDialog> {
  late final TextEditingController _formulaController;
  late bool _hidden;

  @override
  void initState() {
    super.initState();
    _formulaController = TextEditingController(
      text: widget.existing?.formulaText ?? '',
    );
    _hidden = widget.existing?.isHiddenFromStaff ?? true;
  }

  @override
  void dispose() {
    _formulaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text('Định lượng: ${widget.service.name}'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _formulaController,
              decoration: const InputDecoration(
                labelText: 'Công thức / định lượng',
                hintText: 'VD: Dầu gội 10ml + thuốc nhuộm 2:1...',
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _hidden,
              title: const Text('Ẩn với nhân viên'),
              subtitle: const Text('Chỉ chủ mới xem được định lượng này'),
              onChanged: (v) => setState(() => _hidden = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            final text = _formulaController.text.trim();
            if (text.isEmpty) return;
            Navigator.of(context).pop((formulaText: text, hidden: _hidden));
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

// ?? Service Editor ??????????????????????????????????????????????????????????????

class _ServiceEditorDialog extends StatefulWidget {
  const _ServiceEditorDialog({this.service, required this.existingServices});

  final ServiceCatalogItem? service;
  final List<ServiceCatalogItem> existingServices;

  @override
  State<_ServiceEditorDialog> createState() => _ServiceEditorDialogState();
}

class _ServiceEditorDialogState extends State<_ServiceEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _durationController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late String _category;
  late String _popularityLabel;
  late bool _isActive;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _nameController = TextEditingController(text: service?.name ?? '');
    _durationController = TextEditingController(
      text: service?.durationMinutes.toString() ?? '60',
    );
    _priceController = TextEditingController(
      text: service?.price.toString() ?? '300000',
    );
    _descriptionController = TextEditingController(
      text: service?.description ?? '',
    );
    _category = ServiceUpsertInput.normalizeCategory(
      service?.category ?? 'Chăm sóc',
    );
    _popularityLabel = ServiceUpsertInput.normalizePopularityLabel(
      service?.popularityLabel ?? 'Ổn định',
    );
    _isActive = service?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.service != null;

    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(isEditing ? 'Sửa dịch vụ' : 'Thêm dịch vụ'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 540),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Tên dịch vụ'),
                  validator: (value) {
                    final normalizedName = ServiceUpsertInput.normalizeName(
                      value ?? '',
                    );
                    if (normalizedName.isEmpty) {
                      return 'Nhập tên dịch vụ';
                    }

                    final hasDuplicate = widget.existingServices.any(
                      (item) =>
                          item.id != widget.service?.id &&
                          ServiceUpsertInput.normalizeName(
                                item.name,
                              ).toLowerCase() ==
                              normalizedName.toLowerCase(),
                    );

                    if (hasDuplicate) {
                      return 'Tên dịch vụ đã tồn tại';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Nhóm dịch vụ'),
                  items: ServiceUpsertInput.categories
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
                      _category = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durationController,
                        decoration: const InputDecoration(
                          labelText: 'Thời lượng (phút)',
                        ),
                        validator: (value) {
                          final minutes = int.tryParse(value?.trim() ?? '');
                          if (minutes == null || minutes <= 0) {
                            return 'Nhập số phút hợp lệ';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(labelText: 'Giá (đ)'),
                        validator: (value) {
                          final price = int.tryParse(value?.trim() ?? '');
                          if (price == null || price <= 0) {
                            return 'Nhập giá hợp lệ';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _popularityLabel,
                  decoration: const InputDecoration(labelText: 'Độ phổ biến'),
                  items: ServiceUpsertInput.popularityLabels
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
                      _popularityLabel = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  title: const Text('Đang áp dụng'),
                  subtitle: Text(
                    _isActive
                        ? 'Dịch vụ đang hiển thị trong catalog'
                        : 'Dịch vụ đang tạm ẩn',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  maxLines: 3,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Nhập mô tả dịch vụ'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: Text(isEditing ? 'Lưu dịch vụ' : 'Tạo dịch vụ'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    Navigator.of(context).pop(
      ServiceUpsertInput.normalized(
        name: _nameController.text.trim(),
        category: _category,
        durationMinutes: int.parse(_durationController.text.trim()),
        price: int.parse(_priceController.text.trim()),
        description: _descriptionController.text,
        isActive: _isActive,
        popularityLabel: _popularityLabel,
      ),
    );
  }
}
