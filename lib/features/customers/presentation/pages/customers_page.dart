import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_upsert_input.dart';
import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/customer_upsert_input.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/compact_management.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final customerSearchQueryProvider = StateProvider<String>((ref) => '');
final customerTierFilterProvider = StateProvider<String?>((ref) => null);
final customerRecentDaysFilterProvider = StateProvider<int?>((ref) => null);
final customerInactiveDaysFilterProvider = StateProvider<int?>((ref) => null);
final customerServiceFilterProvider = StateProvider<String?>((ref) => null);
final selectedCustomerIndexProvider = StateProvider<int>((ref) => 0);
final customerProfileDetailIdProvider = StateProvider<String?>((ref) => null);
final customerProfileTabProvider = StateProvider<int>((ref) => 0);

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

final filteredCustomersProvider = FutureProvider<List<CustomerProfile>>((
  ref,
) async {
  ref.watch(customersRefreshProvider);
  final query = ref.watch(customerSearchQueryProvider);
  final tier = ref.watch(customerTierFilterProvider);
  final recentDays = ref.watch(customerRecentDaysFilterProvider);
  final inactiveDays = ref.watch(customerInactiveDaysFilterProvider);
  final service = ref.watch(customerServiceFilterProvider);

  final customers = await ref
      .watch(customersRepositoryProvider)
      .fetchCustomersView(
        query: query.isEmpty ? null : query,
        tier: tier,
        recentDays: recentDays,
        inactiveDays: inactiveDays,
      );

  if (service == null || service.isEmpty) return customers;
  final expected = service.toLowerCase();
  return customers
      .where(
        (customer) => customer.favoriteService.toLowerCase().contains(expected),
      )
      .toList(growable: false);
});

Future<CustomerProfile?> _openCustomerEditor(
  BuildContext context,
  WidgetRef ref, {
  CustomerProfile? customer,
}) async {
  final input = await showDialog<CustomerUpsertInput>(
    context: context,
    builder: (_) => _CustomerEditorDialog(customer: customer),
  );
  if (input == null || !context.mounted) return null;

  try {
    final saved = await ref
        .read(customersRepositoryProvider)
        .saveCustomer(input, existingId: customer?.id);
    if (!context.mounted) return null;

    ref.read(selectedCustomerIndexProvider.notifier).state = 0;
    ref.read(customersRefreshProvider.notifier).state++;
    ref.invalidate(filteredCustomersProvider);
    ref.invalidate(customersViewProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          customer == null
              ? 'Đã thêm khách hàng ${saved.fullName}'
              : 'Đã cập nhật hồ sơ ${saved.fullName}',
        ),
      ),
    );
    return saved;
  } catch (error) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    return null;
  }
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

