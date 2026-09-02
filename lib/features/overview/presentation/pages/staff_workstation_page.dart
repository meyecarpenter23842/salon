import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/navigation/desktop_navigation.dart';
import '../../../../core/models/appointment_entry.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
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

    final content = Container(
      color: Colors.transparent,
      child: Container(
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
                  servicesCount:
                      servicesState.valueOrNull
                          ?.where((service) => service.isActive)
                          .length ??
                      0,
                  onClose: _closeWindow,
                  onOpenBilling: _openBillingDesk,
                  onOpenUpsell: _openUpsellDesk,
                  onExportReceipt: _openReceiptDesk,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: servicesState.when(
                    data: (services) => productsState.when(
                      data: (products) => appointmentsState.when(
                        data: (appointments) => _StaffBody(
                          appointments: _filterTodayAppointments(appointments),
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
                        error: (error, stackTrace) => Center(
                          child: Text(
                            'Không tải được bàn thao tác nhân viên: $error',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        ),
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) => Center(
                        child: Text(
                          'Không tải được sản phẩm bán lẻ: $error',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stackTrace) => Center(
                      child: Text(
                        'Không tải được dịch vụ đang hoạt động: $error',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.standalone) {
      return Scaffold(body: content);
    }

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
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  List<AppointmentEntry> _filterTodayAppointments(
    List<AppointmentEntry> source,
  ) {
    final now = DateTime.now();
    final todayItems =
        source
            .where((item) {
              final startsAt = item.startsAt;
              final matchesDate =
                  startsAt.year == now.year &&
                  startsAt.month == now.month &&
                  startsAt.day == now.day;
              return matchesDate || item.dateLabel == 'Hôm nay';
            })
            .toList(growable: false)
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    if (todayItems.isNotEmpty) {
      return todayItems;
    }

    final fallback = List<AppointmentEntry>.from(source)
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return fallback.take(8).toList(growable: false);
  }

  Future<void> _updateStatus(
    AppointmentEntry appointment,
    String status,
  ) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await ref
          .read(appointmentsRepositoryProvider)
          .updateAppointmentStatus(appointment.id, status);
      ref.invalidate(appointmentsViewProvider);
      ref.invalidate(overviewSummaryProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã cập nhật ${appointment.customerName} sang trạng thái $status',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _checkoutAppointment(AppointmentEntry appointment) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final messenger = ScaffoldMessenger.of(context);
      await ref
          .read(invoicesRepositoryProvider)
          .prefillDraftFromAppointment(appointment);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }

      if (!mounted) {
        return;
      }

      if (!widget.standalone) {
        await _closeWindow();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã mở tính tiền cho ${appointment.customerName}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
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
          'Mở bàn tính tiền để thêm dịch vụ/sản phẩm bán kèm cho khách.',
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
      const SnackBar(
        content: Text('Mở bàn tính tiền để xuất phiếu cho khách.'),
      ),
    );
  }

  Future<void> _addServiceForAppointment(
    AppointmentEntry appointment,
    ServiceCatalogItem service,
  ) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await ref
          .read(invoicesRepositoryProvider)
          .prefillDraftFromAppointment(appointment);
      await ref.read(invoicesRepositoryProvider).addInvoiceService(service.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm ${service.name} cho ${appointment.customerName} vào bill.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _addProductForAppointment(
    AppointmentEntry appointment,
    RetailProductItem product,
  ) async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await ref
          .read(invoicesRepositoryProvider)
          .prefillDraftFromAppointment(appointment);
      await ref.read(invoicesRepositoryProvider).addInvoiceProduct(product.id);
      ref.invalidate(invoiceDraftProvider);
      if (widget.standalone) {
        await _openStandaloneBilling();
      } else {
        ref.read(desktopSectionProvider.notifier).state =
            DesktopSection.invoices;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm ${product.name} cho ${appointment.customerName} vào bill.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _openStandaloneBilling() async {
    if (!widget.standalone || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.topBarAccent,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.luxuryShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bàn thao tác nhân viên',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Màn thao tác riêng cho nhân viên, dữ liệu đồng bộ chung với cửa sổ Owner.',
                      style: TextStyle(color: AppColors.textMuted, height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dịch vụ đang mở bán: $servicesCount',
                      style: TextStyle(
                        color: AppColors.copper,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: isProcessing ? null : onClose,
                icon: const Icon(Icons.close),
                label: Text(
                  standalone ? 'Đóng cửa sổ Staff' : 'Đóng bàn nhân viên',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: isProcessing ? null : onOpenBilling,
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Tính tiền nhanh'),
              ),
              OutlinedButton.icon(
                onPressed: isProcessing ? null : onExportReceipt,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Xuất phiếu'),
              ),
              OutlinedButton.icon(
                onPressed: isProcessing ? null : onOpenUpsell,
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Bán thêm'),
              ),
            ],
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
  )
  onAddService;
  final Future<void> Function(
    AppointmentEntry appointment,
    RetailProductItem product,
  )
  onAddProduct;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Text(
          'Hôm nay chưa có lịch để thao tác.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return ListView.separated(
      itemCount: appointments.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final appointment = appointments[index];
        final canReceive = appointment.status == 'Chờ xác nhận';
        final canStart =
            appointment.status == 'Chờ xác nhận' ||
            appointment.status == 'Đã đặt';
        final canComplete =
            appointment.status == 'Đang làm' || appointment.status == 'Đã đặt';
        final canUndoComplete = appointment.status == 'Hoàn thành';
        final canCancel = appointment.status != 'Đã hủy';
        final canCheckout =
            appointment.status != 'Chờ xác nhận' &&
            appointment.status != 'Đã hủy';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.panelRaised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${appointment.timeLabel} - ${appointment.customerName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _StatusChip(status: appointment.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${appointment.servicesSummary} - ${appointment.staffName}',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isProcessing || !canReceive
                        ? null
                        : () => onReceive(appointment),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: const Text('Nhận khách'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing || !canStart
                        ? null
                        : () => onStartService(appointment),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Bắt đầu dịch vụ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing || !canComplete
                        ? null
                        : () => onComplete(appointment),
                    icon: const Icon(Icons.task_alt_outlined),
                    label: const Text('Hoàn thành hẹn'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing || !canUndoComplete
                        ? null
                        : () => onUndoComplete(appointment),
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Hoàn tác hoàn thành'),
                  ),
                  FilledButton.icon(
                    onPressed: isProcessing || !canCheckout
                        ? null
                        : () => onCheckout(appointment),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Tính tiền'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing || !canCancel
                        ? null
                        : () => onCancel(appointment),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('Hủy lịch'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () async {
                            final service = await _openStaffServicePicker(
                              context,
                              services,
                            );
                            if (service == null) {
                              return;
                            }
                            await onAddService(appointment, service);
                          },
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Thêm dịch vụ'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isProcessing
                        ? null
                        : () async {
                            final product = await _openStaffProductPicker(
                              context,
                              products,
                            );
                            if (product == null) {
                              return;
                            }
                            await onAddProduct(appointment, product);
                          },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Thêm sản phẩm'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
      backgroundColor: AppColors.panel,
      title: const Text('Chọn sản phẩm thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: products.isEmpty
            ? const Center(
                child: Text('Chưa có sản phẩm hiển thị cho nhân viên.'),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    onTap: () => Navigator.of(dialogContext).pop(product),
                    title: Text(product.name),
                    subtitle: Text('${product.productType} - ${product.brand}'),
                    trailing: Text(
                      product.salePriceLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
      backgroundColor: AppColors.panel,
      title: const Text('Chọn dịch vụ thêm vào bill'),
      content: SizedBox(
        width: 520,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: services.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final service = services[index];
            return ListTile(
              onTap: () => Navigator.of(dialogContext).pop(service),
              title: Text(service.name),
              subtitle: Text('${service.category} - ${service.durationLabel}'),
              trailing: Text(
                service.priceLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final Color tone;
    if (status == 'Hoàn thành') {
      tone = AppColors.success;
    } else if (status == 'Đã hủy') {
      tone = AppColors.textMuted;
    } else if (status == 'Đang làm') {
      tone = AppColors.warning;
    } else {
      tone = AppColors.copper;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
