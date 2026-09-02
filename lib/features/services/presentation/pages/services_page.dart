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
        Widget buildBody() {
          return LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1080;

              if (stacked) {
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
                    flex: 11,
                    child: _ServiceListPanel(
                      items: items,
                      selectedIndex: effectiveIndex,
                    ),
                  ),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(
                    flex: 9,
                    child: _ServiceDetailPanel(service: selectedService),
                  ),
                ],
              );
            },
          );
        }

        final shortViewport = viewport.maxHeight < 590;
        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              _ServicesToolbar(selectedCategory: category),
              const SizedBox(height: 12),
              _ServicesSummaryRow(items: items),
              const SizedBox(height: 14),
              SizedBox(height: 620, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServicesToolbar(selectedCategory: category),
            const SizedBox(height: 12),
            _ServicesSummaryRow(items: items),
            const SizedBox(height: 14),
            Expanded(child: buildBody()),
          ],
        );
      },
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
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  hintText: 'Tìm dịch vụ, nhóm hoặc mô tả',
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _openServiceEditor(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Thêm dịch vụ'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories
              .map(
                (item) => FilterChip(
                  label: Text(item),
                  selected: item == selectedCategory,
                  showCheckmark: false,
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

    final metrics = [
      _SummaryMetric(
        icon: Icons.content_cut_rounded,
        label: 'Tổng dịch vụ',
        value: '${items.length}',
      ),
      _SummaryMetric(
        icon: Icons.check_circle_outline_rounded,
        label: 'Đang áp dụng',
        value: '$activeCount',
      ),
      _SummaryMetric(
        icon: Icons.visibility_off_outlined,
        label: 'Tạm ẩn',
        value: '$hiddenCount',
      ),
      _SummaryMetric(
        icon: Icons.trending_up_rounded,
        label: 'Bán chạy',
        value: '$topService',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Wrap(
              spacing: 22,
              runSpacing: 12,
              children: metrics,
            );
          }

          return Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(child: metrics[index]),
                if (index < metrics.length - 1)
                  Container(
                    width: 1,
                    height: 30,
                    color: AppColors.workspaceDivider,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.textMuted),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Danh mục dịch vụ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Chọn một dịch vụ để xem và chỉnh sửa thông tin.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${items.length} mục',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.workspaceDivider),
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
                padding: const EdgeInsets.symmetric(vertical: 6),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Material(
        color: selected ? AppColors.selectedSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.copper : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.copper.withValues(alpha: 0.14)
                        : AppColors.panelAlt,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.content_cut_rounded,
                    size: 17,
                    color: selected ? AppColors.copper : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        service.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${service.category} · ${service.durationLabel} · ${service.popularityLabel}',
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
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      service.priceLabel,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          service.statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      return Card(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.content_cut_rounded,
                  size: 28,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 10),
                const Text('Chọn một dịch vụ để xem chi tiết.'),
              ],
            ),
          ),
        ),
      );
    }

    final current = service!;
    final statusColor = current.isActive
        ? AppColors.success
        : AppColors.warning;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.copper.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.content_cut_rounded,
                    size: 19,
                    color: AppColors.copper,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${current.category} · ${current.popularityLabel}',
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
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        current.statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.workspaceDivider),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceFacts(service: current),
                  const SizedBox(height: 22),
                  Text(
                    'Mô tả',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    current.description,
                    style: const TextStyle(fontSize: 13, height: 1.55),
                  ),
                  const SizedBox(height: 22),
                  Divider(height: 1, color: AppColors.workspaceDivider),
                  const SizedBox(height: 18),
                  _ServiceFormulaPanel(service: current),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.workspaceDivider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _openServiceEditor(context, ref, service: current),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Sửa dịch vụ'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _toggleServiceActive(context, ref, current),
                  child: Text(current.isActive ? 'Ẩn' : 'Bật lại'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceFacts extends StatelessWidget {
  const _ServiceFacts({required this.service});

  final ServiceCatalogItem service;

  @override
  Widget build(BuildContext context) {
    final facts = [
      _ServiceFact(label: 'Giá', value: service.priceLabel),
      _ServiceFact(label: 'Thời lượng', value: service.durationLabel),
      _ServiceFact(label: 'Độ phổ biến', value: service.popularityLabel),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Wrap(
            spacing: 24,
            runSpacing: 16,
            children: facts,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < facts.length; index++) ...[
              Expanded(child: facts[index]),
              if (index < facts.length - 1)
                Container(
                  width: 1,
                  height: 42,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.workspaceDivider,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceFact extends StatelessWidget {
  const _ServiceFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

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
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Định lượng · chỉ chủ xem',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openFormulaEditor(
                      context,
                      ref,
                      service: service,
                      existing: formula.isEmpty ? null : formula.first,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                    ),
                    child: Text(formula.isEmpty ? 'Thêm' : 'Sửa'),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                formula.isEmpty ? 'Chưa có định lượng.' : formula.first.formulaText,
                style: TextStyle(
                  color: formula.isEmpty
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (formula.isNotEmpty && formula.first.isHiddenFromStaff) ...[
                const SizedBox(height: 7),
                Text(
                  'Ẩn với nhân viên',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
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
