import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/customer_upsert_input.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');
final customerTierFilterProvider = StateProvider<String?>((ref) => null);
final customerRecentDaysFilterProvider = StateProvider<int?>((ref) => null);
final customerServiceFilterProvider = StateProvider<String?>((ref) => null);
final selectedCustomerIndexProvider = StateProvider<int>((ref) => 0);

final customerServiceOptionsProvider = FutureProvider<List<String>>((ref) async {
  final services = await ref.watch(servicesRepositoryProvider).fetchServicesView();
  final names = services
      .map((service) => service.name.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return names;
});

final filteredCustomersProvider = FutureProvider<List<CustomerProfile>>((ref) async {
  ref.watch(customersRefreshProvider);
  final query = ref.watch(customerSearchQueryProvider);
  final tier = ref.watch(customerTierFilterProvider);
  final recentDays = ref.watch(customerRecentDaysFilterProvider);
  final service = ref.watch(customerServiceFilterProvider);
  final customers = await ref.watch(customersRepositoryProvider).fetchCustomersView(
        query: query.isEmpty ? null : query,
        tier: tier,
        recentDays: recentDays,
      );

  if (service == null || service.isEmpty) return customers;
  final expected = service.toLowerCase();
  return customers
      .where((customer) => customer.favoriteService.toLowerCase().contains(expected))
      .toList(growable: false);
});

Future<void> _openCustomerEditor(
  BuildContext context,
  WidgetRef ref, {
  CustomerProfile? customer,
}) async {
  final input = await showDialog<CustomerUpsertInput>(
    context: context,
    builder: (_) => _CustomerEditorDialog(customer: customer),
  );
  if (input == null || !context.mounted) return;

  final savedCustomer = await ref
      .read(customersRepositoryProvider)
      .saveCustomer(input, existingId: customer?.id);
  if (!context.mounted) return;

  ref.read(customerSearchQueryProvider.notifier).state = savedCustomer.fullName;
  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
  ref.read(customersRefreshProvider.notifier).state++;
  ref.invalidate(filteredCustomersProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        customer == null
            ? 'Đã thêm khách hàng ${savedCustomer.fullName}'
            : 'Đã cập nhật hồ sơ ${savedCustomer.fullName}',
      ),
    ),
  );
}

Future<void> _openCustomerBilling(
  BuildContext context,
  WidgetRef ref,
  CustomerProfile customer,
) async {
  await ref.read(invoicesRepositoryProvider).selectInvoiceCustomer(customer.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã mở tính tiền cho ${customer.fullName}')),
  );
}

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(filteredCustomersProvider);
    return customers.when(
      data: (items) => _CustomersView(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Không tải được khách hàng',
        message: '$error',
      ),
    );
  }
}

class _CustomersView extends ConsumerWidget {
  const _CustomersView({required this.items});

  final List<CustomerProfile> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedCustomerIndexProvider);
    final effectiveIndex = items.isEmpty ? 0 : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final allCustomers = ref.watch(customersViewProvider).valueOrNull ?? items;
    final repeatCount = allCustomers.where((item) => item.visitCount >= 5).length;
    final vipCount = allCustomers.where((item) => item.tier.contains('VIP')).length;
    final totalSpent = allCustomers.fold<int>(0, (sum, item) => sum + item.totalSpent);

    return LayoutBuilder(
      builder: (context, viewport) {
        final compactHeight = viewport.maxHeight < 620;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumSectionCard(
              key: const Key('customers-premium-header'),
              child: PremiumPageHeader(
                icon: Icons.people_alt_outlined,
                eyebrow: 'Quan hệ khách hàng',
                title: 'Khách hàng',
                subtitle: 'Hồ sơ, thói quen quay lại, hạng thành viên và lịch sử chi tiêu trong một không gian tư vấn gọn.',
                trailing: [
                  PremiumStatusPill(
                    label: '${allCustomers.length} hồ sơ',
                    tone: AppColors.copper,
                  ),
                  FilledButton.icon(
                    onPressed: () => _openCustomerEditor(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Thêm khách'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CustomerStats(
              total: allCustomers.length,
              repeat: repeatCount,
              vip: vipCount,
              totalSpent: totalSpent,
            ),
            const SizedBox(height: 14),
            const _CustomerToolbar(),
            const SizedBox(height: 14),
            if (compactHeight)
              SizedBox(
                height: 680,
                child: _CustomerWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              )
            else
              Expanded(
                child: _CustomerWorkspace(
                  items: items,
                  selectedIndex: effectiveIndex,
                  selected: selected,
                ),
              ),
          ],
        );

        return compactHeight
            ? ListView(
                key: const Key('customers-premium-workspace'),
                primary: false,
                children: [content],
              )
            : KeyedSubtree(
                key: const Key('customers-premium-workspace'),
                child: content,
              );
      },
    );
  }
}

