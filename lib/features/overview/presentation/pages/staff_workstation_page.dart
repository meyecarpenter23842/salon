import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';
import '../../../invoices/presentation/pages/invoices_page.dart';

class StaffWorkstationPage extends ConsumerStatefulWidget {
  const StaffWorkstationPage({
    super.key,
    this.standalone = false,
    this.sideRail,
    this.onOpenCompactRail,
  });

  final bool standalone;
  final Widget? sideRail;
  final VoidCallback? onOpenCompactRail;

  @override
  ConsumerState<StaffWorkstationPage> createState() =>
      _StaffWorkstationPageState();
}

class _StaffWorkstationPageState extends ConsumerState<StaffWorkstationPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _isProcessing = false;
  String _searchQuery = '';
  _StaffFilter _selectedFilter = _StaffFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsState = ref.watch(appointmentsViewProvider);
    final servicesState = ref.watch(servicesViewProvider);
    final productsState = ref.watch(retailProductsViewProvider);
    final draftState = ref.watch(invoiceDraftProvider);
    final appointments =
        appointmentsState.valueOrNull ?? const <AppointmentEntry>[];
    final draftLabel = draftState.when(
      data: (draft) => _staffDraftLabel(draft, appointments),
      loading: () => 'Đang đọc bill…',
      error: (_, _) => 'Không đọc được bill',
    );
    final hasActiveDraft = draftState.valueOrNull != null &&
        _staffHasDraftWork(draftState.valueOrNull!);

    final workstationBody = servicesState.when(
      data: (services) => productsState.when(
        data: (products) => appointmentsState.when(
          data: (items) => _StaffBody(
            appointments: _filterTodayAppointments(items),
            services: services
                .where((service) => service.isActive)
                .toList(growable: false),
            products: products
                .where(
                  (product) => product.isActive && !product.isHiddenFromStaff,
                )
                .toList(growable: false),
            isProcessing: _isProcessing,
            searchQuery: _searchQuery,
            selectedFilter: _selectedFilter,
            onFilterSelected: (filter) {
              setState(() => _selectedFilter = filter);
            },
            onReceive: (appointment) =>
                _updateStatus(appointment, 'Đã đặt'),
            onStartService: (appointment) =>
                _updateStatus(appointment, 'Đang làm'),
            onComplete: (appointment) =>
                _updateStatus(appointment, 'Hoàn thành'),
            onUndoComplete: (appointment) =>
                _updateStatus(appointment, 'Đang làm'),
            onCancel: (appointment) =>
                _updateStatus(appointment, 'Đã hủy'),
            onCheckout: _checkoutAppointment,
            onAddService: _addServiceForAppointment,
            onAddProduct: _addProductForAppointment,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _StaffError(
            message: 'Không tải được bàn thao tác nhân viên: $error',
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _StaffError(
          message: 'Không tải được sản phẩm bán lẻ: $error',
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _StaffError(
        message: 'Không tải được dịch vụ đang hoạt động: $error',
      ),
    );

    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.background, AppColors.backgroundSoft],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              _StaffHeader(
                searchController: _searchController,
                searchQuery: _searchQuery,
                isProcessing: _isProcessing,
                standalone: widget.standalone,
                draftLabel: draftLabel,
                hasActiveDraft: hasActiveDraft,
                onSearchChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                onClearSearch: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                onClose: _closeWindow,
                onOpenBilling: _openBillingDesk,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasRail = widget.sideRail != null;
                    final showRail = hasRail && constraints.maxWidth >= 1180;

                    if (!showRail) {
                      return Stack(
                        children: [
                          Positioned.fill(child: workstationBody),
                          if (hasRail && widget.onOpenCompactRail != null)
                            Positioned(
                              right: 14,
                              bottom: 14,
                              child: FilledButton.icon(
                                key: const Key('staff-quick-rail-open'),
                                onPressed: widget.onOpenCompactRail,
                                icon: const Icon(Icons.bolt_outlined, size: 18),
                                label: const Text('Thao tác nhanh'),
                              ),
                            ),
                        ],
                      );
                    }

                    final railWidth =
                        constraints.maxWidth >= 1540 ? 430.0 : 350.0;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: workstationBody),
                        const SizedBox(width: 16),
                        SizedBox(width: railWidth, child: widget.sideRail),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.standalone) return Scaffold(body: content);
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: content,
    );
  }

  Future<void> _closeWindow() async {
    if (widget.standalone) {
      await SystemNavigator.pop();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  List<AppointmentEntry> _filterTodayAppointments(
    List<AppointmentEntry> source,
  ) {
    final now = DateTime.now();
    final todayItems = source.where((item) {
      final startsAt = item.startsAt;
      return startsAt.year == now.year &&
          startsAt.month == now.month &&
          startsAt.day == now.day;
    }).toList(growable: false)
      ..sort(_compareStaffAppointments);

    return todayItems;
  }

  Future<void> _updateStatus(
    AppointmentEntry appointment,
    String status,
  ) async {
    if (_isProcessing || appointment.isPaid) return;
    setState(() => _isProcessing = true);
    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .updateAppointmentStatus(appointment.id, status);
      ref.invalidate(appointmentsViewProvider);
      ref.invalidate(overviewSummaryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã cập nhật ${appointment.customerName} sang trạng thái $status',
          ),
        ),
      );
    } on StateError catch (error) {
      await _showBusinessError(error.message.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _checkoutAppointment(AppointmentEntry appointment) async {
    if (_isProcessing || appointment.isPaid) return;
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final draft = await _prepareDraftForAppointment(appointment);
      if (draft == null) return;
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }
      if (!mounted) return;
      if (!widget.standalone) await _closeWindow();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã mở tính tiền cho ${appointment.customerName}'),
        ),
      );
    } on StateError catch (error) {
      await _showBusinessError(
        _friendlyInvoiceError(error, appointment.customerName),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _openBillingDesk() {
    if (widget.standalone) {
      _openStandaloneBilling();
      return;
    }
    ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
    _closeWindow();
  }

  Future<void> _addServiceForAppointment(
    AppointmentEntry appointment,
    ServiceCatalogItem service,
  ) async {
    if (_isProcessing || appointment.isPaid) return;
    setState(() => _isProcessing = true);
    try {
      final draft = await _prepareDraftForAppointment(appointment);
      if (draft == null) return;
      await ref.read(invoicesRepositoryProvider).addInvoiceService(service.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm phát sinh ${service.name} vào bill của ${appointment.customerName}.',
          ),
        ),
      );
    } on StateError catch (error) {
      await _showBusinessError(
        _friendlyInvoiceError(error, appointment.customerName),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _addProductForAppointment(
    AppointmentEntry appointment,
    RetailProductItem product,
  ) async {
    if (_isProcessing || appointment.isPaid) return;
    setState(() => _isProcessing = true);
    try {
      final draft = await _prepareDraftForAppointment(appointment);
      if (draft == null) return;
      await ref.read(invoicesRepositoryProvider).addInvoiceProduct(product.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm ${product.name} vào bill của ${appointment.customerName}.',
          ),
        ),
      );
    } on StateError catch (error) {
      await _showBusinessError(
        _friendlyInvoiceError(error, appointment.customerName),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<InvoiceDraft?> _prepareDraftForAppointment(
    AppointmentEntry appointment,
  ) async {
    final repository = ref.read(invoicesRepositoryProvider);
    final draft = await repository.fetchInvoiceDraft();

    if (!_staffHasDraftWork(draft)) {
      final prepared = await repository.prefillDraftFromAppointment(appointment);
      ref.invalidate(invoiceDraftProvider);
      return prepared;
    }

    if (draft.appointmentId == appointment.id) {
      return draft;
    }

    final canReuseEmptyCustomerSelection = draft.lines.isEmpty &&
        draft.appointmentId == null &&
        draft.customerId == appointment.customerId;
    if (canReuseEmptyCustomerSelection) {
      final prepared = await repository.prefillDraftFromAppointment(appointment);
      ref.invalidate(invoiceDraftProvider);
      return prepared;
    }

    await _showDraftConflict(appointment, draft);
    return null;
  }

  Future<void> _showDraftConflict(
    AppointmentEntry target,
    InvoiceDraft draft,
  ) async {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    final appointments = ref.read(appointmentsViewProvider).valueOrNull ??
        const <AppointmentEntry>[];
    final owner = _staffDraftOwner(draft, appointments);
    final openBill = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đang có bill chưa hoàn tất'),
        content: Text(
          owner == 'Khách đã chọn'
              ? 'Bill hiện tại đang có dữ liệu. Hãy mở bill đó để hoàn tất hoặc xóa bill trước khi tính tiền cho ${target.customerName}.'
              : 'Bill hiện tại đang thuộc $owner. Hãy hoàn tất hoặc xóa bill đó trước khi tính tiền cho ${target.customerName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.point_of_sale_outlined),
            label: const Text('Mở bill hiện tại'),
          ),
        ],
      ),
    );
    if (openBill == true && mounted) {
      _openBillingDesk();
    }
  }

  Future<void> _showBusinessError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Không thể thực hiện'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStandaloneBilling() async {
    if (!widget.standalone || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Tính tiền (Staff)')),
          body: const Padding(
            padding: EdgeInsets.all(16),
            child: InvoicesPage(),
          ),
        ),
      ),
    );
  }
}

