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
  const StaffWorkstationPage({super.key, this.standalone = false});

  final bool standalone;

  @override
  ConsumerState<StaffWorkstationPage> createState() =>
      _StaffWorkstationPageState();
}

class _StaffWorkstationPageState extends ConsumerState<StaffWorkstationPage> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final appointmentsState = ref.watch(appointmentsViewProvider);
    final servicesState = ref.watch(servicesViewProvider);
    final productsState = ref.watch(retailProductsViewProvider);
    final draftState = ref.watch(invoiceDraftProvider);
    final appointments = appointmentsState.valueOrNull ?? const <AppointmentEntry>[];
    final draftLabel = draftState.when(
      data: (draft) => _staffDraftLabel(draft, appointments),
      loading: () => 'Đang đọc bill…',
      error: (_, __) => 'Không đọc được bill hiện tại',
    );
    final hasActiveDraft = draftState.valueOrNull != null &&
        _staffHasDraftWork(draftState.valueOrNull!);

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
                draftLabel: draftLabel,
                hasActiveDraft: hasActiveDraft,
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
                      data: (items) => _StaffBody(
                        appointments: _filterTodayAppointments(items),
                        services: services
                            .where((service) => service.isActive)
                            .toList(growable: false),
                        products: products
                            .where(
                              (product) =>
                                  product.isActive &&
                                  !product.isHiddenFromStaff,
                            )
                            .toList(growable: false),
                        isProcessing: _isProcessing,
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
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _StaffError(
                        message: 'Không tải được bàn thao tác nhân viên: $error',
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _StaffError(
                      message: 'Không tải được sản phẩm bán lẻ: $error',
                    ),
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _StaffError(
                    message: 'Không tải được dịch vụ đang hoạt động: $error',
                  ),
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
    try {
      final draft = await _prepareDraftForAppointment(appointment);
      if (draft == null) return;
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      }
      if (!mounted) return;
      if (!widget.standalone) await _closeWindow();
      ScaffoldMessenger.of(context).showSnackBar(
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

  void _openUpsellDesk() {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.standalone) {
      _openStandaloneBilling();
    } else {
      ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
      _closeWindow();
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Mở bill hiện tại để thêm dịch vụ phát sinh hoặc sản phẩm bán kèm.',
        ),
      ),
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
    messenger.showSnackBar(
      const SnackBar(content: Text('Mở bàn tính tiền để xuất phiếu cho khách.')),
    );
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
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
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
        ref.read(desktopSectionProvider.notifier).state = DesktopSection.invoices;
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
    final appointments =
        ref.read(appointmentsViewProvider).valueOrNull ?? const <AppointmentEntry>[];
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
    required this.isProcessing,
    required this.standalone,
    required this.draftLabel,
    required this.hasActiveDraft,
    required this.onClose,
    required this.onOpenBilling,
    required this.onOpenUpsell,
    required this.onExportReceipt,
  });

  final bool isProcessing;
  final bool standalone;
  final String draftLabel;
  final bool hasActiveDraft;
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
        subtitle:
            'Xử lý lịch hôm nay, dịch vụ phát sinh và tính tiền mà không rời luồng phục vụ.',
        trailing: [
          PremiumStatusPill(
            label: draftLabel,
            tone: hasActiveDraft ? AppColors.warning : AppColors.success,
          ),
          FilledButton.icon(
            key: const Key('staff-open-billing'),
            onPressed: isProcessing ? null : onOpenBilling,
            icon: const Icon(Icons.point_of_sale_outlined),
            label: Text(hasActiveDraft ? 'Mở bill' : 'Tính tiền'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Thao tác khác',
            onSelected: (value) {
              if (value == 'receipt') onExportReceipt();
              if (value == 'upsell') onOpenUpsell();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'receipt',
                child: ListTile(
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Xuất phiếu'),
                ),
              ),
              PopupMenuItem(
                value: 'upsell',
                child: ListTile(
                  leading: Icon(Icons.add_shopping_cart_outlined),
                  title: Text('Bán thêm'),
                ),
              ),
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
    final waiting = appointments
        .where(
          (item) =>
              _staffOperationalState(item) ==
              _StaffOperationalState.waitingConfirmation,
        )
        .length;
    final active = appointments
        .where(
          (item) =>
              _staffOperationalState(item) == _StaffOperationalState.active,
        )
        .length;
    final completed = appointments
        .where(
          (item) =>
              _staffOperationalState(item) ==
                  _StaffOperationalState.awaitingPayment ||
              _staffOperationalState(item) == _StaffOperationalState.paid,
        )
        .length;

    return ListView(
      primary: false,
      key: const Key('staff-premium-workspace'),
      children: [
        _StaffStats(
          total: appointments.length,
          waiting: waiting,
          active: active,
          completed: completed,
        ),
        const SizedBox(height: 16),
        PremiumSectionCard(
          icon: Icons.view_timeline_outlined,
          title: 'Khách hôm nay',
          subtitle: appointments.isEmpty
              ? 'Chưa có lịch để thao tác'
              : '${appointments.length} lượt cần theo dõi',
          trailing: isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          child: appointments.isEmpty
              ? const PremiumEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Hôm nay chưa có lịch',
                  message: 'Lịch mới sẽ xuất hiện ở đây để nhân viên xử lý.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < appointments.length;
                      index++
                    ) ...[
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
                      if (index < appointments.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StaffStats extends StatelessWidget {
  const _StaffStats({
    required this.total,
    required this.waiting,
    required this.active,
    required this.completed,
  });

  final int total;
  final int waiting;
  final int active;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(
        icon: Icons.people_alt_outlined,
        label: 'Lượt hôm nay',
        value: '$total',
      ),
      PremiumStatCard(
        icon: Icons.notifications_active_outlined,
        label: 'Chờ xác nhận',
        value: '$waiting',
        tone: AppColors.copper,
      ),
      PremiumStatCard(
        icon: Icons.content_cut_rounded,
        label: 'Đang phục vụ',
        value: '$active',
        tone: AppColors.warning,
      ),
      PremiumStatCard(
        icon: Icons.task_alt_outlined,
        label: 'Hoàn thành',
        value: '$completed',
        tone: AppColors.success,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 600
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
    final paid = appointment.isPaid;
    final canReceive = !paid && appointment.status == 'Chờ xác nhận';
    final canStart = !paid &&
        (appointment.status == 'Chờ xác nhận' ||
            appointment.status == 'Đã đặt');
    final canComplete = !paid &&
        (appointment.status == 'Đang làm' || appointment.status == 'Đã đặt');
    final canUndoComplete = !paid && appointment.status == 'Hoàn thành';
    final canCancel = !paid && appointment.status != 'Đã hủy';
    final canCheckout = !paid &&
        appointment.status != 'Chờ xác nhận' &&
        appointment.status != 'Đã hủy';
    final displayStatus = _staffOperationalLabel(appointment);
    final tone = _staffOperationalTone(appointment);

    return Container(
      key: Key('staff-appointment-${appointment.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: tone.withValues(
            alpha: appointment.status == 'Đang làm' ? 0.36 : 0.16,
          ),
        ),
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
                    Text(
                      appointment.timeLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appointment.slotLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                      ),
                    ),
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
                        Expanded(
                          child: Text(
                            appointment.customerName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontSize: 16),
                          ),
                        ),
                        PremiumStatusPill(label: displayStatus, tone: tone),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      appointment.servicesSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${appointment.staffName} • ${appointment.durationLabel}',
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
                  label: const Text('Xác nhận lịch'),
                ),
              if (canStart)
                OutlinedButton.icon(
                  onPressed: isProcessing
                      ? null
                      : () => onStartService(appointment),
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
                  onPressed: isProcessing
                      ? null
                      : () => onUndoComplete(appointment),
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Hoàn tác'),
                ),
              if (paid)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Đã thu'),
                )
              else
                FilledButton.icon(
                  key: Key('staff-checkout-${appointment.id}'),
                  onPressed: isProcessing || !canCheckout
                      ? null
                      : () => onCheckout(appointment),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Tính tiền'),
                ),
              if (!paid)
                PopupMenuButton<String>(
                  key: Key('staff-actions-${appointment.id}'),
                  enabled: !isProcessing,
                  tooltip: 'Thêm vào bill / thao tác khác',
                  onSelected: (value) async {
                    if (value == 'service') {
                      final service =
                          await _openStaffServicePicker(context, services);
                      if (service != null) {
                        await onAddService(appointment, service);
                      }
                    } else if (value == 'product') {
                      final product =
                          await _openStaffProductPicker(context, products);
                      if (product != null) {
                        await onAddProduct(appointment, product);
                      }
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
                    PopupMenuItem(
                      value: 'cancel',
                      enabled: canCancel,
                      child: const ListTile(
                        leading: Icon(Icons.event_busy_outlined),
                        title: Text('Hủy lịch'),
                      ),
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz_rounded, size: 18),
                        SizedBox(width: 5),
                        Text('Khác'),
                      ],
                    ),
                  ),
                ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 12), primaryActions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: 16),
              Flexible(
                flex: 4,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: primaryActions,
                ),
              ),
            ],
          );
        },
      ),
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
                separatorBuilder: (context, index) =>
                    const PremiumDivider(indent: 44),
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
                separatorBuilder: (context, index) =>
                    const PremiumDivider(indent: 44),
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
      return AppColors.warning;
    case _StaffOperationalState.booked:
      return AppColors.info;
    case _StaffOperationalState.canceled:
      return AppColors.textMuted;
    case _StaffOperationalState.waitingConfirmation:
    case _StaffOperationalState.other:
      return AppColors.copper;
  }
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

bool _staffHasDraftWork(InvoiceDraft draft) => draft.lines.isNotEmpty;

String _staffDraftLabel(
  InvoiceDraft draft,
  List<AppointmentEntry> appointments,
) {
  if (!_staffHasDraftWork(draft)) return 'Chưa có bill đang làm';
  final owner = _staffDraftOwner(draft, appointments);
  final total = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  ).format(draft.totalAmount).replaceAll(',', '.');
  return 'Bill: $owner • $total';
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

String _friendlyInvoiceError(StateError error, String customerName) {
  final message = error.message.toString();
  if (message.contains('Bill đang làm đã có dữ liệu')) {
    return 'Đang có bill khác chưa hoàn tất. Hãy mở bill hiện tại để hoàn tất hoặc xóa bill trước khi tính tiền cho $customerName.';
  }
  return message;
}
