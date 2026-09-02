import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';
import '../../../invoices/presentation/pages/invoices_page.dart';

class StaffWorkstationPage extends ConsumerStatefulWidget {
  const StaffWorkstationPage({super.key, this.standalone = false});

  final bool standalone;

  @override
  ConsumerState<StaffWorkstationPage> createState() => _StaffWorkstationPageState();
}

class _StaffWorkstationPageState extends ConsumerState<StaffWorkstationPage> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final appointmentsState = ref.watch(appointmentsViewProvider);
    final servicesState = ref.watch(servicesViewProvider);
    final productsState = ref.watch(retailProductsViewProvider);

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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            children: [
              _StaffHeader(
                isProcessing: _isProcessing,
                standalone: widget.standalone,
                servicesCount: servicesState.valueOrNull?.where((service) => service.isActive).length ?? 0,
                onClose: _closeWindow,
                onOpenBilling: _openBillingDesk,
                onOpenUpsell: _openUpsellDesk,
                onExportReceipt: _openReceiptDesk,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: servicesState.when(
                  data: (services) => productsState.when(
                    data: (products) => appointmentsState.when(
                      data: (appointments) => _StaffBody(
                        appointments: _filterTodayAppointments(appointments),
                        services: services.where((service) => service.isActive).toList(growable: false),
                        products: products
                            .where((product) => product.isActive && !product.isHiddenFromStaff)
                            .toList(growable: false),
                        isProcessing: _isProcessing,
                        onReceive: (appointment) => _updateStatus(appointment, 'Đã đặt'),
                        onStartService: (appointment) => _updateStatus(appointment, 'Đang làm'),
                        onComplete: (appointment) => _updateStatus(appointment, 'Hoàn thành'),
                        onUndoComplete: (appointment) => _updateStatus(appointment, 'Đang làm'),
                        onCancel: (appointment) => _updateStatus(appointment, 'Đã hủy'),
                        onCheckout: _checkoutAppointment,
                        onAddService: _addServiceForAppointment,
                        onAddProduct: _addProductForAppointment,
                      ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _StaffError(message: 'Không tải được bàn thao tác nhân viên: $error'),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _StaffError(message: 'Không tải được sản phẩm bán lẻ: $error'),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _StaffError(message: 'Không tải được dịch vụ đang hoạt động: $error'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.standalone) return Scaffold(body: content);
    return Dialog.fullscreen(backgroundColor: Colors.transparent, child: content);
  }

  Future<void> _closeWindow() async {
    if (widget.standalone) {
      await SystemNavigator.pop();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  List<AppointmentEntry> _filterTodayAppointments(List<AppointmentEntry> source) {
    final now = DateTime.now();
    final todayItems = source.where((item) {
      final startsAt = item.startsAt;
      final matchesDate = startsAt.year == now.year && startsAt.month == now.month && startsAt.day == now.day;
      return matchesDate || item.dateLabel == 'Hôm nay';
    }).toList(growable: false)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    if (todayItems.isNotEmpty) return todayItems;
    final fallback = List<AppointmentEntry>.from(source)..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return fallback.take(8).toList(growable: false);
  }

  Future<void> _updateStatus(AppointmentEntry appointment, String status) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(appointmentsRepositoryProvider).updateAppointmentStatus(appointment.id, status);
      ref.invalidate(appointmentsViewProvider);
      ref.invalidate(overviewSummaryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã cập nhật ${appointment.customerName} sang trạng thái $status')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _checkoutAppointment(AppointmentEntry appointment) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      await ref.read(invoicesRepositoryProvider).prefillDraftFromAppointment(appointment);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      }
      if (!mounted) return;
      if (!widget.standalone) await _closeWindow();
      messenger.showSnackBar(SnackBar(content: Text('Đã mở tính tiền cho ${appointment.customerName}')));
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

  void _openUpsellDesk() {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.standalone) {
      _openStandaloneBilling();
    } else {
      ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      _closeWindow();
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Mở bàn tính tiền để thêm dịch vụ/sản phẩm bán kèm cho khách.')),
    );
  }

  void _openReceiptDesk() {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.standalone) {
      _openStandaloneBilling();
    } else {
      ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      _closeWindow();
    }
    messenger.showSnackBar(const SnackBar(content: Text('Mở bàn tính tiền để xuất phiếu cho khách.')));
  }

  Future<void> _addServiceForAppointment(AppointmentEntry appointment, ServiceCatalogItem service) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(invoicesRepositoryProvider).prefillDraftFromAppointment(appointment);
      await ref.read(invoicesRepositoryProvider).addInvoiceService(service.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${service.name} cho ${appointment.customerName} vào bill.')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _addProductForAppointment(AppointmentEntry appointment, RetailProductItem product) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await ref.read(invoicesRepositoryProvider).prefillDraftFromAppointment(appointment);
      await ref.read(invoicesRepositoryProvider).addInvoiceProduct(product.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${product.name} cho ${appointment.customerName} vào bill.')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openStandaloneBilling() async {
    if (!widget.standalone || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Tính tiền (Staff)')),
          body: const Padding(padding: EdgeInsets.all(16), child: InvoicesPage()),
        ),
      ),
    );
  }
}

class _StaffHeader extends StatelessWidget {
  const _StaffHeader({
    required this.isProcessing,
    required this.standalone,
    required this.servicesCount,
    required this.onClose,
    required this.onOpenBilling,
    required this.onOpenUpsell,
    required this.onExportReceipt,
  });

  final bool isProcessing;
  final bool standalone;
  final int servicesCount;
  final VoidCallback onClose;
  final VoidCallback onOpenBilling;
  final VoidCallback onOpenUpsell;
  final VoidCallback onExportReceipt;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionCard(
      key: const Key('staff-premium-header'),
      child: PremiumPageHeader(
        icon: Icons.badge_outlined,
        eyebrow: 'Không gian thao tác',
        title: 'Bàn thao tác nhân viên',
        subtitle: 'Xử lý lịch hôm nay, dịch vụ phát sinh và tính tiền mà không rời luồng phục vụ.',
        trailing: [
          PremiumStatusPill(label: '$servicesCount dịch vụ mở', tone: AppColors.success),
          FilledButton.icon(
            onPressed: isProcessing ? null : onOpenBilling,
            icon: const Icon(Icons.point_of_sale_outlined),
            label: const Text('Tính tiền'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Thao tác khác',
            onSelected: (value) {
              if (value == 'receipt') onExportReceipt();
              if (value == 'upsell') onOpenUpsell();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'receipt', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('Xuất phiếu'))),
              PopupMenuItem(value: 'upsell', child: ListTile(leading: Icon(Icons.add_shopping_cart_outlined), title: Text('Bán thêm'))),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          IconButton(
            onPressed: isProcessing ? null : onClose,
            tooltip: standalone ? 'Đóng cửa sổ Staff' : 'Đóng bàn nhân viên',
            icon: const Icon(Icons.close_rounded),
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
  final ValueChanged<AppointmentEntry> onReceive;
  final ValueChanged<AppointmentEntry> onStartService;
  final ValueChanged<AppointmentEntry> onComplete;
  final ValueChanged<AppointmentEntry> onUndoComplete;
  final ValueChanged<AppointmentEntry> onCancel;
  final ValueChanged<AppointmentEntry> onCheckout;
  final Future<void> Function(AppointmentEntry appointment, ServiceCatalogItem service) onAddService;
  final Future<void> Function(AppointmentEntry appointment, RetailProductItem product) onAddProduct;

  @override
  Widget build(BuildContext context) {
    final waiting = appointments.where((item) => item.status == 'Chờ xác nhận').length;
    final active = appointments.where((item) => item.status == 'Đang làm').length;
    final completed = appointments.where((item) => item.status == 'Hoàn thành').length;

    return ListView(
      primary: false,
      key: const Key('staff-premium-workspace'),
      children: [
        _StaffStats(total: appointments.length, waiting: waiting, active: active, completed: completed),
        const SizedBox(height: 16),
        PremiumSectionCard(
          icon: Icons.view_timeline_outlined,
          title: 'Khách hôm nay',
          subtitle: appointments.isEmpty ? 'Chưa có lịch để thao tác' : '${appointments.length} lượt cần theo dõi',
          trailing: isProcessing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          child: appointments.isEmpty
              ? const PremiumEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Hôm nay chưa có lịch',
                  message: 'Lịch mới sẽ xuất hiện ở đây để nhân viên xử lý.',
                )
              : Column(
                  children: [
                    for (var index = 0; index < appointments.length; index++) ...[
                      _StaffAppointmentCard(
                        appointment: appointments[index],
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
                      ),
                      if (index < appointments.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StaffStats extends StatelessWidget {
  const _StaffStats({required this.total, required this.waiting, required this.active, required this.completed});

  final int total;
  final int waiting;
  final int active;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(icon: Icons.people_alt_outlined, label: 'Lượt hôm nay', value: '$total'),
      PremiumStatCard(icon: Icons.notifications_active_outlined, label: 'Chờ nhận khách', value: '$waiting', tone: AppColors.copper),
      PremiumStatCard(icon: Icons.content_cut_rounded, label: 'Đang phục vụ', value: '$active', tone: AppColors.warning),
      PremiumStatCard(icon: Icons.task_alt_outlined, label: 'Hoàn thành', value: '$completed', tone: AppColors.success),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080 ? 4 : constraints.maxWidth >= 600 ? 2 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: width, child: card)]);
      },
    );
  }
}

class _StaffAppointmentCard extends StatelessWidget {
  const _StaffAppointmentCard({
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
  final Future<void> Function(AppointmentEntry appointment, ServiceCatalogItem service) onAddService;
  final Future<void> Function(AppointmentEntry appointment, RetailProductItem product) onAddProduct;

  @override
  Widget build(BuildContext context) {
    final canReceive = appointment.status == 'Chờ xác nhận';
    final canStart = appointment.status == 'Chờ xác nhận' || appointment.status == 'Đã đặt';
    final canComplete = appointment.status == 'Đang làm' || appointment.status == 'Đã đặt';
    final canUndoComplete = appointment.status == 'Hoàn thành';
    final canCancel = appointment.status != 'Đã hủy';
    final canCheckout = appointment.status != 'Chờ xác nhận' && appointment.status != 'Đã hủy';
    final tone = _staffStatusTone(appointment.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: appointment.status == 'Đang làm' ? 0.36 : 0.16)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.iconSurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(appointment.timeLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(appointment.slotLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(appointment.customerName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16))),
                        PremiumStatusPill(label: appointment.status, tone: tone),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(appointment.servicesSummary, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 5),
                        Expanded(child: Text('${appointment.staffName} • ${appointment.durationLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.textMuted))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final primaryActions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canReceive)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => onReceive(appointment),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Nhận khách'),
                ),
              if (canStart)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => onStartService(appointment),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Bắt đầu dịch vụ'),
                ),
              if (canComplete)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => onComplete(appointment),
                  icon: const Icon(Icons.task_alt_outlined),
                  label: const Text('Hoàn thành'),
                ),
              if (canUndoComplete)
                OutlinedButton.icon(
                  onPressed: isProcessing ? null : () => onUndoComplete(appointment),
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Hoàn tác'),
                ),
              FilledButton.icon(
                onPressed: isProcessing || !canCheckout ? null : () => onCheckout(appointment),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Tính tiền'),
              ),
              PopupMenuButton<String>(
                enabled: !isProcessing,
                tooltip: 'Thêm vào bill / thao tác khác',
                onSelected: (value) async {
                  if (value == 'service') {
                    final service = await _openStaffServicePicker(context, services);
                    if (service != null) await onAddService(appointment, service);
                  } else if (value == 'product') {
                    final product = await _openStaffProductPicker(context, products);
                    if (product != null) await onAddProduct(appointment, product);
                  } else if (value == 'cancel' && canCancel) {
                    onCancel(appointment);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'service', child: ListTile(leading: Icon(Icons.add_business_outlined), title: Text('Thêm dịch vụ'))),
                  const PopupMenuItem(value: 'product', child: ListTile(leading: Icon(Icons.shopping_bag_outlined), title: Text('Thêm sản phẩm'))),
                  PopupMenuItem(
                    value: 'cancel',
                    enabled: canCancel,
                    child: const ListTile(leading: Icon(Icons.event_busy_outlined), title: Text('Hủy lịch')),
                  ),
                ],
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.controlBorder),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.more_horiz_rounded, size: 18), SizedBox(width: 5), Text('Khác')]),
                ),
              ),
            ],
          );

          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [identity, const SizedBox(height: 12), primaryActions]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(flex: 5, child: identity), const SizedBox(width: 16), Flexible(flex: 4, child: Align(alignment: Alignment.centerRight, child: primaryActions))]);
        },
      ),
    );
  }
}