class _StaffHeader extends StatelessWidget {
  const _StaffHeader({
    required this.searchController,
    required this.searchQuery,
    required this.isProcessing,
    required this.standalone,
    required this.draftLabel,
    required this.hasActiveDraft,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onClose,
    required this.onOpenBilling,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final bool isProcessing;
  final bool standalone;
  final String draftLabel;
  final bool hasActiveDraft;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onClose;
  final VoidCallback onOpenBilling;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayLabel = _staffDateLabel(now);

    return Container(
      key: const Key('staff-compact-header'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.controlBorder),
        boxShadow: AppColors.surfaceShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1050;

          final title = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PremiumIconBadge(
                icon: Icons.badge_outlined,
                size: 46,
                tone: AppColors.copper,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bàn thao tác nhân viên',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 23,
                            letterSpacing: -0.35,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Không gian thao tác nhanh, hoạt động độc lập khỏi ứng dụng chính',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final date = Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: AppColors.featureSurface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.controlBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    todayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );

          final search = SizedBox(
            key: const Key('staff-search-wrap'),
            height: 48,
            child: TextField(
              key: const Key('staff-search'),
              controller: searchController,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm tên khách hàng, số điện thoại…',
                prefixIcon: const Icon(Icons.search_rounded, size: 21),
                suffixIcon: searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        key: const Key('staff-clear-search'),
                        onPressed: onClearSearch,
                        tooltip: 'Xóa tìm kiếm',
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                isDense: true,
              ),
            ),
          );

          final bill = _DraftSummaryCard(
            label: draftLabel,
            active: hasActiveDraft,
          );

          final openBill = SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('staff-open-billing'),
              onPressed: isProcessing ? null : onOpenBilling,
              icon: Icon(
                hasActiveDraft
                    ? Icons.point_of_sale_outlined
                    : Icons.add_rounded,
                size: 19,
              ),
              label: Text(hasActiveDraft ? 'Mở bill' : 'Tính tiền'),
            ),
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    if (!standalone)
                      IconButton(
                        onPressed: isProcessing ? null : onClose,
                        tooltip: 'Đóng bàn nhân viên',
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(width: 190, child: date),
                    const SizedBox(width: 10),
                    Expanded(child: search),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: bill),
                    const SizedBox(width: 10),
                    SizedBox(width: 132, child: openBill),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 4, child: title),
              const SizedBox(width: 14),
              SizedBox(width: 190, child: date),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: search),
              const SizedBox(width: 12),
              SizedBox(width: 230, child: bill),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: openBill),
              if (!standalone) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: isProcessing ? null : onClose,
                  tooltip: 'Đóng bàn nhân viên',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DraftSummaryCard extends StatelessWidget {
  const _DraftSummaryCard({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tone = active ? AppColors.warning : AppColors.textMuted;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active
            ? AppColors.warning.withValues(alpha: 0.09)
            : AppColors.featureSurface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: active
              ? AppColors.warning.withValues(alpha: 0.28)
              : AppColors.controlBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.point_of_sale_outlined, size: 18, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bill đang làm',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        active ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffBody extends StatelessWidget {
  const _StaffBody({
    required this.appointments,
    required this.services,
    required this.products,
    required this.isProcessing,
    required this.searchQuery,
    required this.selectedFilter,
    required this.onFilterSelected,
    required this.onReceive,
    required this.onStartService,
    required this.onComplete,
    required this.onUndoComplete,
    required this.onCancel,
    required this.onCheckout,
    required this.onAddService,
    required this.onAddProduct,
  });

  final List<AppointmentEntry> appointments;
  final List<ServiceCatalogItem> services;
  final List<RetailProductItem> products;
  final bool isProcessing;
  final String searchQuery;
  final _StaffFilter selectedFilter;
  final ValueChanged<_StaffFilter> onFilterSelected;
  final ValueChanged<AppointmentEntry> onReceive;
  final ValueChanged<AppointmentEntry> onStartService;
  final ValueChanged<AppointmentEntry> onComplete;
  final ValueChanged<AppointmentEntry> onUndoComplete;
  final ValueChanged<AppointmentEntry> onCancel;
  final ValueChanged<AppointmentEntry> onCheckout;
  final Future<void> Function(
    AppointmentEntry appointment,
    ServiceCatalogItem service,
  ) onAddService;
  final Future<void> Function(
    AppointmentEntry appointment,
    RetailProductItem product,
  ) onAddProduct;

  @override
  Widget build(BuildContext context) {
    final filtered = appointments.where((appointment) {
      if (!_staffMatchesFilter(appointment, selectedFilter)) return false;
      return _staffMatchesSearch(appointment, searchQuery);
    }).toList(growable: false);

    return Column(
      key: const Key('staff-operation-workspace'),
      children: [
        _StaffFilterBar(
          appointments: appointments,
          selectedFilter: selectedFilter,
          onSelected: onFilterSelected,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            key: const Key('staff-premium-workspace'),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.controlBorder),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.view_timeline_outlined,
                        size: 19,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Khách hôm nay (${appointments.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _staffListSummary(
                                total: appointments.length,
                                visible: filtered.length,
                                query: searchQuery,
                                filter: selectedFilter,
                              ),
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isProcessing) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_vert_rounded,
                            size: 17,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Ưu tiên xử lý · theo giờ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const PremiumDivider(),
                Expanded(
                  child: appointments.isEmpty
                      ? const PremiumEmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'Hôm nay chưa có lịch',
                          message:
                              'Lịch mới sẽ xuất hiện ở đây để nhân viên xử lý.',
                        )
                      : filtered.isEmpty
                          ? PremiumEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Không có khách phù hợp',
                              message: searchQuery.trim().isNotEmpty
                                  ? 'Thử tên, số điện thoại khác hoặc đổi bộ lọc.'
                                  : 'Đổi bộ lọc để xem các lịch hôm nay.',
                            )
                          : ListView.separated(
                              primary: false,
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 14),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final appointment = filtered[index];
                                return _StaffAppointmentRow(
                                  appointment: appointment,
                                  services: services,
                                  products: products,
                                  isProcessing: isProcessing,
                                  onReceive: onReceive,
                                  onStartService: onStartService,
                                  onComplete: onComplete,
                                  onUndoComplete: onUndoComplete,
                                  onCancel: onCancel,
                                  onCheckout: onCheckout,
                                  onAddService: onAddService,
                                  onAddProduct: onAddProduct,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StaffFilterBar extends StatelessWidget {
  const _StaffFilterBar({
    required this.appointments,
    required this.selectedFilter,
    required this.onSelected,
  });

  final List<AppointmentEntry> appointments;
  final _StaffFilter selectedFilter;
  final ValueChanged<_StaffFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('staff-filter-bar'),
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in _StaffFilter.values) ...[
              _StaffFilterChip(
                key: Key('staff-filter-${filter.name}'),
                filter: filter,
                count: _staffFilterCount(appointments, filter),
                selected: filter == selectedFilter,
                onTap: () => onSelected(filter),
              ),
              if (filter != _StaffFilter.values.last)
                const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaffFilterChip extends StatelessWidget {
  const _StaffFilterChip({
    super.key,
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _StaffFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = _staffFilterTone(filter);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.shellAccentSurface
                : AppColors.featureSurface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.copper.withValues(alpha: 0.55)
                  : AppColors.controlBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _staffFilterIcon(filter),
                size: 17,
                color: selected ? AppColors.copper : tone,
              ),
              const SizedBox(width: 8),
              Text(
                _staffFilterLabel(filter),
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.copper.withValues(alpha: 0.18)
                      : AppColors.panelRaised,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? AppColors.copper : AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffAppointmentRow extends StatelessWidget {
  const _StaffAppointmentRow({
    required this.appointment,
    required this.services,
    required this.products,
    required this.isProcessing,
    required this.onReceive,
    required this.onStartService,
    required this.onComplete,
    required this.onUndoComplete,
    required this.onCancel,
    required this.onCheckout,
    required this.onAddService,
    required this.onAddProduct,
  });

  final AppointmentEntry appointment;
  final List<ServiceCatalogItem> services;
  final List<RetailProductItem> products;
  final bool isProcessing;
  final ValueChanged<AppointmentEntry> onReceive;
  final ValueChanged<AppointmentEntry> onStartService;
  final ValueChanged<AppointmentEntry> onComplete;
  final ValueChanged<AppointmentEntry> onUndoComplete;
  final ValueChanged<AppointmentEntry> onCancel;
  final ValueChanged<AppointmentEntry> onCheckout;
  final Future<void> Function(
    AppointmentEntry appointment,
    ServiceCatalogItem service,
  ) onAddService;
  final Future<void> Function(
    AppointmentEntry appointment,
    RetailProductItem product,
  ) onAddProduct;

  @override
  Widget build(BuildContext context) {
    final state = _staffOperationalState(appointment);
    final tone = _staffOperationalTone(appointment);
    final timing = _staffTimingLabel(appointment, DateTime.now());

    return Container(
      key: Key('staff-appointment-${appointment.id}'),
      constraints: const BoxConstraints(minHeight: 108),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tone.withValues(
            alpha: state == _StaffOperationalState.active ? 0.35 : 0.16,
          ),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 5, color: tone),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                if (compact) return _buildCompact(context, timing);
                return _buildWide(context, timing);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context, String timing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 122,
          child: _TimeCell(appointment: appointment, timing: timing),
        ),
        Container(
          width: 1,
          height: 62,
          color: AppColors.controlBorder,
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _CustomerCell(appointment: appointment),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: _ServiceCell(appointment: appointment),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 186,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PremiumStatusPill(
                  label: _staffOperationalLabel(appointment),
                  tone: _staffOperationalTone(appointment),
                ),
              ),
              const SizedBox(height: 9),
              _buildPrimaryAction(),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _buildSecondaryMenu(context),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, String timing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: _TimeCell(appointment: appointment, timing: timing),
            ),
            const SizedBox(width: 12),
            Expanded(child: _CustomerCell(appointment: appointment)),
            const SizedBox(width: 8),
            PremiumStatusPill(
              label: _staffOperationalLabel(appointment),
              tone: _staffOperationalTone(appointment),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ServiceCell(appointment: appointment),
        const SizedBox(height: 10),
        Row(
          children: [
            const Spacer(),
            SizedBox(width: 170, child: _buildPrimaryAction()),
            const SizedBox(width: 5),
            _buildSecondaryMenu(context),
          ],
        ),
      ],
    );
  }

  Widget _buildPrimaryAction() {
    final state = _staffOperationalState(appointment);
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );

    switch (state) {
      case _StaffOperationalState.waitingConfirmation:
        return FilledButton.icon(
          key: Key('staff-primary-${appointment.id}'),
          style: style,
          onPressed: isProcessing ? null : () => onReceive(appointment),
          icon: const Icon(Icons.event_available_outlined, size: 17),
          label: const Text('Xác nhận lịch'),
        );
      case _StaffOperationalState.booked:
        return FilledButton.icon(
          key: Key('staff-primary-${appointment.id}'),
          style: style,
          onPressed: isProcessing ? null : () => onStartService(appointment),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Bắt đầu'),
        );
      case _StaffOperationalState.active:
        return FilledButton.icon(
          key: Key('staff-primary-${appointment.id}'),
          style: style,
          onPressed: isProcessing ? null : () => onComplete(appointment),
          icon: const Icon(Icons.task_alt_outlined, size: 17),
          label: const Text('Hoàn thành'),
        );
      case _StaffOperationalState.awaitingPayment:
        return FilledButton.icon(
          key: Key('staff-checkout-${appointment.id}'),
          style: style,
          onPressed: isProcessing ? null : () => onCheckout(appointment),
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: const Text('Tính tiền'),
        );
      case _StaffOperationalState.paid:
        return OutlinedButton.icon(
          key: Key('staff-primary-${appointment.id}'),
          onPressed: null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          icon: const Icon(Icons.verified_outlined, size: 17),
          label: const Text('Đã thu'),
        );
      case _StaffOperationalState.canceled:
        return OutlinedButton.icon(
          key: Key('staff-primary-${appointment.id}'),
          onPressed: null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          icon: const Icon(Icons.event_busy_outlined, size: 17),
          label: const Text('Đã hủy'),
        );
      case _StaffOperationalState.other:
        return OutlinedButton(
          key: Key('staff-primary-${appointment.id}'),
          onPressed: null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
          child: Text(_staffOperationalLabel(appointment)),
        );
    }
  }

  Widget _buildSecondaryMenu(BuildContext context) {
    if (appointment.isPaid) {
      return const SizedBox(width: 40);
    }

    final canUndo = _staffOperationalState(appointment) ==
        _StaffOperationalState.awaitingPayment;
    final canCancel = appointment.status != 'Đã hủy';

    return PopupMenuButton<String>(
      key: Key('staff-actions-${appointment.id}'),
      enabled: !isProcessing,
      tooltip: 'Thao tác khác',
      onSelected: (value) async {
        if (value == 'service') {
          final service = await _openStaffServicePicker(context, services);
          if (service != null) {
            await onAddService(appointment, service);
          }
        } else if (value == 'product') {
          final product = await _openStaffProductPicker(context, products);
          if (product != null) {
            await onAddProduct(appointment, product);
          }
        } else if (value == 'undo' && canUndo) {
          onUndoComplete(appointment);
        } else if (value == 'cancel' && canCancel) {
          onCancel(appointment);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'service',
          child: ListTile(
            leading: Icon(Icons.add_business_outlined),
            title: Text('Thêm phát sinh vào bill'),
          ),
        ),
        const PopupMenuItem(
          value: 'product',
          child: ListTile(
            leading: Icon(Icons.shopping_bag_outlined),
            title: Text('Thêm sản phẩm vào bill'),
          ),
        ),
        if (canUndo)
          const PopupMenuItem(
            value: 'undo',
            child: ListTile(
              leading: Icon(Icons.undo_outlined),
              title: Text('Hoàn tác hoàn thành'),
            ),
          ),
        PopupMenuItem(
          value: 'cancel',
          enabled: canCancel,
          child: const ListTile(
            leading: Icon(Icons.event_busy_outlined),
            title: Text('Hủy lịch'),
          ),
        ),
      ],
      icon: const Icon(Icons.more_horiz_rounded),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.appointment, required this.timing});

  final AppointmentEntry appointment;
  final String timing;

  @override
  Widget build(BuildContext context) {
    final tone = _staffTimingTone(appointment, DateTime.now());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appointment.timeLabel,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                timing,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.25,
                  color: tone,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomerCell extends StatelessWidget {
  const _CustomerCell({required this.appointment});

  final AppointmentEntry appointment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appointment.customerName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                appointment.customerPhone,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceCell extends StatelessWidget {
  const _ServiceCell({required this.appointment});

  final AppointmentEntry appointment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          appointment.servicesSummary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _MetaCell(
              icon: Icons.person_outline_rounded,
              label: appointment.staffName,
            ),
            _MetaCell(
              icon: Icons.schedule_outlined,
              label: appointment.durationLabel,
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaCell extends StatelessWidget {
  const _MetaCell({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

Future<RetailProductItem?> _openStaffProductPicker(
  BuildContext context,
  List<RetailProductItem> products,
) {
  return showDialog<RetailProductItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Chọn sản phẩm thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: products.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Chưa có sản phẩm',
                message: 'Không có sản phẩm đang hiển thị cho nhân viên.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, _) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    leading: const PremiumIconBadge(
                      icon: Icons.shopping_bag_outlined,
                      size: 34,
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(product),
                    title: Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${product.productType}${product.brand.isEmpty ? '' : ' • ${product.brand}'}',
                    ),
                    trailing: Text(
                      product.salePriceLabel,
                      style: TextStyle(
                        color: AppColors.copper,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

Future<ServiceCatalogItem?> _openStaffServicePicker(
  BuildContext context,
  List<ServiceCatalogItem> services,
) {
  return showDialog<ServiceCatalogItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Chọn dịch vụ phát sinh thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: services.isEmpty
            ? const PremiumEmptyState(
                icon: Icons.content_cut_rounded,
                title: 'Chưa có dịch vụ',
                message: 'Không có dịch vụ đang hoạt động.',
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: services.length,
                separatorBuilder: (_, _) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final service = services[index];
                  return ListTile(
                    leading: const PremiumIconBadge(
                      icon: Icons.content_cut_rounded,
                      size: 34,
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(service),
                    title: Text(
                      service.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${service.category} • ${service.durationLabel}',
                    ),
                    trailing: Text(
                      service.priceLabel,
                      style: TextStyle(
                        color: AppColors.copper,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

class _StaffError extends StatelessWidget {
  const _StaffError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Không tải được dữ liệu',
      message: message,
    );
  }
}

enum _StaffOperationalState {
  waitingConfirmation,
  booked,
  active,
  awaitingPayment,
  paid,
  canceled,
  other,
}

enum _StaffFilter {
  all,
  waitingConfirmation,
  booked,
  active,
  awaitingPayment,
  paid,
}

_StaffOperationalState _staffOperationalState(AppointmentEntry appointment) {
  if (appointment.isPaid) return _StaffOperationalState.paid;
  if (appointment.status == 'Hoàn thành') {
    return _StaffOperationalState.awaitingPayment;
  }
  if (appointment.status == 'Chờ xác nhận') {
    return _StaffOperationalState.waitingConfirmation;
  }
  if (appointment.status == 'Đã đặt') return _StaffOperationalState.booked;
  if (appointment.status == 'Đang làm') return _StaffOperationalState.active;
  if (appointment.status == 'Đã hủy') return _StaffOperationalState.canceled;
  return _StaffOperationalState.other;
}

String _staffOperationalLabel(AppointmentEntry appointment) {
  switch (_staffOperationalState(appointment)) {
    case _StaffOperationalState.awaitingPayment:
      return 'Chờ thu';
    case _StaffOperationalState.paid:
      return 'Đã thu';
    case _StaffOperationalState.waitingConfirmation:
      return 'Chờ xác nhận';
    case _StaffOperationalState.booked:
      return 'Đã đặt';
    case _StaffOperationalState.active:
      return 'Đang làm';
    case _StaffOperationalState.canceled:
      return 'Đã hủy';
    case _StaffOperationalState.other:
      return appointment.status;
  }
}

Color _staffOperationalTone(AppointmentEntry appointment) {
  switch (_staffOperationalState(appointment)) {
    case _StaffOperationalState.awaitingPayment:
      return AppColors.warning;
    case _StaffOperationalState.paid:
      return AppColors.success;
    case _StaffOperationalState.active:
      return AppColors.success;
    case _StaffOperationalState.booked:
      return AppColors.info;
    case _StaffOperationalState.canceled:
      return AppColors.textMuted;
    case _StaffOperationalState.waitingConfirmation:
    case _StaffOperationalState.other:
      return AppColors.copper;
  }
}

String _staffFilterLabel(_StaffFilter filter) {
  switch (filter) {
    case _StaffFilter.all:
      return 'Tất cả';
    case _StaffFilter.waitingConfirmation:
      return 'Chờ xác nhận';
    case _StaffFilter.booked:
      return 'Đã đặt';
    case _StaffFilter.active:
      return 'Đang làm';
    case _StaffFilter.awaitingPayment:
      return 'Chờ thu';
    case _StaffFilter.paid:
      return 'Đã thu';
  }
}

IconData _staffFilterIcon(_StaffFilter filter) {
  switch (filter) {
    case _StaffFilter.all:
      return Icons.grid_view_rounded;
    case _StaffFilter.waitingConfirmation:
      return Icons.schedule_outlined;
    case _StaffFilter.booked:
      return Icons.event_available_outlined;
    case _StaffFilter.active:
      return Icons.content_cut_rounded;
    case _StaffFilter.awaitingPayment:
      return Icons.receipt_long_outlined;
    case _StaffFilter.paid:
      return Icons.task_alt_rounded;
  }
}

Color _staffFilterTone(_StaffFilter filter) {
  switch (filter) {
    case _StaffFilter.all:
      return AppColors.copper;
    case _StaffFilter.waitingConfirmation:
      return AppColors.copper;
    case _StaffFilter.booked:
      return AppColors.info;
    case _StaffFilter.active:
      return AppColors.success;
    case _StaffFilter.awaitingPayment:
      return AppColors.warning;
    case _StaffFilter.paid:
      return AppColors.success;
  }
}

bool _staffMatchesFilter(
  AppointmentEntry appointment,
  _StaffFilter filter,
) {
  if (filter == _StaffFilter.all) return true;
  final state = _staffOperationalState(appointment);
  switch (filter) {
    case _StaffFilter.all:
      return true;
    case _StaffFilter.waitingConfirmation:
      return state == _StaffOperationalState.waitingConfirmation;
    case _StaffFilter.booked:
      return state == _StaffOperationalState.booked;
    case _StaffFilter.active:
      return state == _StaffOperationalState.active;
    case _StaffFilter.awaitingPayment:
      return state == _StaffOperationalState.awaitingPayment;
    case _StaffFilter.paid:
      return state == _StaffOperationalState.paid;
  }
}

int _staffFilterCount(
  List<AppointmentEntry> appointments,
  _StaffFilter filter,
) {
  if (filter == _StaffFilter.all) return appointments.length;
  return appointments
      .where((appointment) => _staffMatchesFilter(appointment, filter))
      .length;
}

bool _staffMatchesSearch(
  AppointmentEntry appointment,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return appointment.customerName.toLowerCase().contains(normalized) ||
      appointment.customerPhone.toLowerCase().contains(normalized);
}

String _staffListSummary({
  required int total,
  required int visible,
  required String query,
  required _StaffFilter filter,
}) {
  if (total == 0) return 'Chưa có lịch để thao tác';
  if (query.trim().isEmpty && filter == _StaffFilter.all) {
    return '$total lượt hôm nay · ưu tiên khách cần xử lý trước';
  }
  return '$visible / $total lượt phù hợp';
}

String _staffTimingLabel(
  AppointmentEntry appointment,
  DateTime now,
) {
  final state = _staffOperationalState(appointment);
  if (state == _StaffOperationalState.paid) return 'Đã hoàn tất thanh toán';
  if (state == _StaffOperationalState.canceled) return 'Lịch đã hủy';
  if (state == _StaffOperationalState.awaitingPayment) {
    return 'Đã xong · chờ thu';
  }

  final start = appointment.startsAt;
  final end = start.add(Duration(minutes: appointment.durationMinutes));

  if (now.isBefore(start)) {
    final minutes = start.difference(now).inMinutes;
    if (minutes <= 30) {
      return 'Gần tới · còn ${minutes < 1 ? 1 : minutes} phút';
    }
    return 'Sắp tới · ${appointment.timeLabel}';
  }

  if (now.isBefore(end)) {
    if (state == _StaffOperationalState.active) return 'Đang làm';
    return 'Đã tới giờ';
  }

  final overdue = now.difference(end).inMinutes;
  if (state == _StaffOperationalState.active) {
    return 'Quá giờ $overdue phút';
  }
  if (state == _StaffOperationalState.waitingConfirmation ||
      state == _StaffOperationalState.booked) {
    return 'Quá giờ $overdue phút';
  }
  return 'Đã qua khung giờ';
}

Color _staffTimingTone(
  AppointmentEntry appointment,
  DateTime now,
) {
  final state = _staffOperationalState(appointment);
  if (state == _StaffOperationalState.paid) return AppColors.success;
  if (state == _StaffOperationalState.canceled) return AppColors.textMuted;
  if (state == _StaffOperationalState.awaitingPayment) return AppColors.warning;

  final start = appointment.startsAt;
  final end = start.add(Duration(minutes: appointment.durationMinutes));
  if (now.isBefore(start)) return AppColors.info;
  if (now.isBefore(end)) return AppColors.success;
  return AppColors.warning;
}

int _compareStaffAppointments(AppointmentEntry a, AppointmentEntry b) {
  final priorityCompare =
      _staffOperationalPriority(a).compareTo(_staffOperationalPriority(b));
  if (priorityCompare != 0) return priorityCompare;
  return a.startsAt.compareTo(b.startsAt);
}

int _staffOperationalPriority(AppointmentEntry appointment) {
  switch (_staffOperationalState(appointment)) {
    case _StaffOperationalState.waitingConfirmation:
      return 0;
    case _StaffOperationalState.awaitingPayment:
      return 1;
    case _StaffOperationalState.active:
      return 2;
    case _StaffOperationalState.booked:
      return 3;
    case _StaffOperationalState.paid:
      return 4;
    case _StaffOperationalState.canceled:
      return 5;
    case _StaffOperationalState.other:
      return 6;
  }
}

bool _staffHasDraftWork(InvoiceDraft draft) {
  return draft.lines.isNotEmpty ||
      draft.customerId.trim().isNotEmpty ||
      (draft.appointmentId?.trim().isNotEmpty ?? false);
}

String _staffDraftLabel(
  InvoiceDraft draft,
  List<AppointmentEntry> appointments,
) {
  if (!_staffHasDraftWork(draft)) return 'Chưa có bill';
  final owner = _staffDraftOwner(draft, appointments);
  final total = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  ).format(draft.totalAmount).replaceAll(',', '.');
  return 'Bill: $owner · $total';
}

String _staffDraftOwner(
  InvoiceDraft draft,
  List<AppointmentEntry> appointments,
) {
  final appointmentId = draft.appointmentId;
  if (appointmentId != null && appointmentId.isNotEmpty) {
    for (final appointment in appointments) {
      if (appointment.id == appointmentId) return appointment.customerName;
    }
  }

  final customerId = draft.customerId.trim();
  if (customerId.isNotEmpty) {
    for (final appointment in appointments) {
      if (appointment.customerId == customerId) return appointment.customerName;
    }
  }
  return 'Khách đã chọn';
}

String _staffDateLabel(DateTime date) {
  const weekDays = [
    '',
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekDays[date.weekday]}, ${DateFormat('dd/MM/yyyy').format(date)}';
}

String _friendlyInvoiceError(StateError error, String customerName) {
  final message = error.message.toString();
  if (message.contains('Bill đang làm đã có dữ liệu')) {
    return 'Đang có bill khác chưa hoàn tất. Hãy mở bill hiện tại để hoàn tất hoặc xóa bill trước khi tính tiền cho $customerName.';
  }
  return message;
}
