import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/customer_upsert_input.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

final customerTierFilterProvider = StateProvider<String?>((ref) => null);

final customerRecentDaysFilterProvider = StateProvider<int?>((ref) => null);

final customerServiceFilterProvider = StateProvider<String?>((ref) => null);

final customerServiceOptionsProvider = FutureProvider<List<String>>((
  ref,
) async {
  final services = await ref
      .watch(servicesRepositoryProvider)
      .fetchServicesView();
  final names =
      services
          .map((service) => service.name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return names;
});

final selectedCustomerIndexProvider = StateProvider<int>((ref) => 0);

final filteredCustomersProvider = FutureProvider<List<CustomerProfile>>((
  ref,
) async {
  ref.watch(customersRefreshProvider);
  final query = ref.watch(customerSearchQueryProvider);
  final tier = ref.watch(customerTierFilterProvider);
  final recentDays = ref.watch(customerRecentDaysFilterProvider);
  final service = ref.watch(customerServiceFilterProvider);
  final customers = await ref
      .watch(customersRepositoryProvider)
      .fetchCustomersView(
        query: query.isEmpty ? null : query,
        tier: tier,
        recentDays: recentDays,
      );

  if (service == null || service.isEmpty) {
    return customers;
  }

  final expected = service.toLowerCase();
  return customers
      .where(
        (customer) => customer.favoriteService.toLowerCase().contains(expected),
      )
      .toList(growable: false);
});

Future<void> _openCustomerEditor(
  BuildContext context,
  WidgetRef ref, {
  CustomerProfile? customer,
}) async {
  final input = await showDialog<CustomerUpsertInput>(
    context: context,
    builder: (dialogContext) => _CustomerEditorDialog(customer: customer),
  );

  if (input == null || !context.mounted) {
    return;
  }

  final savedCustomer = await ref
      .read(customersRepositoryProvider)
      .saveCustomer(input, existingId: customer?.id);

  if (!context.mounted) {
    return;
  }

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

  if (!context.mounted) {
    return;
  }

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
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được khách hàng: $error')),
    );
  }
}

class _CustomersView extends ConsumerWidget {
  const _CustomersView({required this.items});

