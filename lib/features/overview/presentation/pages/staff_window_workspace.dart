import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';
import '../../../invoices/presentation/pages/invoices_page.dart';
import 'staff_workstation_page.dart';

final RouteObserver<PageRoute<dynamic>> staffWindowRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class StaffWindowWorkspace extends ConsumerStatefulWidget {
  const StaffWindowWorkspace({super.key});

  @override
  ConsumerState<StaffWindowWorkspace> createState() =>
      _StaffWindowWorkspaceState();
}

class _StaffWindowWorkspaceState extends ConsumerState<StaffWindowWorkspace>
    with RouteAware {
  static const _pollInterval = Duration(seconds: 12);

  Timer? _refreshTimer;
  PageRoute<dynamic>? _subscribedRoute;
  bool _isRailProcessing = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted || _isRailProcessing) return;
      _refreshWorkspace();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _subscribedRoute)) {
      return;
    }
    if (_subscribedRoute != null) {
      staffWindowRouteObserver.unsubscribe(this);
    }
    _subscribedRoute = route;
    staffWindowRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() {
    _refreshWorkspace();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    staffWindowRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsState = ref.watch(appointmentsViewProvider);
    final servicesState = ref.watch(servicesViewProvider);
    final productsState = ref.watch(retailProductsViewProvider);
    final draftState = ref.watch(invoiceDraftProvider);

    final appointments = appointmentsState.valueOrNull ??
        const <AppointmentEntry>[];
    final services = (servicesState.valueOrNull ??
            const <ServiceCatalogItem>[])
        .where((service) => service.isActive)
        .toList(growable: false);
    final products = (productsState.valueOrNull ??
            const <RetailProductItem>[])
        .where((product) => product.isActive && !product.isHiddenFromStaff)
        .toList(growable: false);
    final draft = draftState.valueOrNull;

    final rail = _StaffQuickRail(
      appointments: _todayAppointments(appointments),
      services: services,
      products: products,
      draft: draft,
      isProcessing: _isRailProcessing,
      servicesLoading: servicesState.isLoading,
      productsLoading: productsState.isLoading,
      onRefresh: () {
        _refreshWorkspace();
        _notify('Đã làm mới dữ liệu Bàn nhân viên.');
      },
      onReminderAction: _handleReminderAction,
      onQuickService: _addServiceToActiveBill,
      onQuickProduct: _addProductToActiveBill,
      onPickService: () => _pickService(services),
      onPickProduct: () => _pickProduct(products),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          unawaited(_openBilling());
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: AppColors.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1280) {
                return Stack(
                  children: [
                    const Positioned.fill(
                      child: StaffWorkstationPage(standalone: true),
                    ),
                    Positioned(
                      right: 18,
                      bottom: 18,
                      child: FilledButton.icon(
                        key: const Key('staff-quick-rail-open'),
                        onPressed: () => _openCompactRail(rail),
                        icon: const Icon(Icons.bolt_outlined, size: 18),
                        label: const Text('Thao tác nhanh'),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  const Expanded(
                    child: StaffWorkstationPage(standalone: true),
                  ),
                  SizedBox(
                    width: 372,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 16, 20),
                      child: rail,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openCompactRail(Widget rail) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: rail,
          ),
        ),
      ),
    );
  }

  void _refreshWorkspace() {
    ref.invalidate(appointmentsViewProvider);
    ref.invalidate(servicesViewProvider);
    ref.invalidate(retailProductsViewProvider);
    ref.invalidate(invoiceDraftProvider);
    ref.invalidate(overviewSummaryProvider);
  }

  Future<void> _handleReminderAction(AppointmentEntry appointment) async {
    if (_isRailProcessing || appointment.isPaid) return;
    final state = _quickState(appointment);

    if (state == _QuickState.awaitingPayment) {
      await _checkoutAppointment(appointment);
      return;
    }

    final nextStatus = switch (state) {
      _QuickState.waitingConfirmation => 'Đã đặt',
      _QuickState.booked => 'Đang làm',
      _QuickState.active => 'Hoàn thành',
      _ => null,
    };
    if (nextStatus == null) return;

    setState(() => _isRailProcessing = true);
    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .updateAppointmentStatus(appointment.id, nextStatus);
      _refreshWorkspace();
      _notify('Đã cập nhật ${appointment.customerName} sang $nextStatus.');
    } on StateError catch (error) {
      await _showBusinessError(error.message.toString());
    } finally {
      if (mounted) setState(() => _isRailProcessing = false);
    }
  }

  Future<void> _checkoutAppointment(AppointmentEntry appointment) async {
    if (_isRailProcessing || appointment.isPaid) return;
    setState(() => _isRailProcessing = true);
    try {
      final draft = await _prepareDraftForAppointment(appointment);
      if (draft == null) return;
      await _openBilling();
    } on StateError catch (error) {
      await _showBusinessError(_friendlyInvoiceError(error));
    } finally {
      if (mounted) setState(() => _isRailProcessing = false);
    }
  }

  Future<InvoiceDraft?> _prepareDraftForAppointment(
    AppointmentEntry appointment,
  ) async {
    final repository = ref.read(invoicesRepositoryProvider);
    final draft = await repository.fetchInvoiceDraft();

    if (!_hasDraftWork(draft)) {
      final prepared = await repository.prefillDraftFromAppointment(appointment);
      _refreshWorkspace();
      return prepared;
    }
    if (draft.appointmentId == appointment.id) return draft;

    final canReuseCustomer = draft.lines.isEmpty &&
        draft.appointmentId == null &&
        draft.customerId == appointment.customerId;
    if (canReuseCustomer) {
      final prepared = await repository.prefillDraftFromAppointment(appointment);
      _refreshWorkspace();
      return prepared;
    }

    final appointments = ref.read(appointmentsViewProvider).valueOrNull ??
        const <AppointmentEntry>[];
    final owner = _draftOwner(draft, appointments);
    if (!mounted) return null;
    final openCurrent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đang có bill chưa hoàn tất'),
        content: Text(
          owner == 'Khách đã chọn'
              ? 'Bill hiện tại đang có dữ liệu. Hãy hoàn tất hoặc xóa bill trước khi tính tiền cho ${appointment.customerName}.'
              : 'Bill hiện tại đang thuộc $owner. Hãy hoàn tất hoặc xóa bill đó trước khi tính tiền cho ${appointment.customerName}.',
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
    if (openCurrent == true && mounted) await _openBilling();
    return null;
  }

  Future<void> _addServiceToActiveBill(ServiceCatalogItem service) async {
    if (_isRailProcessing) return;
    setState(() => _isRailProcessing = true);
    try {
      final repository = ref.read(invoicesRepositoryProvider);
      final draft = await repository.fetchInvoiceDraft();
      if (!await _canUseQuickDraft(draft)) return;
      await repository.addInvoiceService(service.id);
      _refreshWorkspace();
      _notify('Đã thêm phát sinh ${service.name} vào bill đang làm.');
    } on StateError catch (error) {
      await _showBusinessError(_friendlyInvoiceError(error));
    } finally {
      if (mounted) setState(() => _isRailProcessing = false);
    }
  }

  Future<void> _addProductToActiveBill(RetailProductItem product) async {
    if (_isRailProcessing) return;
    setState(() => _isRailProcessing = true);
    try {
      final repository = ref.read(invoicesRepositoryProvider);
      final draft = await repository.fetchInvoiceDraft();
      if (!await _canUseQuickDraft(draft)) return;
      await repository.addInvoiceProduct(product.id);
      _refreshWorkspace();
      _notify('Đã thêm ${product.name} vào bill đang làm.');
    } on StateError catch (error) {
      await _showBusinessError(_friendlyInvoiceError(error));
    } finally {
      if (mounted) setState(() => _isRailProcessing = false);
    }
  }

  Future<bool> _canUseQuickDraft(InvoiceDraft draft) async {
    if (!_hasDraftWork(draft)) {
      await _showBusinessError(
        'Chưa có bill đang làm. Hãy chọn Tính tiền ở một khách trước khi thêm nhanh dịch vụ hoặc sản phẩm.',
      );
      return false;
    }

    final appointmentId = draft.appointmentId;
    if (appointmentId != null && appointmentId.isNotEmpty) {
      final appointments = ref.read(appointmentsViewProvider).valueOrNull ??
          const <AppointmentEntry>[];
      for (final appointment in appointments) {
        if (appointment.id == appointmentId && appointment.isPaid) {
          await _showBusinessError(
            'Lịch của bill này đã thanh toán. Không thể thêm phát sinh từ Bàn nhân viên.',
          );
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _pickService(List<ServiceCatalogItem> services) async {
    if (!mounted) return;
    final selected = await showDialog<ServiceCatalogItem>(
      context: context,
      builder: (_) => _ServicePickerDialog(services: services),
    );
    if (selected != null) await _addServiceToActiveBill(selected);
  }

  Future<void> _pickProduct(List<RetailProductItem> products) async {
    if (!mounted) return;
    final selected = await showDialog<RetailProductItem>(
      context: context,
      builder: (_) => _ProductPickerDialog(products: products),
    );
    if (selected != null) await _addProductToActiveBill(selected);
  }

  Future<void> _openBilling() async {
    if (!mounted) return;
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
    if (mounted) _refreshWorkspace();
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

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _StaffQuickRail extends StatelessWidget {
  const _StaffQuickRail({
    required this.appointments,
    required this.services,
    required this.products,
    required this.draft,
    required this.isProcessing,
    required this.servicesLoading,
    required this.productsLoading,
    required this.onRefresh,
    required this.onReminderAction,
    required this.onQuickService,
    required this.onQuickProduct,
    required this.onPickService,
    required this.onPickProduct,
  });

  final List<AppointmentEntry> appointments;
  final List<ServiceCatalogItem> services;
  final List<RetailProductItem> products;
  final InvoiceDraft? draft;
  final bool isProcessing;
  final bool servicesLoading;
  final bool productsLoading;
  final VoidCallback onRefresh;
  final ValueChanged<AppointmentEntry> onReminderAction;
  final ValueChanged<ServiceCatalogItem> onQuickService;
  final ValueChanged<RetailProductItem> onQuickProduct;
  final VoidCallback onPickService;
  final VoidCallback onPickProduct;

  @override
  Widget build(BuildContext context) {
    final reminders = _buildReminders(appointments, DateTime.now())
        .take(3)
        .toList(growable: false);
    final currentDraft = draft;
    final quickBillReady =
        currentDraft != null && _hasDraftWork(currentDraft);

    return Container(
      key: const Key('staff-quick-rail'),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                PremiumIconBadge(
                  icon: Icons.bolt_outlined,
                  size: 34,
                  tone: AppColors.copper,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Thao tác nhanh',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tự làm mới dữ liệu định kỳ',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('staff-rail-refresh'),
                  onPressed: isProcessing ? null : onRefresh,
                  tooltip: 'Làm mới ngay',
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          ),
          const PremiumDivider(),
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.all(12),
              children: [
                _RailSection(
                  key: const Key('staff-reminder-rail'),
                  icon: Icons.notifications_active_outlined,
                  title: 'Nhắc xử lý',
                  trailing: Text('${reminders.length}'),
                  child: reminders.isEmpty
                      ? const _RailEmpty(
                          text: 'Không có việc cần nhắc ngay lúc này.',
                        )
                      : Column(
                          children: [
                            for (var index = 0;
                                index < reminders.length;
                                index++) ...[
                              _ReminderRow(
                                reminder: reminders[index],
                                isProcessing: isProcessing,
                                onAction: () => onReminderAction(
                                  reminders[index].appointment,
                                ),
                              ),
                              if (index != reminders.length - 1)
                                const PremiumDivider(),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _RailSection(
                  key: const Key('staff-service-rail'),
                  icon: Icons.auto_awesome_outlined,
                  title: 'Dịch vụ phát sinh nhanh',
                  trailing: TextButton(
                    key: const Key('staff-rail-services-more'),
                    onPressed: isProcessing ? null : onPickService,
                    child: const Text('Xem tất cả'),
                  ),
                  child: _QuickCatalogGrid<ServiceCatalogItem>(
                    items: services.take(6).toList(growable: false),
                    loading: servicesLoading,
                    billReady: quickBillReady,
                    emptyLabel: 'Chưa có dịch vụ đang hoạt động.',
                    billHint:
                        'Tính tiền một khách trước để thêm phát sinh nhanh.',
                    itemBuilder: (context, service, enabled) => _QuickCatalogTile(
                      key: Key('staff-quick-service-${service.id}'),
                      icon: Icons.content_cut_rounded,
                      title: service.name,
                      subtitle: service.priceLabel,
                      enabled: enabled && !isProcessing,
                      tooltip: 'Thêm phát sinh vào bill',
                      onTap: () => onQuickService(service),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _RailSection(
                  key: const Key('staff-product-rail'),
                  icon: Icons.shopping_bag_outlined,
                  title: 'Sản phẩm bán kèm',
                  trailing: TextButton(
                    key: const Key('staff-rail-products-more'),
                    onPressed: isProcessing ? null : onPickProduct,
                    child: const Text('Xem tất cả'),
                  ),
                  child: _QuickCatalogGrid<RetailProductItem>(
                    items: products.take(6).toList(growable: false),
                    loading: productsLoading,
                    billReady: quickBillReady,
                    emptyLabel: 'Chưa có sản phẩm hiển thị cho nhân viên.',
                    billHint: 'Tính tiền một khách trước để thêm sản phẩm nhanh.',
                    itemBuilder: (context, product, enabled) => _QuickCatalogTile(
                      key: Key('staff-quick-product-${product.id}'),
                      icon: Icons.inventory_2_outlined,
                      title: product.name,
                      subtitle: product.salePriceLabel,
                      enabled: enabled && !isProcessing,
                      tooltip: 'Thêm sản phẩm vào bill',
                      onTap: () => onQuickProduct(product),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ctrl+B · mở khu tính tiền',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
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

class _RailSection extends StatelessWidget {
  const _RailSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.copper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const PremiumDivider(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _RailEmpty extends StatelessWidget {
  const _RailEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.isProcessing,
    required this.onAction,
  });

  final _StaffReminder reminder;
  final bool isProcessing;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: reminder.tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.appointment.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reminder.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: isProcessing ? null : onAction,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              reminder.actionLabel,
              style: const TextStyle(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCatalogGrid<T> extends StatelessWidget {
  const _QuickCatalogGrid({
    required this.items,
    required this.loading,
    required this.billReady,
    required this.emptyLabel,
    required this.billHint,
    required this.itemBuilder,
  });

  final List<T> items;
  final bool loading;
  final bool billReady;
  final String emptyLabel;
  final String billHint;
  final Widget Function(BuildContext context, T item, bool enabled) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (items.isEmpty) return _RailEmpty(text: emptyLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!billReady) ...[
          Text(
            billHint,
            style: TextStyle(
              color: AppColors.warning,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in items)
                  SizedBox(
                    width: tileWidth,
                    child: itemBuilder(context, item, billReady),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickCatalogTile extends StatelessWidget {
  const _QuickCatalogTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? tooltip : 'Cần có bill đang làm',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.controlBorder),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: enabled ? AppColors.copper : AppColors.textMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textMuted,
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

class _ServicePickerDialog extends StatefulWidget {
  const _ServicePickerDialog({required this.services});

  final List<ServiceCatalogItem> services;

  @override
  State<_ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<_ServicePickerDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.services.where((service) {
      if (query.isEmpty) return true;
      return service.name.toLowerCase().contains(query) ||
          service.category.toLowerCase().contains(query);
    }).toList(growable: false);

    return AlertDialog(
      key: const Key('staff-service-picker-dialog'),
      title: const Text('Thêm phát sinh vào bill'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TextField(
              key: const Key('staff-service-picker-search'),
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Tìm tên hoặc nhóm dịch vụ',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const PremiumEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Không tìm thấy dịch vụ',
                      message: 'Thử từ khóa khác.',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const PremiumDivider(indent: 44),
                      itemBuilder: (context, index) {
                        final service = filtered[index];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(service),
                          leading: const PremiumIconBadge(
                            icon: Icons.content_cut_rounded,
                            size: 34,
                          ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});

  final List<RetailProductItem> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.products.where((product) {
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.productType.toLowerCase().contains(query);
    }).toList(growable: false);

    return AlertDialog(
      key: const Key('staff-product-picker-dialog'),
      title: const Text('Thêm sản phẩm vào bill'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TextField(
              key: const Key('staff-product-picker-search'),
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Tìm tên, loại hoặc thương hiệu',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const PremiumEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Không tìm thấy sản phẩm',
                      message: 'Thử từ khóa khác.',
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const PremiumDivider(indent: 44),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return ListTile(
                          onTap: () => Navigator.of(context).pop(product),
                          leading: const PremiumIconBadge(
                            icon: Icons.shopping_bag_outlined,
                            size: 34,
                          ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

enum _QuickState {
  waitingConfirmation,
  booked,
  active,
  awaitingPayment,
  paid,
  canceled,
  other,
}

class _StaffReminder {
  const _StaffReminder({
    required this.appointment,
    required this.message,
    required this.actionLabel,
    required this.tone,
    required this.priority,
  });

  final AppointmentEntry appointment;
  final String message;
  final String actionLabel;
  final Color tone;
  final int priority;
}

List<AppointmentEntry> _todayAppointments(List<AppointmentEntry> source) {
  final now = DateTime.now();
  return source.where((appointment) {
    final start = appointment.startsAt;
    return start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
  }).toList(growable: false);
}

List<_StaffReminder> _buildReminders(
  List<AppointmentEntry> appointments,
  DateTime now,
) {
  final reminders = <_StaffReminder>[];
  for (final appointment in appointments) {
    final state = _quickState(appointment);
    if (state == _QuickState.paid ||
        state == _QuickState.canceled ||
        state == _QuickState.other) {
      continue;
    }

    final start = appointment.startsAt;
    final end = start.add(Duration(minutes: appointment.durationMinutes));
    final minutesUntil = start.difference(now).inMinutes;

    switch (state) {
      case _QuickState.awaitingPayment:
        reminders.add(
          _StaffReminder(
            appointment: appointment,
            message: 'Đã xong dịch vụ · chờ thu',
            actionLabel: 'Tính tiền',
            tone: AppColors.warning,
            priority: 0,
          ),
        );
        break;
      case _QuickState.waitingConfirmation:
        if (minutesUntil > 30) break;
        final overdue = now.isAfter(start) ? now.difference(start).inMinutes : 0;
        reminders.add(
          _StaffReminder(
            appointment: appointment,
            message: overdue > 0
                ? 'Quá giờ xác nhận $overdue phút'
                : 'Còn ${minutesUntil < 1 ? 1 : minutesUntil} phút · chờ xác nhận',
            actionLabel: 'Xác nhận',
            tone: AppColors.copper,
            priority: 1,
          ),
        );
        break;
      case _QuickState.active:
        final overdue = now.isAfter(end) ? now.difference(end).inMinutes : 0;
        reminders.add(
          _StaffReminder(
            appointment: appointment,
            message: overdue > 0
                ? 'Đang làm · quá giờ $overdue phút'
                : 'Đang trong khung phục vụ',
            actionLabel: 'Hoàn thành',
            tone: overdue > 0 ? AppColors.warning : AppColors.success,
            priority: 2,
          ),
        );
        break;
      case _QuickState.booked:
        if (minutesUntil > 30) break;
        final overdue = now.isAfter(start) ? now.difference(start).inMinutes : 0;
        reminders.add(
          _StaffReminder(
            appointment: appointment,
            message: overdue > 0
                ? 'Đã tới giờ $overdue phút · chưa bắt đầu'
                : 'Còn ${minutesUntil < 1 ? 1 : minutesUntil} phút · đã đặt',
            actionLabel: 'Bắt đầu',
            tone: overdue > 0 ? AppColors.warning : AppColors.info,
            priority: 3,
          ),
        );
        break;
      case _QuickState.paid:
      case _QuickState.canceled:
      case _QuickState.other:
        break;
    }
  }

  reminders.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;
    return a.appointment.startsAt.compareTo(b.appointment.startsAt);
  });
  return reminders;
}

_QuickState _quickState(AppointmentEntry appointment) {
  if (appointment.isPaid) return _QuickState.paid;
  if (appointment.status == 'Hoàn thành') return _QuickState.awaitingPayment;
  if (appointment.status == 'Chờ xác nhận') {
    return _QuickState.waitingConfirmation;
  }
  if (appointment.status == 'Đã đặt') return _QuickState.booked;
  if (appointment.status == 'Đang làm') return _QuickState.active;
  if (appointment.status == 'Đã hủy') return _QuickState.canceled;
  return _QuickState.other;
}

bool _hasDraftWork(InvoiceDraft draft) {
  return draft.lines.isNotEmpty ||
      draft.customerId.trim().isNotEmpty ||
      (draft.appointmentId?.trim().isNotEmpty ?? false);
}

String _draftOwner(
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

String _friendlyInvoiceError(StateError error) {
  final message = error.message.toString();
  if (message.contains('Bill đang làm đã có dữ liệu')) {
    return 'Đang có bill khác chưa hoàn tất. Hãy mở bill hiện tại để hoàn tất hoặc xóa bill trước khi tiếp tục.';
  }
  return message;
}
