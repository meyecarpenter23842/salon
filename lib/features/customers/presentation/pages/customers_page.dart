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
final customerInactiveDaysFilterProvider = StateProvider<int?>((ref) => null);
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
  final inactiveDays = ref.watch(customerInactiveDaysFilterProvider);
  final service = ref.watch(customerServiceFilterProvider);

  final customers = await ref.watch(customersRepositoryProvider).fetchCustomersView(
        query: query.isEmpty ? null : query,
        tier: tier,
        recentDays: recentDays,
        inactiveDays: inactiveDays,
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

  final saved = await ref
      .read(customersRepositoryProvider)
      .saveCustomer(input, existingId: customer?.id);
  if (!context.mounted) return;

  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
  ref.read(customersRefreshProvider.notifier).state++;
  ref.invalidate(filteredCustomersProvider);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        customer == null
            ? 'Đã thêm khách hàng ${saved.fullName}'
            : 'Đã cập nhật hồ sơ ${saved.fullName}',
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
    final totalState = ref.watch(customersViewProvider);
    final total = totalState.valueOrNull?.length ?? items.length;
    final repeat = items.where((item) => item.visitCount >= 5).length;
    final vip = items.where((item) => item.tier.contains('VIP')).length;

    return LayoutBuilder(
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 620;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PremiumSectionCard(
              key: const Key('customers-premium-header'),
              child: PremiumPageHeader(
                icon: Icons.groups_2_outlined,
                eyebrow: 'Quan hệ khách hàng',
                title: 'Khách hàng',
                subtitle:
                    'Hồ sơ, hạng thành viên, thói quen dịch vụ và lịch sử thanh toán trong một workspace thống nhất.',
                trailing: [
                  PremiumStatusPill(label: '$total hồ sơ', tone: AppColors.copper),
                  FilledButton.icon(
                    onPressed: () => _openCustomerEditor(context, ref),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Thêm khách'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CustomerStats(total: total, repeat: repeat, vip: vip, visible: items.length),
            const SizedBox(height: 14),
            const _CustomerToolbar(),
            const SizedBox(height: 14),
            if (shortViewport)
              SizedBox(
                height: 760,
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

        if (shortViewport) {
          return ListView(
            key: const Key('customers-premium-workspace'),
            primary: false,
            children: [content],
          );
        }
        return KeyedSubtree(
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
    required this.visible,
  });

  final int total;
  final int repeat;
  final int vip;
  final int visible;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(icon: Icons.groups_2_outlined, label: 'Tổng khách', value: '$total'),
      PremiumStatCard(
        icon: Icons.refresh_rounded,
        label: 'Khách quay lại',
        value: '$repeat',
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.workspace_premium_outlined,
        label: 'Khách VIP',
        value: '$vip',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.filter_alt_outlined,
        label: 'Đang hiển thị',
        value: '$visible',
        tone: AppColors.info,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
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

  static const tiers = [
    (label: 'Tất cả hạng', value: null),
    (label: 'VIP Gold', value: 'VIP Gold'),
    (label: 'VIP Silver', value: 'VIP Silver'),
    (label: 'Member', value: 'Member'),
  ];
  static const activityFilters = [
    (label: 'Tất cả khách', recentDays: null, inactiveDays: null),
    (label: 'Gần đây · 7 ngày', recentDays: 7, inactiveDays: null),
    (label: 'Gần đây · 30 ngày', recentDays: 30, inactiveDays: null),
    (label: 'Gần đây · 90 ngày', recentDays: 90, inactiveDays: null),
    (label: 'Không hoạt động · 30+ ngày', recentDays: null, inactiveDays: 30),
    (label: 'Không hoạt động · 90+ ngày', recentDays: null, inactiveDays: 90),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTier = ref.watch(customerTierFilterProvider);
    final currentRecentDays = ref.watch(customerRecentDaysFilterProvider);
    final currentInactiveDays = ref.watch(customerInactiveDaysFilterProvider);
    final currentService = ref.watch(customerServiceFilterProvider);
    final services = ref.watch(customerServiceOptionsProvider);

    return PremiumSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: ref.watch(customerSearchQueryProvider),
            onChanged: (value) {
              ref.read(customerSearchQueryProvider.notifier).state = value;
              ref.read(selectedCustomerIndexProvider.notifier).state = 0;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Tìm tên, số điện thoại, hạng thành viên hoặc dịch vụ yêu thích',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in tiers)
                FilterChip(
                  label: Text(option.label),
                  selected: currentTier == option.value,
                  showCheckmark: false,
                  onSelected: (_) {
                    ref.read(customerTierFilterProvider.notifier).state = option.value;
                    ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                  },
                ),
              for (final option in activityFilters)
                FilterChip(
                  label: Text(option.label),
                  selected: currentRecentDays == option.recentDays &&
                      currentInactiveDays == option.inactiveDays,
                  showCheckmark: false,
                  onSelected: (_) {
                    ref.read(customerRecentDaysFilterProvider.notifier).state =
                        option.recentDays;
                    ref.read(customerInactiveDaysFilterProvider.notifier).state =
                        option.inactiveDays;
                    ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          services.when(
            data: (items) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: DropdownButtonFormField<String?>(
                initialValue: currentService,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.content_cut_rounded),
                  labelText: 'Dịch vụ yêu thích',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả dịch vụ'),
                  ),
                  ...items.map(
                    (name) => DropdownMenuItem<String?>(value: name, child: Text(name)),
                  ),
                ],
                onChanged: (value) {
                  ref.read(customerServiceFilterProvider.notifier).state = value;
                  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                },
              ),
            ),
            loading: () => const SizedBox(
              height: 46,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
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
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(selected?.id ?? 'customer-empty'),
      child: _CustomerDetail(customer: selected),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // After the desktop sidebar is deducted, a 1024–1280 window does not
        // have enough room for a useful two-column CRM workspace. Stack early.
        if (constraints.maxWidth < 1040) {
          return ListView(
            primary: false,
            children: [
              SizedBox(
                height: 330,
                child: _CustomerList(items: items, selectedIndex: selectedIndex),
              ),
              const SizedBox(height: 12),
              SizedBox(height: 470, child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11,
              child: _CustomerList(items: items, selectedIndex: selectedIndex),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 9, child: detail),
          ],
        );
      },
    );
  }
}

class _CustomerList extends ConsumerWidget {
  const _CustomerList({required this.items, required this.selectedIndex});

  final List<CustomerProfile> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.people_alt_outlined,
      title: 'Danh sách khách hàng',
      subtitle: '${items.length} hồ sơ phù hợp bộ lọc',
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: items.isEmpty
          ? const PremiumEmptyState(
              icon: Icons.person_search_outlined,
              title: 'Không có khách phù hợp',
              message: 'Thử đổi từ khóa hoặc bộ lọc hiện tại.',
            )
          : ListView.separated(
              primary: false,
              itemCount: items.length,
              separatorBuilder: (_, _) => const PremiumDivider(indent: 56),
              itemBuilder: (context, index) {
                final customer = items[index];
                final isSelected = index == selectedIndex;
                final vip = customer.tier.contains('VIP');

                return PremiumInteractiveSurface(
                  selected: isSelected,
                  onTap: () {
                    ref.read(selectedCustomerIndexProvider.notifier).state = index;
                  },
                  child: Row(
                    children: [
                      PremiumIconBadge(
                        icon: vip
                            ? Icons.workspace_premium_outlined
                            : Icons.person_outline_rounded,
                        size: 38,
                        tone: vip ? AppColors.warning : AppColors.copper,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _TierBadge(tier: customer.tier),
                                Text(
                                  customer.phone,
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                                if (customer.favoriteService.isNotEmpty)
                                  Text(
                                    customer.favoriteService,
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              customer.spentLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${customer.visitCount} lượt',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _CustomerDetail extends ConsumerWidget {
  const _CustomerDetail({required this.customer});

  final CustomerProfile? customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = customer;
    if (current == null) {
      return const PremiumSectionCard(
        child: PremiumEmptyState(
          icon: Icons.person_pin_outlined,
          title: 'Chọn một khách hàng',
          message: 'Hồ sơ tóc và lịch sử thanh toán sẽ hiển thị ở đây.',
        ),
      );
    }

    final history = ref.watch(customerInvoiceHistoryProvider(current.id));
    final vip = current.tier.contains('VIP');

    return PremiumSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                PremiumIconBadge(
                  icon: vip
                      ? Icons.workspace_premium_outlined
                      : Icons.person_outline_rounded,
                  size: 48,
                  tone: vip ? AppColors.warning : AppColors.copper,
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
                        current.phone,
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      _TierBadge(tier: current.tier),
                    ],
                  ),
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
                  _CustomerMetricStrip(customer: current),
                  const SizedBox(height: 8),
                  PremiumInfoRow(
                    icon: Icons.content_cut_rounded,
                    label: 'Dịch vụ yêu thích',
                    value: current.favoriteService.isEmpty
                        ? 'Chưa ghi nhận'
                        : current.favoriteService,
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
                    value: current.hairProfile.isEmpty ? 'Chưa có hồ sơ tóc' : current.hairProfile,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Ghi chú salon',
                    value: current.note.isEmpty ? 'Chưa có ghi chú' : current.note,
                  ),
                  const SizedBox(height: 14),
                  _InvoiceHistory(history: history),
                ],
              ),
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final billing = FilledButton.icon(
                  onPressed: () => _openCustomerBilling(context, ref, current),
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: const Text('Mở tính tiền'),
                );
                final edit = OutlinedButton.icon(
                  onPressed: () => _openCustomerEditor(context, ref, customer: current),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Sửa hồ sơ'),
                );

                if (constraints.maxWidth < 360) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [billing, const SizedBox(height: 8), edit],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: billing),
                    const SizedBox(width: 8),
                    Expanded(child: edit),
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

class _CustomerMetricStrip extends StatelessWidget {
  const _CustomerMetricStrip({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Số lần ghé', '${customer.visitCount}'),
      ('Tổng chi', customer.spentLabel),
      ('Điểm', '${customer.loyaltyPoints}'),
    ];

    return Container(
      width: double.infinity,
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
              Container(width: 1, height: 32, color: AppColors.workspaceDivider),
          ],
        ],
      ),
    );
  }
}

class _InvoiceHistory extends StatelessWidget {
  const _InvoiceHistory({required this.history});

  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => PremiumInfoRow(
        icon: Icons.receipt_long_outlined,
        label: 'Lịch sử thanh toán',
        value: 'Không tải được: $error',
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const PremiumInfoRow(
            icon: Icons.receipt_long_outlined,
            label: 'Lịch sử thanh toán',
            value: 'Chưa có hóa đơn đã thanh toán',
          );
        }

        final visible = invoices.take(3).toList(growable: false);
        final totalPaid = invoices.fold<int>(0, (sum, invoice) => sum + invoice.totalAmount);
        return PremiumSectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'Lịch sử thanh toán',
          subtitle: '${invoices.length} hóa đơn • ${_currency(totalPaid)}',
          child: Column(
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                _InvoiceRow(invoice: visible[index]),
                if (index < visible.length - 1) const PremiumDivider(indent: 42),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});

  final InvoiceDraft invoice;

  @override
  Widget build(BuildContext context) {
    final paidAt = invoice.paidAt;
    return PremiumInfoRow(
      icon: Icons.payments_outlined,
      label: paidAt == null ? 'Chưa thanh toán' : _dateTime(paidAt),
      value: '${_currency(invoice.totalAmount)} • ${invoice.lines.length} dịch vụ • ${invoice.paymentMethod}',
    );
  }
}

class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final gold = tier.contains('Gold');
    final vip = tier.contains('VIP');
    final tone = gold
        ? AppColors.warning
        : vip
            ? AppColors.copper
            : AppColors.textMuted;
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: AppColors.isLight ? 0.09 : 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Text(
        tier,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _favoriteServiceController;
  late final TextEditingController _hairProfileController;
  late final TextEditingController _noteController;
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
    final editing = widget.customer != null;
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(editing ? 'Sửa hồ sơ khách hàng' : 'Thêm khách hàng'),
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
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập họ và tên khách hàng'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập số điện thoại'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
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
          child: Text(editing ? 'Lưu thay đổi' : 'Tạo hồ sơ'),
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