class _CustomerStats extends StatelessWidget {
  const _CustomerStats({
    required this.total,
    required this.repeat,
    required this.vip,
    required this.totalSpent,
  });

  final int total;
  final int repeat;
  final int vip;
  final int totalSpent;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.groups_2_outlined,
        label: 'Tổng hồ sơ',
        value: '$total',
        note: 'Toàn bộ khách đang lưu',
      ),
      PremiumStatCard(
        icon: Icons.repeat_rounded,
        label: 'Khách quay lại',
        value: '$repeat',
        note: 'Từ 5 lượt ghé trở lên',
        tone: AppColors.info,
      ),
      PremiumStatCard(
        icon: Icons.workspace_premium_outlined,
        label: 'Khách VIP',
        value: '$vip',
        note: 'Silver và Gold',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.payments_outlined,
        label: 'Tổng chi đã ghi nhận',
        value: _currency(totalSpent),
        note: 'Theo hồ sơ hiện có',
        tone: AppColors.success,
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

class _CustomerToolbar extends ConsumerWidget {
  const _CustomerToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tier = ref.watch(customerTierFilterProvider);
    final recentDays = ref.watch(customerRecentDaysFilterProvider);
    final service = ref.watch(customerServiceFilterProvider);
    final services = ref.watch(customerServiceOptionsProvider);

    void resetSelection() {
      ref.read(selectedCustomerIndexProvider.notifier).state = 0;
    }

    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextFormField(
                initialValue: ref.watch(customerSearchQueryProvider),
                onChanged: (value) {
                  ref.read(customerSearchQueryProvider.notifier).state = value;
                  resetSelection();
                },
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Tìm tên, số điện thoại hoặc hạng thành viên',
                ),
              );
              final servicePicker = services.when(
                data: (values) => DropdownButtonFormField<String?>(
                  initialValue: service,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.content_cut_rounded),
                    labelText: 'Dịch vụ yêu thích',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tất cả dịch vụ')),
                    ...values.map(
                      (value) => DropdownMenuItem<String?>(value: value, child: Text(value)),
                    ),
                  ],
                  onChanged: (value) {
                    ref.read(customerServiceFilterProvider.notifier).state = value;
                    resetSelection();
                  },
                ),
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, _) => const SizedBox.shrink(),
              );

              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    search,
                    const SizedBox(height: 10),
                    servicePicker,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 5, child: search),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: servicePicker),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  (label: 'Tất cả', value: null),
                  (label: 'VIP Gold', value: 'VIP Gold'),
                  (label: 'VIP Silver', value: 'VIP Silver'),
                  (label: 'Member', value: 'Member'),
                ])
                  FilterChip(
                    label: Text(option.label),
                    selected: tier == option.value,
                    showCheckmark: false,
                    onSelected: (_) {
                      ref.read(customerTierFilterProvider.notifier).state = option.value;
                      resetSelection();
                    },
                  ),
                for (final option in const [
                  (label: 'Mọi thời gian', value: null),
                  (label: '7 ngày', value: 7),
                  (label: '30 ngày', value: 30),
                  (label: '90 ngày', value: 90),
                ])
                  FilterChip(
                    label: Text(option.label),
                    selected: recentDays == option.value,
                    showCheckmark: false,
                    onSelected: (_) {
                      ref.read(customerRecentDaysFilterProvider.notifier).state = option.value;
                      resetSelection();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerWorkspace extends StatelessWidget {
  const _CustomerWorkspace({
    required this.items,
    required this.selectedIndex,
    required this.selected,
  });

  final List<CustomerProfile> items;
  final int selectedIndex;
  final CustomerProfile? selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return ListView(
            primary: false,
            children: [
              SizedBox(
                height: 300,
                child: _CustomerListPanel(items: items, selectedIndex: selectedIndex),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 390, child: _CustomerDetailPanel(customer: selected)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11,
              child: _CustomerListPanel(items: items, selectedIndex: selectedIndex),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 9, child: _CustomerDetailPanel(customer: selected)),
          ],
        );
      },
    );
  }
}

