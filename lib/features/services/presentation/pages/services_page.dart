import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/models/service_formula_item.dart';
import '../../../../core/models/service_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';
import '../widgets/service_performance_panel.dart';

final serviceSearchQueryProvider = StateProvider<String>((ref) => '');
final serviceCategoryFilterProvider = StateProvider<String>((ref) => 'Tất cả');
final selectedServiceIndexProvider = StateProvider<int>((ref) => 0);

final filteredServicesProvider = FutureProvider<List<ServiceCatalogItem>>((ref) async {
  final services = await ref.watch(servicesRepositoryProvider).fetchServicesView();
  final query = ref.watch(serviceSearchQueryProvider).trim().toLowerCase();
  final category = ref.watch(serviceCategoryFilterProvider);
  return services.where((item) {
    final categoryOk = category == 'Tất cả' || item.category == category;
    final queryOk = query.isEmpty ||
        [item.name, item.category, item.description]
            .any((value) => value.toLowerCase().contains(query));
    return categoryOk && queryOk;
  }).toList();
});

Future<void> _openServiceEditor(
  BuildContext context,
  WidgetRef ref, {
  ServiceCatalogItem? service,
}) async {
  final all = await ref.read(servicesRepositoryProvider).fetchServicesView();
  if (!context.mounted) return;
  final input = await showDialog<ServiceUpsertInput>(
    context: context,
    builder: (_) => _ServiceEditorDialog(
      service: service,
      existingServices: all,
    ),
  );
  if (input == null || !context.mounted) return;
  final saved = await ref
      .read(servicesRepositoryProvider)
      .saveService(input, existingId: service?.id);
  if (!context.mounted) return;
  ref.read(serviceSearchQueryProvider.notifier).state = saved.name;
  ref.read(serviceCategoryFilterProvider.notifier).state = saved.category;
  ref.read(selectedServiceIndexProvider.notifier).state = 0;
  ref.invalidate(filteredServicesProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        service == null
            ? 'Đã thêm dịch vụ ${saved.name}'
            : 'Đã cập nhật dịch vụ ${saved.name}',
      ),
    ),
  );
}

Future<void> _toggleService(
  BuildContext context,
  WidgetRef ref,
  ServiceCatalogItem service,
) async {
  final updated = await ref
      .read(servicesRepositoryProvider)
      .updateServiceActive(service.id, !service.isActive);
  if (!context.mounted) return;
  ref.read(serviceSearchQueryProvider.notifier).state = updated.name;
  ref.read(serviceCategoryFilterProvider.notifier).state = updated.category;
  ref.read(selectedServiceIndexProvider.notifier).state = 0;
  ref.invalidate(filteredServicesProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Đã chuyển ${updated.name} sang ${updated.statusLabel}'),
    ),
  );
}

class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(filteredServicesProvider).when(
      data: (items) => _ServicesView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Không tải được dịch vụ',
        message: '$error',
      ),
    );
  }
}

class _ServicesView extends ConsumerWidget {
  const _ServicesView({required this.items});