Future<RetailProductItem?> _openStaffProductPicker(BuildContext context, List<RetailProductItem> products) {
  return showDialog<RetailProductItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Chọn sản phẩm thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: products.isEmpty
            ? const PremiumEmptyState(icon: Icons.inventory_2_outlined, title: 'Chưa có sản phẩm', message: 'Không có sản phẩm đang hiển thị cho nhân viên.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (context, index) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    leading: const PremiumIconBadge(icon: Icons.shopping_bag_outlined, size: 34),
                    onTap: () => Navigator.of(dialogContext).pop(product),
                    title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${product.productType}${product.brand.isEmpty ? '' : ' • ${product.brand}'}'),
                    trailing: Text(product.salePriceLabel, style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w800)),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Đóng'))],
    ),
  );
}

Future<ServiceCatalogItem?> _openStaffServicePicker(BuildContext context, List<ServiceCatalogItem> services) {
  return showDialog<ServiceCatalogItem>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Chọn dịch vụ thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: services.isEmpty
            ? const PremiumEmptyState(icon: Icons.content_cut_rounded, title: 'Chưa có dịch vụ', message: 'Không có dịch vụ đang hoạt động.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: services.length,
                separatorBuilder: (context, index) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final service = services[index];
                  return ListTile(
                    leading: const PremiumIconBadge(icon: Icons.content_cut_rounded, size: 34),
                    onTap: () => Navigator.of(dialogContext).pop(service),
                    title: Text(service.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${service.category} • ${service.durationLabel}'),
                    trailing: Text(service.priceLabel, style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w800)),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Đóng'))],
    ),
  );
}

class _StaffError extends StatelessWidget {
  const _StaffError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PremiumEmptyState(icon: Icons.error_outline_rounded, title: 'Không tải được dữ liệu', message: message);
  }
}

Color _staffStatusTone(String status) {
  if (status == 'Hoàn thành') return AppColors.success;
  if (status == 'Đã hủy') return AppColors.textMuted;
  if (status == 'Đang làm') return AppColors.warning;
  if (status == 'Đã đặt') return AppColors.info;
  return AppColors.copper;
}