class _CustomerListPanel extends ConsumerWidget {
  const _CustomerListPanel({required this.items, required this.selectedIndex});

  final List<CustomerProfile> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.person_search_outlined,
      title: 'Danh sách khách',
      subtitle: '${items.length} hồ sơ phù hợp bộ lọc',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.person_off_outlined,
              title: 'Không có khách phù hợp',
              message: 'Thử đổi bộ lọc hoặc tạo hồ sơ khách mới.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 56),
              itemBuilder: (context, index) {
                final customer = items[index];
                final selected = index == selectedIndex;
                return Material(
                  color: selected ? AppColors.selectedSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ref.read(selectedCustomerIndexProvider.notifier).state = index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      child: Row(
                        children: [
                          PremiumIconBadge(
                            icon: customer.tier.contains('VIP')
                                ? Icons.workspace_premium_outlined
                                : Icons.person_outline_rounded,
                            size: 38,
                            tone: customer.tier.contains('VIP') ? AppColors.warning : AppColors.copper,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        customer.fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _TierBadge(tier: customer.tier),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${customer.phone} • ${customer.favoriteService.isEmpty ? 'Chưa ghi dịch vụ thích' : customer.favoriteService}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(customer.spentLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text('${customer.visitCount} lượt', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _CustomerDetailPanel extends ConsumerWidget {
  const _CustomerDetailPanel({required this.customer});

  final CustomerProfile? customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = customer;
    if (current == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.person_search_outlined,
          title: 'Chọn một khách hàng',
          message: 'Thông tin tư vấn và lịch sử thanh toán sẽ hiện ở đây.',
        ),
      );
    }

    final history = ref.watch(customerInvoiceHistoryProvider(current.id));
    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.person_rounded,
                  size: 46,
                  tone: current.tier.contains('VIP') ? AppColors.warning : AppColors.copper,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${current.phone}${current.email == null ? '' : ' • ${current.email}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                _TierBadge(tier: current.tier, prominent: true),
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
                  _CustomerMetricStrip(customer: current),
                  const SizedBox(height: 8),
                  PremiumInfoRow(
                    icon: Icons.content_cut_rounded,
                    label: 'Dịch vụ yêu thích',
                    value: current.favoriteService.isEmpty ? 'Chưa ghi nhận' : current.favoriteService,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.history_rounded,
                    label: 'Lần ghé gần nhất',
                    value: current.lastVisitLabel,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Hồ sơ tóc',
                    value: current.hairProfile.isEmpty ? 'Chưa có ghi chú hồ sơ tóc' : current.hairProfile,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Ghi chú salon',
                    value: current.note.isEmpty ? 'Chưa có ghi chú' : current.note,
                  ),
                  const SizedBox(height: 14),
                  _CustomerInvoiceHistorySection(history: history),
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
                    onPressed: () => _openCustomerBilling(context, ref, current),
                    icon: const Icon(Icons.point_of_sale_outlined),
                    label: const Text('Mở tính tiền'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openCustomerEditor(context, ref, customer: current),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa hồ sơ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerMetricStrip extends StatelessWidget {
  const _CustomerMetricStrip({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Số lần ghé', '${customer.visitCount}'),
      ('Tổng chi', customer.spentLabel),
      ('Điểm tích lũy', '${customer.loyaltyPoints}'),
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
                  Text(metrics[index].$1, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 5),
                  Text(metrics[index].$2, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (index < metrics.length - 1)
              Container(width: 1, height: 32, color: AppColors.workspaceDivider),
          ],
        ],
      ),
    );
  }
}

class _CustomerInvoiceHistorySection extends StatelessWidget {
  const _CustomerInvoiceHistorySection({required this.history});

  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text('Không tải được lịch sử hóa đơn: $error'),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Chưa có hóa đơn đã chốt',
            message: 'Lịch sử thanh toán sẽ xuất hiện sau lần tính tiền đầu tiên.',
          );
        }
        final totalPaid = invoices.fold<int>(0, (sum, invoice) => sum + invoice.totalAmount);
        final recent = invoices.take(3).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PremiumIconBadge(icon: Icons.receipt_long_outlined, size: 34),
                const SizedBox(width: 9),
                const Expanded(child: Text('Lịch sử thanh toán', style: TextStyle(fontWeight: FontWeight.w800))),
                Text('${invoices.length} hóa đơn • ${_currency(totalPaid)}', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < recent.length; index++) ...[
              _CustomerInvoiceTile(invoice: recent[index]),
              if (index < recent.length - 1) const PremiumDivider(indent: 42),
            ],
          ],
        );
      },
    );
  }
}