Future<void> _openCustomerAppointment(
  BuildContext context,
  WidgetRef ref,
  CustomerProfile customer,
) async {
  final services = await ref
      .read(servicesRepositoryProvider)
      .fetchServicesView();
  final employees = await ref
      .read(employeesRepositoryProvider)
      .fetchEmployeesView();
  if (!context.mounted) return;

  final availableServices = services
      .where((service) => service.isActive)
      .toList(growable: false);
  if (availableServices.isEmpty || employees.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cần có ít nhất một dịch vụ và một nhân viên trước khi tạo lịch.',
        ),
      ),
    );
    return;
  }

  final input = await showDialog<AppointmentUpsertInput>(
    context: context,
    builder: (_) => _CustomerAppointmentDialog(
      customer: customer,
      services: availableServices,
      employees: employees,
    ),
  );
  if (input == null || !context.mounted) return;

  try {
    final saved = await ref
        .read(appointmentsRepositoryProvider)
        .saveAppointment(input);
    if (!context.mounted) return;

    ref.invalidate(appointmentsViewProvider);
    ref.invalidate(overviewSummaryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã tạo lịch ${saved.timeLabel} cho ${customer.fullName}',
        ),
        action: SnackBarAction(
          label: 'Xem lịch',
          onPressed: () {
            ref.read(desktopSectionProvider.notifier).state =
                DesktopSection.appointments;
          },
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
  }
}

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailId = ref.watch(customerProfileDetailIdProvider);
    if (detailId != null) {
      final customers = ref.watch(customersViewProvider);
      return customers.when(
        data: (items) {
          final customer = _findCustomer(items, detailId);
          if (customer == null) {
            return _MissingCustomerProfile(
              onBack: () =>
                  ref.read(customerProfileDetailIdProvider.notifier).state =
                      null,
            );
          }
          return _CustomerFullProfile(customer: customer);
        },
        loading: () =>
            const PremiumLoadingState(label: 'Đang mở hồ sơ khách hàng…'),
        error: (error, _) => PremiumErrorState(
          title: 'Không mở được hồ sơ khách hàng',
          message: '$error',
          onRetry: () => ref.invalidate(customersViewProvider),
        ),
      );
    }

    final customers = ref.watch(filteredCustomersProvider);
    return customers.when(
      data: (items) => _CustomersView(items: items),
      loading: () => const PremiumLoadingState(label: 'Đang tải khách hàng…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được khách hàng',
        message: '$error',
        onRetry: () => ref.invalidate(filteredCustomersProvider),
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
    final effectiveIndex = items.isEmpty
        ? 0
        : selectedIndex.clamp(0, items.length - 1);
    final selected = items.isEmpty ? null : items[effectiveIndex];
    final totalState = ref.watch(customersViewProvider);
    final total = totalState.valueOrNull?.length ?? items.length;
    final repeat = items.where((item) => item.visitCount >= 5).length;
    final vip = items.where((item) => item.tier.contains('VIP')).length;

    return KeyedSubtree(
      key: const Key('customers-premium-workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompactManagementHeader(
            key: const Key('customers-premium-header'),
            title: 'Khách hàng',
            subtitle:
                'Tìm khách, xem hồ sơ và tiếp tục đặt lịch hoặc tính tiền.',
            actionLabel: 'Thêm khách',
            actionIcon: Icons.person_add_alt_1_outlined,
            onAction: () => _openCustomerEditor(context, ref),
          ),
          const SizedBox(height: 12),
          _CustomerToolbar(
            total: total,
            repeat: repeat,
            vip: vip,
            visible: items.length,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _CustomerWorkspace(
              items: items,
              selectedIndex: effectiveIndex,
              selected: selected,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerToolbar extends ConsumerWidget {
  const _CustomerToolbar({
    required this.total,
    required this.repeat,
    required this.vip,
    required this.visible,
  });

  final int total;
  final int repeat;
  final int vip;
  final int visible;

  static const tiers = [
    (label: 'Tất cả hạng', value: null),
    (label: 'VIP Gold', value: 'VIP Gold'),
    (label: 'VIP Silver', value: 'VIP Silver'),
    (label: 'Member', value: 'Member'),
  ];

  static const activityFilters = [
    (label: 'Tất cả', recentDays: null, inactiveDays: null),
    (label: '7 ngày', recentDays: 7, inactiveDays: null),
    (label: '30 ngày', recentDays: 30, inactiveDays: null),
    (label: '90 ngày', recentDays: 90, inactiveDays: null),
    (label: 'Ngưng 30+', recentDays: null, inactiveDays: 30),
    (label: 'Ngưng 90+', recentDays: null, inactiveDays: 90),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTier = ref.watch(customerTierFilterProvider);
    final currentRecentDays = ref.watch(customerRecentDaysFilterProvider);
    final currentInactiveDays = ref.watch(customerInactiveDaysFilterProvider);
    final currentService = ref.watch(customerServiceFilterProvider);
    final services = ref.watch(customerServiceOptionsProvider);

    final search = TextFormField(
      initialValue: ref.watch(customerSearchQueryProvider),
      onChanged: (value) {
        ref.read(customerSearchQueryProvider.notifier).state = value;
        ref.read(selectedCustomerIndexProvider.notifier).state = 0;
      },
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded),
        hintText: 'Tìm tên, số điện thoại, hạng hoặc dịch vụ',
      ),
    );

    final tierPicker = DropdownButtonFormField<String?>(
      initialValue: currentTier,
      isExpanded: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.workspace_premium_outlined),
        labelText: 'Hạng',
      ),
      items: tiers
          .map(
            (option) => DropdownMenuItem<String?>(
              value: option.value,
              child: Text(option.label),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        ref.read(customerTierFilterProvider.notifier).state = value;
        ref.read(selectedCustomerIndexProvider.notifier).state = 0;
      },
    );

    final servicePicker = services.when(
      data: (items) => DropdownButtonFormField<String?>(
        initialValue: currentService,
        isExpanded: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.content_cut_rounded),
          labelText: 'Dịch vụ',
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
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = constraints.maxWidth >= 980
            ? Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: 180, child: tierPicker),
                  const SizedBox(width: 8),
                  SizedBox(width: 230, child: servicePicker),
                ],
              )
            : Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: tierPicker),
                      const SizedBox(width: 8),
                      Expanded(child: servicePicker),
                    ],
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            controls,
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CompactManagementSummary(
                  items: [
                    '$total khách',
                    '$repeat quay lại',
                    '$vip VIP',
                    '$visible hiển thị',
                  ],
                ),
                for (final option in activityFilters)
                  FilterChip(
                    label: Text(option.label),
                    selected:
                        currentRecentDays == option.recentDays &&
                        currentInactiveDays == option.inactiveDays,
                    showCheckmark: false,
                    onSelected: (_) {
                      ref
                              .read(customerRecentDaysFilterProvider.notifier)
                              .state =
                          option.recentDays;
                      ref
                              .read(customerInactiveDaysFilterProvider.notifier)
                              .state =
                          option.inactiveDays;
                      ref.read(selectedCustomerIndexProvider.notifier).state =
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
    final list = _CustomerList(items: items, selectedIndex: selectedIndex);
    final detail = PremiumAnimatedDetail(
      transitionKey: ValueKey(selected?.id ?? 'customer-empty'),
      child: _CustomerDetail(customer: selected),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1040) {
          return ListView(
            primary: false,
            children: [
              SizedBox(height: 320, child: list),
              const SizedBox(height: 10),
              SizedBox(height: 500, child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: constraints.maxWidth * 0.34, child: list),
            const SizedBox(width: 10),
            Expanded(child: detail),
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
                    ref.read(selectedCustomerIndexProvider.notifier).state =
                        index;
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
                    value: current.hairProfile.isEmpty
                        ? 'Chưa có hồ sơ tóc'
                        : current.hairProfile,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Ghi chú salon',
                    value: current.note.isEmpty
                        ? 'Chưa có ghi chú'
                        : current.note,
                  ),
                  const SizedBox(height: 14),
                  _InvoiceHistory(history: history, limit: 3),
                ],
              ),
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const Key('customer-open-full-profile'),
                  onPressed: () {
                    ref.read(customerProfileTabProvider.notifier).state = 0;
                    ref.read(customerProfileDetailIdProvider.notifier).state =
                        current.id;
                  },
                  icon: const Icon(Icons.contact_page_outlined),
                  label: const Text('Xem hồ sơ đầy đủ'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openCustomerBilling(context, ref, current),
                        icon: const Icon(Icons.point_of_sale_outlined),
                        label: const Text('Tính tiền'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openCustomerEditor(
                          context,
                          ref,
                          customer: current,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Sửa'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerFullProfile extends ConsumerWidget {
  const _CustomerFullProfile({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(customerInvoiceHistoryProvider(customer.id));
    final selectedTab = ref.watch(customerProfileTabProvider);

    return ListView(
      key: const Key('customer-full-profile'),
      primary: false,
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        PremiumSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                key: const Key('customer-profile-back'),
                onPressed: () =>
                    ref.read(customerProfileDetailIdProvider.notifier).state =
                        null,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Quay lại danh sách khách'),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PremiumIconBadge(
                        icon: customer.tier.contains('VIP')
                            ? Icons.workspace_premium_outlined
                            : Icons.person_outline_rounded,
                        size: 72,
                        tone: customer.tier.contains('VIP')
                            ? AppColors.warning
                            : AppColors.copper,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  customer.fullName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                _TierBadge(tier: customer.tier),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                _InlineMeta(
                                  icon: Icons.phone_outlined,
                                  text: customer.phone,
                                ),
                                if ((customer.email ?? '').trim().isNotEmpty)
                                  _InlineMeta(
                                    icon: Icons.mail_outline_rounded,
                                    text: customer.email!,
                                  ),
                                _InlineMeta(
                                  icon: Icons.history_rounded,
                                  text: 'Gần nhất: ${customer.lastVisitLabel}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );

                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      FilledButton.icon(
                        key: const Key('customer-profile-book'),
                        onPressed: () =>
                            _openCustomerAppointment(context, ref, customer),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Đặt lịch'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('customer-profile-billing'),
                        onPressed: () =>
                            _openCustomerBilling(context, ref, customer),
                        icon: const Icon(Icons.point_of_sale_outlined),
                        label: const Text('Tính tiền'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('customer-profile-edit'),
                        onPressed: () => _openCustomerEditor(
                          context,
                          ref,
                          customer: customer,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Sửa hồ sơ'),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [identity, const SizedBox(height: 14), actions],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 18),
                      Flexible(child: actions),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _CustomerProfileMetrics(customer: customer),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PremiumSectionCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CustomerProfileTabs(
                selected: selectedTab,
                onSelected: (value) =>
                    ref.read(customerProfileTabProvider.notifier).state = value,
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(selectedTab),
                  child: switch (selectedTab) {
                    1 => _ServiceHistoryTab(history: history),
                    2 => _NotesTab(customer: customer),
                    3 => _PaymentsTab(history: history),
                    _ => _CustomerOverviewTab(
                      customer: customer,
                      history: history,
                    ),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerProfileMetrics extends StatelessWidget {
  const _CustomerProfileMetrics({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Tổng chi tiêu',
        value: customer.spentLabel,
        tone: AppColors.copper,
      ),
      PremiumStatCard(
        icon: Icons.refresh_rounded,
        label: 'Số lần ghé',
        value: '${customer.visitCount}',
        tone: AppColors.success,
      ),
      PremiumStatCard(
        icon: Icons.stars_outlined,
        label: 'Điểm tích lũy',
        value: '${customer.loyaltyPoints}',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.calendar_today_outlined,
        label: 'Lần ghé gần nhất',
        value: customer.lastVisitLabel,
        tone: AppColors.info,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
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

class _CustomerProfileTabs extends StatelessWidget {
  const _CustomerProfileTabs({
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  static const tabs = [
    (Icons.person_outline_rounded, 'Tổng quan'),
    (Icons.content_cut_rounded, 'Lịch sử dịch vụ'),
    (Icons.sticky_note_2_outlined, 'Ghi chú'),
    (Icons.receipt_long_outlined, 'Thanh toán'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < tabs.length; index++)
          ChoiceChip(
            key: Key('customer-profile-tab-$index'),
            selected: selected == index,
            showCheckmark: false,
            avatar: Icon(tabs[index].$1, size: 16),
            label: Text(tabs[index].$2),
            onSelected: (_) => onSelected(index),
          ),
      ],
    );
  }
}

class _CustomerOverviewTab extends StatelessWidget {
  const _CustomerOverviewTab({required this.customer, required this.history});

  final CustomerProfile customer;
  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final details = PremiumSectionCard(
              icon: Icons.auto_awesome_outlined,
              title: 'Chăm sóc & sở thích',
              child: Column(
                children: [
                  PremiumInfoRow(
                    icon: Icons.content_cut_rounded,
                    label: 'Dịch vụ yêu thích',
                    value: customer.favoriteService.isEmpty
                        ? 'Chưa ghi nhận'
                        : customer.favoriteService,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.auto_fix_high_outlined,
                    label: 'Hồ sơ tóc',
                    value: customer.hairProfile.isEmpty
                        ? 'Chưa có hồ sơ tóc'
                        : customer.hairProfile,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Ghi chú salon',
                    value: customer.note.isEmpty
                        ? 'Chưa có ghi chú'
                        : customer.note,
                  ),
                ],
              ),
            );
            final contact = PremiumSectionCard(
              icon: Icons.contact_phone_outlined,
              title: 'Thông tin liên hệ',
              child: Column(
                children: [
                  PremiumInfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Số điện thoại',
                    value: customer.phone,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    value: (customer.email ?? '').trim().isEmpty
                        ? 'Chưa có email'
                        : customer.email!,
                  ),
                  const PremiumDivider(indent: 42),
                  PremiumInfoRow(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Hạng thành viên',
                    value: customer.tier,
                  ),
                ],
              ),
            );

            if (constraints.maxWidth < 820) {
              return Column(
                children: [details, const SizedBox(height: 12), contact],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                Expanded(child: contact),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _InvoiceHistory(history: history, limit: 3),
      ],
    );
  }
}

class _ServiceHistoryTab extends StatelessWidget {
  const _ServiceHistoryTab({required this.history});

  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (error, _) => PremiumEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Không tải được lịch sử dịch vụ',
        message: '$error',
      ),
      data: (invoices) {
        final serviceInvoices = invoices
            .where((invoice) => invoice.lines.any((line) => line.isService))
            .toList(growable: false);
        if (serviceInvoices.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.history_toggle_off_rounded,
            title: 'Chưa có lịch sử dịch vụ',
            message: 'Dịch vụ đã thanh toán của khách sẽ xuất hiện tại đây.',
          );
        }

        return Column(
          children: [
            for (var index = 0; index < serviceInvoices.length; index++) ...[
              _ServiceHistoryRow(invoice: serviceInvoices[index]),
              if (index < serviceInvoices.length - 1)
                const PremiumDivider(indent: 48),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceHistoryRow extends StatelessWidget {
  const _ServiceHistoryRow({required this.invoice});

  final InvoiceDraft invoice;

  @override
  Widget build(BuildContext context) {
    final services = invoice.lines
        .where((line) => line.isService)
        .toList(growable: false);
    final paidAt = invoice.paidAt ?? invoice.updatedAt;
    final serviceTotal = services.fold<int>(
      0,
      (sum, line) => sum + line.totalPrice,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PremiumIconBadge(
            icon: Icons.content_cut_rounded,
            size: 38,
            tone: AppColors.copper,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  services
                      .map(
                        (line) => line.quantity > 1
                            ? '${line.quantity} × ${line.title}'
                            : line.title,
                      )
                      .join(' • '),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_dateTime(paidAt)} • ${invoice.paymentMethod}',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _currency(serviceTotal),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.customer});

  final CustomerProfile customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumSectionCard(
          icon: Icons.auto_awesome_outlined,
          title: 'Hồ sơ tóc',
          child: Text(
            customer.hairProfile.isEmpty
                ? 'Chưa có hồ sơ tóc.'
                : customer.hairProfile,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ),
        const SizedBox(height: 12),
        PremiumSectionCard(
          icon: Icons.sticky_note_2_outlined,
          title: 'Ghi chú salon',
          child: Text(
            customer.note.isEmpty ? 'Chưa có ghi chú.' : customer.note,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () =>
                _openCustomerEditor(context, ref, customer: customer),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Chỉnh sửa hồ sơ & ghi chú'),
          ),
        ),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.history});

  final AsyncValue<List<InvoiceDraft>> history;

  @override
  Widget build(BuildContext context) {
    return _InvoiceHistory(history: history);
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

class _InvoiceHistory extends StatelessWidget {
  const _InvoiceHistory({required this.history, this.limit});

  final AsyncValue<List<InvoiceDraft>> history;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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

        final visible = limit == null
            ? invoices
            : invoices.take(limit!).toList(growable: false);
        final totalPaid = invoices.fold<int>(
          0,
          (sum, invoice) => sum + invoice.totalAmount,
        );
        return PremiumSectionCard(
          icon: Icons.receipt_long_outlined,
          title: 'Lịch sử thanh toán',
          subtitle: '${invoices.length} hóa đơn • ${_currency(totalPaid)}',
          child: Column(
            children: [
              for (var index = 0; index < visible.length; index++) ...[
                _InvoiceRow(invoice: visible[index]),
                if (index < visible.length - 1)
                  const PremiumDivider(indent: 42),
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
      value:
          '${_currency(invoice.totalAmount)} • ${invoice.lines.length} mục • ${invoice.paymentMethod}',
    );
  }
}

class _InlineMeta extends StatelessWidget {
  const _InlineMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
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
      constraints: const BoxConstraints(maxWidth: 120),
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

class _MissingCustomerProfile extends StatelessWidget {
  const _MissingCustomerProfile({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PremiumEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Không còn tìm thấy hồ sơ khách',
            message:
                'Hồ sơ có thể đã thay đổi. Quay lại danh sách để chọn lại khách.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Quay lại danh sách'),
          ),
        ],
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
                    if (value != null) setState(() => _tier = value);
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

class _CustomerAppointmentDialog extends StatefulWidget {
  const _CustomerAppointmentDialog({
    required this.customer,
    required this.services,
    required this.employees,
  });

  final CustomerProfile customer;
  final List<ServiceCatalogItem> services;
  final List<Map<String, Object?>> employees;

  @override
  State<_CustomerAppointmentDialog> createState() =>
      _CustomerAppointmentDialogState();
}

class _CustomerAppointmentDialogState
    extends State<_CustomerAppointmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _timeController = TextEditingController(text: '10:00');
  final _slotController = TextEditingController(text: 'Ghế 1');
  final _noteController = TextEditingController();
  final _durationController = TextEditingController(text: '90');
  List<String> _serviceIds = const [];
  String? _employeeId;
  String _dayLabel = 'Hôm nay';

  @override
  void initState() {
    super.initState();
    _employeeId = widget.employees.isEmpty
        ? null
        : widget.employees.first['id']?.toString();
  }

  @override
  void dispose() {
    _timeController.dispose();
    _slotController.dispose();
    _noteController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  List<ServiceCatalogItem> get _selectedServices {
    final ids = _serviceIds.toSet();
    return widget.services
        .where((service) => ids.contains(service.id))
        .toList(growable: false);
  }

  int get _selectedDuration => _selectedServices.fold<int>(
    0,
    (sum, service) => sum + service.durationMinutes,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const PremiumIconBadge(icon: Icons.calendar_month_outlined, size: 38),
          const SizedBox(width: 10),
          Expanded(child: Text('Đặt lịch cho ${widget.customer.fullName}')),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 620),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.featureSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.customer.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.customer.phone,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Dịch vụ',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 7),
                FormField<List<String>>(
                  initialValue: _serviceIds,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Chọn ít nhất một dịch vụ'
                      : null,
                  builder: (field) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.fieldShell,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: field.hasError
                            ? AppColors.danger
                            : AppColors.controlBorder,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final service in widget.services)
                          CheckboxListTile(
                            value: _serviceIds.contains(service.id),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              service.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${service.durationLabel} • ${service.priceLabel}',
                            ),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _serviceIds = {
                                    ..._serviceIds,
                                    service.id,
                                  }.toList(growable: false);
                                } else {
                                  _serviceIds = _serviceIds
                                      .where((id) => id != service.id)
                                      .toList(growable: false);
                                }
                                final duration = _selectedDuration;
                                _durationController.text =
                                    '${duration == 0 ? 90 : duration}';
                                field.didChange(_serviceIds);
                              });
                            },
                          ),
                        if (field.hasError)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                              child: Text(
                                field.errorText!,
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _employeeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nhân viên phụ trách',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: widget.employees
                      .map(
                        (employee) => DropdownMenuItem<String>(
                          value: employee['id']?.toString(),
                          child: Text(
                            '${employee['name']} • ${employee['role']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Chọn nhân viên' : null,
                  onChanged: (value) => setState(() => _employeeId = value),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final day = DropdownButtonFormField<String>(
                      initialValue: _dayLabel,
                      decoration: const InputDecoration(labelText: 'Ngày hẹn'),
                      items: const ['Hôm nay', 'Ngày mai']
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _dayLabel = value);
                        }
                      },
                    );
                    final time = TextFormField(
                      controller: _timeController,
                      decoration: const InputDecoration(labelText: 'Giờ hẹn'),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) {
                          return 'Dùng định dạng HH:mm';
                        }
                        return null;
                      },
                    );
                    if (stacked) {
                      return Column(
                        children: [day, const SizedBox(height: 10), time],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: day),
                        const SizedBox(width: 10),
                        Expanded(child: time),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 500;
                    final duration = TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(
                        labelText: 'Thời lượng (phút)',
                      ),
                      validator: (value) {
                        final minutes = int.tryParse(value?.trim() ?? '');
                        return minutes == null || minutes <= 0
                            ? 'Nhập số phút hợp lệ'
                            : null;
                      },
                    );
                    final slot = TextFormField(
                      controller: _slotController,
                      decoration: const InputDecoration(
                        labelText: 'Khu vực / ghế',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Nhập khu vực phục vụ'
                          : null,
                    );
                    if (stacked) {
                      return Column(
                        children: [duration, const SizedBox(height: 10), slot],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: duration),
                        const SizedBox(width: 10),
                        Expanded(child: slot),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                  maxLines: 3,
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
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Tạo lịch'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final employee = widget.employees
        .where((item) => item['id']?.toString() == _employeeId)
        .firstOrNull;
    final services = _selectedServices;
    if (employee == null || services.isEmpty) return;

    Navigator.of(context).pop(
      AppointmentUpsertInput(
        customerId: widget.customer.id,
        serviceIds: services
            .map((service) => service.id)
            .toList(growable: false),
        employeeId: employee['id']!.toString(),
        customerName: widget.customer.fullName,
        customerPhone: widget.customer.phone,
        serviceName: services.map((service) => service.name).join(' + '),
        staffName: employee['name']!.toString(),
        status: 'Chờ xác nhận',
        durationMinutes: int.parse(_durationController.text.trim()),
        slotLabel: _slotController.text.trim(),
        note: _noteController.text.trim(),
        dayLabel: _dayLabel,
        timeLabel: _timeController.text.trim(),
      ),
    );
  }
}

CustomerProfile? _findCustomer(List<CustomerProfile> items, String id) {
  for (final customer in items) {
    if (customer.id == id) return customer;
  }
  return null;
}

String _friendlyError(Object error) {
  final raw = error.toString().trim();
  const statePrefix = 'Bad state: ';
  return raw.startsWith(statePrefix)
      ? raw.substring(statePrefix.length).trim()
      : raw;
}

final NumberFormat _currencyFormatter = NumberFormat.currency(
  locale: 'vi_VN',
  symbol: 'đ',
  decimalDigits: 0,
);
final DateFormat _dateTimeFormatter = DateFormat('dd/MM/yyyy HH:mm');

String _currency(int value) =>
    _currencyFormatter.format(value).replaceAll(',', '.');
String _dateTime(DateTime value) => _dateTimeFormatter.format(value);