  final List<CustomerProfile> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedCustomerIndexProvider);
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selectedCustomer = items.isEmpty ? null : items[effectiveIndex];
    final query = ref.watch(customerSearchQueryProvider);

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
                      child: _CustomerListPanel(
                        items: items,
                        selectedIndex: effectiveIndex,
                      ),
                    ),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(
                      flex: 4,
                      child: _CustomerDetailPanel(
                        customer: selectedCustomer,
                        onEdit: selectedCustomer == null
                            ? null
                            : () => _openCustomerEditor(
                                context,
                                ref,
                                customer: selectedCustomer,
                              ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _CustomerListPanel(
                      items: items,
                      selectedIndex: effectiveIndex,
                    ),
                  ),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(
                    flex: 4,
                    child: _CustomerDetailPanel(
                      customer: selectedCustomer,
                      onEdit: selectedCustomer == null
                          ? null
                          : () => _openCustomerEditor(
                              context,
                              ref,
                              customer: selectedCustomer,
                            ),
                    ),
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
              const _CustomersHero(),
              const SizedBox(height: AppDimens.heroGap),
              _CustomerSummaryRow(items: items),
              const SizedBox(height: AppDimens.sectionGap),
              _CustomerSearchBar(
                query: query,
                onChanged: (value) {
                  ref.read(customerSearchQueryProvider.notifier).state = value;
                  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                },
                onCreate: () => _openCustomerEditor(context, ref),
              ),
              const SizedBox(height: 10),
              const _CustomerFilterBar(),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 680, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CustomersHero(),
            const SizedBox(height: AppDimens.heroGap),
            _CustomerSummaryRow(items: items),
            const SizedBox(height: AppDimens.sectionGap),
            _CustomerSearchBar(
              query: query,
              onChanged: (value) {
                ref.read(customerSearchQueryProvider.notifier).state = value;
                ref.read(selectedCustomerIndexProvider.notifier).state = 0;
              },
              onCreate: () => _openCustomerEditor(context, ref),
            ),
            const SizedBox(height: 10),
            const _CustomerFilterBar(),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _CustomerFilterBar extends ConsumerWidget {
  const _CustomerFilterBar();

  static const List<({String label, String? tier})> _tierOptions = [
    (label: 'Tất cả', tier: null),
    (label: 'VIP Gold', tier: 'VIP Gold'),
    (label: 'VIP Silver', tier: 'VIP Silver'),
    (label: 'Member', tier: 'Member'),
  ];

  static const List<({String label, int? days})> _dayOptions = [
    (label: 'Mọi thời gian', days: null),
    (label: '7 ngày', days: 7),
    (label: '30 ngày', days: 30),
    (label: '90 ngày', days: 90),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTier = ref.watch(customerTierFilterProvider);
    final currentDays = ref.watch(customerRecentDaysFilterProvider);
    final selectedService = ref.watch(customerServiceFilterProvider);
    final serviceOptionsState = ref.watch(customerServiceOptionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in _tierOptions)
              FilterChip(
                label: Text(opt.label),
                selected: currentTier == opt.tier,
                onSelected: (_) {
                  ref.read(customerTierFilterProvider.notifier).state =
                      opt.tier;
                  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                },
              ),
            const SizedBox(width: 8),
            for (final opt in _dayOptions)
              FilterChip(
                label: Text(opt.label),
                selected: currentDays == opt.days,
                onSelected: (_) {
                  ref.read(customerRecentDaysFilterProvider.notifier).state =
                      opt.days;
                  ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        serviceOptionsState.when(
          data: (services) {
            final options = [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Tất cả dịch vụ'),
              ),
              ...services.map(
                (name) =>
                    DropdownMenuItem<String>(value: name, child: Text(name)),
              ),
            ];
            return LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                width: constraints.maxWidth < 320 ? constraints.maxWidth : 320,
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedService,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Lọc theo dịch vụ yêu thích',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: options,
                  onChanged: (value) {
                    ref.read(customerServiceFilterProvider.notifier).state =
                        value;
                    ref.read(selectedCustomerIndexProvider.notifier).state = 0;
                  },
                ),
              ),
            );
          },
          loading: () => const SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _CustomersHero extends StatelessWidget {
  const _CustomersHero();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.luxuryShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.selectedSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Customer Relationship',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.copperSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Hồ sơ khách hàng', style: textTheme.displayLarge),
          const SizedBox(height: 10),
          Text(
            'Theo dõi hồ sơ VIP, hành vi quay lại, lịch sử thanh toán và hồ sơ tóc trong một layout desktop gọn, đậm thông tin và đủ sang để dùng tư vấn trực tiếp.',
            style: textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSummaryRow extends ConsumerWidget {
  const _CustomerSummaryRow({required this.items});

  final List<CustomerProfile> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCustomersState = ref.watch(customersViewProvider);
    final totalCustomers =
        allCustomersState.valueOrNull?.length ?? items.length;
    final repeatCustomers = items.where((item) => item.visitCount >= 5).length;
    final vipCustomers = items
        .where((item) => item.tier.contains('VIP'))
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _CustomerSummaryCard(
            label: 'Tổng danh sách',
            value: '$totalCustomers',
            icon: Icons.groups_2_outlined,
          ),
          _CustomerSummaryCard(
            label: 'Khách quay lại',
            value: '$repeatCustomers',
            icon: Icons.refresh_outlined,
          ),
          _CustomerSummaryCard(
            label: 'Khách VIP',
            value: '$vipCustomers',
            icon: Icons.workspace_premium_outlined,
          ),
          _CustomerSummaryCard(
            label: 'Hồ sơ nổi bật',
            value: items.isEmpty ? 'Không có dữ liệu' : items.first.fullName,
            icon: Icons.person_pin_outlined,
          ),
        ];

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

class _CustomerSummaryCard extends StatelessWidget {
  const _CustomerSummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              height: 38,
              width: 38,
              decoration: BoxDecoration(
                color: AppColors.selectedSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: AppColors.copperSoft),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: textTheme.titleLarge?.copyWith(fontSize: 24),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchBar extends StatelessWidget {
  const _CustomerSearchBar({
    required this.query,
    required this.onChanged,
    required this.onCreate,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.luxuryShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: query,
              onChanged: onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText:
                    'Tìm theo tên, số điện thoại, hạng thành viên hoặc dịch vụ yêu thích',
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Thêm khách'),
          ),
        ],
      ),
    );
  }
}

class _CustomerListPanel extends ConsumerWidget {
  const _CustomerListPanel({required this.items, required this.selectedIndex});

  final List<CustomerProfile> items;
  final int selectedIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Danh sách khách hàng',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${items.length} hồ sơ',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Không có khách hàng phù hợp với điều kiện tìm kiếm.',
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemCount: items.length,
                  itemBuilder: (context, index) => _CustomerListTile(
                    customer: items[index],
                    selected: index == selectedIndex,
                    onTap: () {
                      ref.read(selectedCustomerIndexProvider.notifier).state =
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

class _CustomerListTile extends StatelessWidget {
  const _CustomerListTile({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final CustomerProfile customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.selectedSurface : AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.borderStrong : AppColors.border,
        ),
        boxShadow: selected ? AppColors.luxuryShadow : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.shellAccentSurface
                        : AppColors.avatarFill,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.borderStrong
                          : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customer.initials,
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 180;
                          final name = Text(
                            customer.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          );

                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                name,
                                const SizedBox(height: 4),
                                _TierBadge(tier: customer.tier),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: name),
                              const SizedBox(width: 8),
                              _TierBadge(tier: customer.tier),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer.phone,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer.lastVisitLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        customer.spentLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${customer.visitCount} lượt',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerDetailPanel extends ConsumerWidget {
  const _CustomerDetailPanel({required this.customer, required this.onEdit});

  final CustomerProfile? customer;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customer == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Chọn một khách hàng để xem chi tiết.'),
        ),
      );
    }

    final invoiceHistory = ref.watch(
      customerInvoiceHistoryProvider(customer!.id),
    );

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
                        Container(
                          height: 78,
                          width: 78,
                          decoration: BoxDecoration(
                            color: AppColors.shellAccentSurface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.borderStrong,
                              width: 1.4,
                            ),
                            boxShadow: AppColors.luxuryShadow,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            customer!.initials,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer!.fullName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                customer!.phone,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _TierBadge(tier: customer!.tier, prominent: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.panelAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chỉ số nhanh',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _DetailStatCard(
                                  label: 'Số lần ghé',
                                  value: '${customer!.visitCount}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DetailStatCard(
                                  label: 'Tổng chi',
                                  value: customer!.spentLabel,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DetailStatCard(
                                  label: 'Điểm tích lũy',
                                  value: '${customer!.loyaltyPoints}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _DetailSection(
                      title: 'Dịch vụ yêu thích',
                      content: customer!.favoriteService,
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      title: 'Lần ghé gần nhất',
                      content: customer!.lastVisitLabel,
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      title: 'Hồ sơ tóc',
                      content: customer!.hairProfile,
                    ),
                    const SizedBox(height: 14),
                    _DetailSection(
                      title: 'Ghi chú salon',
                      content: customer!.note,
                    ),
                    const SizedBox(height: 14),
                    _CustomerInvoiceHistorySection(history: invoiceHistory),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        _openCustomerBilling(context, ref, customer!),
                    child: const Text('Mở tính tiền'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Sửa hồ sơ'),
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

class _CustomerInvoiceHistorySection extends StatelessWidget {
  const _CustomerInvoiceHistorySection({required this.history});

  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.panelAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _DetailSection(
        title: 'Lịch sử thanh toán',
        content: 'Không tải được lịch sử hóa đơn: $error',
      ),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const _DetailSection(
            title: 'Lịch sử thanh toán',
            content: 'Khách hàng này chưa có hóa đơn đã thanh toán.',
          );
        }

        final totalPaid = invoices.fold<int>(
          0,
          (sum, invoice) => sum + invoice.totalAmount,
        );
        final latestPaidAt = invoices.first.paidAt;
        final visibleInvoices = invoices.take(3).toList(growable: false);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lịch sử thanh toán',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DetailStatCard(
                      label: 'Hóa đơn đã chốt',
                      value: '${invoices.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DetailStatCard(
                      label: 'Doanh thu đã chốt',
                      value: _currency(totalPaid),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DetailStatCard(
                      label: 'Thanh toán gần nhất',
                      value: latestPaidAt == null
                          ? 'Chưa có'
                          : _dateTime(latestPaidAt),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...visibleInvoices.map(
                (invoice) => _CustomerInvoiceTile(invoice: invoice),
              ),
            ],
          ),
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
    final paidAt = invoice.paidAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thanh toán ${_currency(invoice.totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  paidAt == null
                      ? 'Chưa thanh toán'
                      : 'Đã chốt lúc ${_dateTime(paidAt)}',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${invoice.lines.length} dịch vụ • ${invoice.paymentMethod}',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                if (invoice.appointmentId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Nguồn từ lịch hẹn ${invoice.appointmentId}',
                    style: TextStyle(
                      color: AppColors.copperSoft,
                      fontWeight: FontWeight.w700,
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

class _DetailStatCard extends StatelessWidget {
  const _DetailStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(height: 1.55, fontWeight: FontWeight.w500),
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
    final isVipGold = tier.contains('Gold');
    final isVip = tier.contains('VIP');
    final background = isVipGold
        ? AppColors.selectedSurface
        : isVip
        ? AppColors.panelAlt
        : AppColors.panelRaised;
    final foreground = isVipGold
        ? AppColors.copperSoft
        : isVip
        ? AppColors.textSecondary
        : AppColors.textMuted;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: prominent ? 12 : 8,
        vertical: prominent ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isVip
              ? AppColors.borderStrong.withValues(alpha: 0.45)
              : AppColors.border,
        ),
      ),
      child: Text(
        tier,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: prominent ? 12 : 10,
          height: 1.0,
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
    _favoriteServiceController = TextEditingController(
      text: customer?.favoriteService ?? '',
    );
    _hairProfileController = TextEditingController(
      text: customer?.hairProfile ?? '',
    );
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
      backgroundColor: AppColors.panel,
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
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Nhập họ và tên khách hàng'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  validator: (value) => (value == null || value.trim().isEmpty)
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
                  decoration: const InputDecoration(
                    labelText: 'Hạng thành viên',
                  ),
                  items: const ['Member', 'VIP Silver', 'VIP Gold']
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
                      _tier = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _favoriteServiceController,
                  decoration: const InputDecoration(
                    labelText: 'Dịch vụ yêu thích',
                  ),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

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

String _currency(int value) =>
    _currencyFormatter.format(value).replaceAll(',', '.');

String _dateTime(DateTime value) => _dateTimeFormatter.format(value);