  final List<ServiceCatalogItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedServiceIndexProvider);
    final effective = items.isEmpty ? 0 : index.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effective];
    final active = items.where((item) => item.isActive).length;
    final hidden = items.length - active;
    final hot = items.where((item) => item.popularityLabel == 'Bán chạy').length;

    final header = PremiumSectionCard(
      key: const Key('services-premium-header'),
      child: PremiumPageHeader(
        icon: Icons.content_cut_rounded,
        eyebrow: 'Catalog dịch vụ',
        title: 'Dịch vụ',
        subtitle:
            'Giá, thời lượng, trạng thái và định lượng nội bộ trong cùng một workspace.',
        trailing: [
          PremiumStatusPill(
            label: '${items.length} dịch vụ',
            tone: AppColors.copper,
          ),
          FilledButton.icon(
            onPressed: () => _openServiceEditor(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm dịch vụ'),
          ),
        ],
      ),
    );

    final stats = _StatGrid(
      cards: [
        PremiumStatCard(
          icon: Icons.content_cut_rounded,
          label: 'Tổng dịch vụ',
          value: '${items.length}',
        ),
        PremiumStatCard(
          icon: Icons.check_circle_outline,
          label: 'Đang áp dụng',
          value: '$active',
          tone: AppColors.success,
        ),
        PremiumStatCard(
          icon: Icons.visibility_off_outlined,
          label: 'Tạm ẩn',
          value: '$hidden',
          tone: AppColors.textMuted,
        ),
        PremiumStatCard(
          icon: Icons.trending_up_rounded,
          label: 'Bán chạy',
          value: '$hot',
          tone: AppColors.warning,
        ),
      ],
    );

    final workspace = _Workspace(
      items: items,
      selectedIndex: effective,
      selected: selected,
    );

    return LayoutBuilder(
      builder: (context, viewport) {
        if (viewport.maxHeight < 760) {
          return ListView(
            key: const Key('services-premium-workspace'),
            primary: false,
            children: [
              header,
              const SizedBox(height: 14),
              stats,
              const SizedBox(height: 14),
              const _Toolbar(),
              const SizedBox(height: 14),
              SizedBox(height: 760, child: workspace),
            ],
          );
        }

        return KeyedSubtree(
          key: const Key('services-premium-workspace'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 14),
              stats,
              const SizedBox(height: 14),
              const _Toolbar(),
              const SizedBox(height: 14),
              Expanded(child: workspace),
            ],
          ),
        );
      },
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        const gap = 12.0;
        final width =
            (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(serviceCategoryFilterProvider);
    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: ref.watch(serviceSearchQueryProvider),
            onChanged: (value) {
              ref.read(serviceSearchQueryProvider.notifier).state = value;
              ref.read(selectedServiceIndexProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Tìm dịch vụ, nhóm hoặc mô tả',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in [
                'Tất cả',
                ...ServiceUpsertInput.categories,
              ])
                FilterChip(
                  label: Text(category),
                  selected: category == selected,
                  showCheckmark: false,
                  onSelected: (_) {
                    ref.read(serviceCategoryFilterProvider.notifier).state =
                        category;
                    ref.read(selectedServiceIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.items,
    required this.selectedIndex,
    required this.selected,
  });

  final List<ServiceCatalogItem> items;
  final int selectedIndex;
  final ServiceCatalogItem? selected;

  @override
  Widget build(BuildContext context) {
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(selected?.id ?? 'service-empty'),
      child: _ServiceDetail(service: selected),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1040) {
          return ListView(
            primary: false,
            children: [
              SizedBox(
                height: 310,
                child: _ServiceList(
                  items: items,
                  selectedIndex: selectedIndex,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 430, child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11,
              child: _ServiceList(
                items: items,
                selectedIndex: selectedIndex,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 9, child: detail),
          ],
        );
      },
    );
  }
}

class _ServiceList extends ConsumerWidget {
  const _ServiceList({required this.items, required this.selectedIndex});

  final List<ServiceCatalogItem> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.view_list_outlined,
      title: 'Danh mục dịch vụ',
      subtitle: '${items.length} dịch vụ phù hợp bộ lọc',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.content_cut_rounded,
              title: 'Không có dịch vụ phù hợp',
              message: 'Thử đổi bộ lọc hoặc thêm dịch vụ mới.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 54),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = index == selectedIndex;
                final tone =
                    item.isActive ? AppColors.success : AppColors.textMuted;
                return PremiumInteractiveSurface(
                  selected: isSelected,
                  onTap: () => ref
                      .read(selectedServiceIndexProvider.notifier)
                      .state = index,
                  child: Row(
                    children: [
                      PremiumIconBadge(
                        icon: Icons.content_cut_rounded,
                        size: 36,
                        tone: isSelected ? AppColors.copper : tone,
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
                              '${item.category} • ${item.durationLabel} • ${item.popularityLabel}',
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
                            item.priceLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          PremiumStatusPill(
                            label: item.statusLabel,
                            tone: tone,
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

class _ServiceDetail extends ConsumerWidget {
  const _ServiceDetail({required this.service});

  final ServiceCatalogItem? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = service;
    if (item == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.content_cut_rounded,
          title: 'Chọn một dịch vụ',
          message: 'Giá, mô tả và định lượng sẽ hiện ở đây.',
        ),
      );
    }

    final tone = item.isActive ? AppColors.success : AppColors.textMuted;
    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const PremiumIconBadge(
                  icon: Icons.content_cut_rounded,
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
                        '${item.category} • ${item.popularityLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                PremiumStatusPill(label: item.statusLabel, tone: tone),
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
                  _MetricStrip(item: item),
                  const SizedBox(height: 12),
                  ServicePerformancePanel(serviceId: item.id),
                  const SizedBox(height: 12),
                  PremiumInfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Giá dịch vụ',
                    value: item.priceLabel,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.schedule_outlined,
                    label: 'Thời lượng',
                    value: item.durationLabel,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.notes_outlined,
                    label: 'Mô tả',
                    value: item.description,
                  ),
                  const SizedBox(height: 14),
                  _FormulaPanel(service: item),
                ],
              ),
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final editButton = FilledButton.icon(
                  onPressed: () =>
                      _openServiceEditor(context, ref, service: item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa dịch vụ'),
                );
                final toggleButton = OutlinedButton.icon(
                  onPressed: () => _toggleService(context, ref, item),
                  icon: Icon(
                    item.isActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  label: Text(item.isActive ? 'Tạm ẩn' : 'Bật lại'),
                );

                if (constraints.maxWidth < 370) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      editButton,
                      const SizedBox(height: 8),
                      toggleButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: editButton),
                    const SizedBox(width: 8),
                    Expanded(child: toggleButton),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.item});

  final ServiceCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Giá', item.priceLabel),
      ('Thời lượng', item.durationLabel),
      ('Phổ biến', item.popularityLabel),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
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

class _FormulaPanel extends ConsumerWidget {
  const _FormulaPanel({required this.service});

  final ServiceCatalogItem service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(serviceFormulasViewProvider).when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, _) => const SizedBox.shrink(),
      data: (all) {
        final matches = all.where((formula) => formula.serviceId == service.id).toList();
        final formula = matches.isEmpty ? null : matches.first;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PremiumIconBadge(
                icon: Icons.lock_outline_rounded,
                size: 34,
                tone: AppColors.info,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Định lượng nội bộ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formula?.formulaText ?? 'Chưa có định lượng.',
                      style: TextStyle(
                        color: formula == null
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _edit(context, ref, formula),
                icon: Icon(
                  formula == null ? Icons.add_rounded : Icons.edit_outlined,
                  size: 16,
                ),
                label: Text(formula == null ? 'Thêm' : 'Sửa'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ServiceFormulaItem? existing,
  ) async {
    final result = await showDialog<({String formulaText, bool hidden})>(
      context: context,
      builder: (_) => _FormulaDialog(service: service, existing: existing),
    );
    if (result == null || !context.mounted) return;
    await ref.read(serviceFormulaRepositoryProvider).saveFormula(
          serviceId: service.id,
          serviceName: service.name,
          formulaText: result.formulaText,
          isHiddenFromStaff: result.hidden,
          existingFormulaId: existing?.id,
        );
    ref.invalidate(serviceFormulasViewProvider);
  }
}

class _FormulaDialog extends StatefulWidget {
  const _FormulaDialog({required this.service, this.existing});

  final ServiceCatalogItem service;
  final ServiceFormulaItem? existing;

  @override
  State<_FormulaDialog> createState() => _FormulaDialogState();
}

class _FormulaDialogState extends State<_FormulaDialog> {
  late final TextEditingController controller;
  late bool hidden;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.existing?.formulaText ?? '');
    hidden = widget.existing?.isHiddenFromStaff ?? true;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Định lượng: ${widget.service.name}'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Công thức / định lượng',
              ),
              maxLines: 5,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: hidden,
              title: const Text('Ẩn với nhân viên'),
              onChanged: (value) => setState(() => hidden = value),
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
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.of(context).pop((formulaText: text, hidden: hidden));
            }
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _ServiceEditorDialog extends StatefulWidget {
  const _ServiceEditorDialog({
    this.service,
    required this.existingServices,
  });

  final ServiceCatalogItem? service;
  final List<ServiceCatalogItem> existingServices;

  @override
  State<_ServiceEditorDialog> createState() => _ServiceEditorDialogState();
}

class _ServiceEditorDialogState extends State<_ServiceEditorDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController duration;
  late final TextEditingController price;
  late final TextEditingController description;
  late String category;
  late String popularity;
  late bool active;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    name = TextEditingController(text: service?.name ?? '');
    duration = TextEditingController(
      text: service?.durationMinutes.toString() ?? '60',
    );
    price = TextEditingController(text: service?.price.toString() ?? '300000');
    description = TextEditingController(text: service?.description ?? '');
    category = ServiceUpsertInput.normalizeCategory(
      service?.category ?? 'Chăm sóc',
    );
    popularity = ServiceUpsertInput.normalizePopularityLabel(
      service?.popularityLabel ?? 'Ổn định',
    );
    active = service?.isActive ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    duration.dispose();
    price.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.service == null ? 'Thêm dịch vụ' : 'Sửa dịch vụ'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 540),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên dịch vụ'),
                  validator: (value) {
                    final normalized =
                        ServiceUpsertInput.normalizeName(value ?? '');
                    if (normalized.isEmpty) return 'Nhập tên dịch vụ';
                    final duplicate = widget.existingServices.any(
                      (item) =>
                          item.id != widget.service?.id &&
                          ServiceUpsertInput.normalizeName(item.name)
                                  .toLowerCase() ==
                              normalized.toLowerCase(),
                    );
                    return duplicate ? 'Tên dịch vụ đã tồn tại' : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Nhóm dịch vụ'),
                  items: ServiceUpsertInput.categories
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => category = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: duration,
                        decoration: const InputDecoration(
                          labelText: 'Thời lượng (phút)',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          return parsed == null || parsed <= 0
                              ? 'Nhập số phút hợp lệ'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: price,
                        decoration: const InputDecoration(labelText: 'Giá (đ)'),
                        validator: (value) {
                          final parsed = int.tryParse(value?.trim() ?? '');
                          return parsed == null || parsed <= 0
                              ? 'Nhập giá hợp lệ'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: popularity,
                  decoration: const InputDecoration(labelText: 'Độ phổ biến'),
                  items: ServiceUpsertInput.popularityLabels
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => popularity = value);
                  },
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: const Text('Đang áp dụng'),
                  onChanged: (value) => setState(() => active = value),
                ),
                TextFormField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  maxLines: 3,
                  validator: (value) =>
                      value == null || value.trim().isEmpty
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.service == null ? 'Tạo dịch vụ' : 'Lưu dịch vụ'),
        ),
      ],
    );
  }

  void _submit() {
    if (!formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ServiceUpsertInput.normalized(
        name: name.text.trim(),
        category: category,
        durationMinutes: int.parse(duration.text.trim()),
        price: int.parse(price.text.trim()),
        description: description.text,
        isActive: active,
        popularityLabel: popularity,
      ),
    );
  }
}