class _CustomerInvoiceTile extends StatelessWidget {
  const _CustomerInvoiceTile({required this.invoice});

  final InvoiceDraft invoice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          PremiumIconBadge(icon: Icons.payments_outlined, size: 32, tone: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_currency(invoice.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '${invoice.lines.length} dịch vụ • ${invoice.paymentMethod}${invoice.paidAt == null ? '' : ' • ${_dateTime(invoice.paidAt!)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier, this.prominent = false});

  final String tier;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final tone = tier.contains('Gold')
        ? AppColors.warning
        : tier.contains('VIP')
            ? AppColors.copper
            : AppColors.textMuted;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: prominent ? 10 : 8, vertical: prominent ? 6 : 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: AppColors.isLight ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tier,
        style: TextStyle(color: tone, fontWeight: FontWeight.w800, fontSize: prominent ? 11 : 10),
      ),
    );
  }
}

class _CustomerEditorDialog extends StatefulWidget {
  const _CustomerEditorDialog({this.customer});

  final CustomerProfile? customer;

  @override
  State<_CustomerEditorDialog> createState() => _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends State<_CustomerEditorDialog> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _favoriteServiceController;
  late final TextEditingController _hairProfileController;
  late final TextEditingController _noteController;
  final _formKey = GlobalKey<FormState>();
  late String _tier;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _fullNameController = TextEditingController(text: customer?.fullName ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _emailController = TextEditingController(text: customer?.email ?? '');
    _favoriteServiceController = TextEditingController(text: customer?.favoriteService ?? '');
    _hairProfileController = TextEditingController(text: customer?.hairProfile ?? '');
    _noteController = TextEditingController(text: customer?.note ?? '');
    _tier = customer?.tier ?? 'Member';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _favoriteServiceController.dispose();
    _hairProfileController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;
    return AlertDialog(
      title: Text(isEditing ? 'Sửa hồ sơ khách hàng' : 'Thêm khách hàng'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 520),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Nhập họ và tên khách hàng' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Nhập số điện thoại' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _tier,
                  decoration: const InputDecoration(labelText: 'Hạng thành viên'),
                  items: const ['Member', 'VIP Silver', 'VIP Gold']
                      .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _tier = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _favoriteServiceController,
                  decoration: const InputDecoration(labelText: 'Dịch vụ yêu thích'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hairProfileController,
                  decoration: const InputDecoration(labelText: 'Hồ sơ tóc'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'Ghi chú salon'),
                  maxLines: 3,
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
          child: Text(isEditing ? 'Lưu thay đổi' : 'Tạo hồ sơ'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    Navigator.of(context).pop(
      CustomerUpsertInput(
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        tier: _tier,
        favoriteService: _favoriteServiceController.text.trim(),
        hairProfile: _hairProfileController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }
}

final NumberFormat _currencyFormatter = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: 'đ',
  decimalDigits: 0,
);
final DateFormat _dateTimeFormatter = DateFormat('dd/MM HH:mm');
String _currency(int value) => _currencyFormatter.format(value).replaceAll(',', '.');
String _dateTime(DateTime value) => _dateTimeFormatter.format(value);
