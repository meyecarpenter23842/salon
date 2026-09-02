import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/invoice_draft_line.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/retail_product_upsert_input.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final invoiceCustomerQueryProvider = StateProvider<String>((ref) => '');

final invoiceFilteredCustomersProvider = FutureProvider<List<CustomerProfile>>((ref) {
  ref.watch(customersRefreshProvider);
  final query = ref.watch(invoiceCustomerQueryProvider).trim();
  return ref.watch(customersRepositoryProvider).fetchCustomersView(query: query.isEmpty ? null : query);
});

Future<void> _selectInvoiceCustomer(BuildContext context, WidgetRef ref, CustomerProfile customer) async {
  await ref.read(invoicesRepositoryProvider).selectInvoiceCustomer(customer.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã chọn khách ${customer.fullName} cho hóa đơn')),
  );
}

Future<void> _updateInvoicePaymentMethod(BuildContext context, WidgetRef ref, String paymentMethod) async {
  await ref.read(invoicesRepositoryProvider).updateInvoicePaymentMethod(paymentMethod);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
}

Future<void> _openDiscountEditor(BuildContext context, WidgetRef ref, InvoiceDraft draft) async {
  final discount = await showAppDialog<int>(
    context: context,
    builder: (_) => _InvoiceDiscountDialog(
      currentDiscount: draft.discountAmount,
      maxDiscount: draft.subtotal,
    ),
  );
  if (discount == null || !context.mounted) return;
  await ref.read(invoicesRepositoryProvider).updateInvoiceDiscount(discount);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã cập nhật giảm giá ${_currency(discount)}')),
  );
}

Future<void> _openInvoiceServicePicker(BuildContext context, WidgetRef ref, InvoiceDraft draft) async {
  final services = await ref.read(servicesRepositoryProvider).fetchServicesView();
  if (!context.mounted) return;
  final selected = await showAppDialog<ServiceCatalogItem>(
    context: context,
    builder: (_) => _InvoiceServicePickerDialog(
      services: services.where((service) => service.isActive).toList(growable: false),
      existingServiceIds: draft.lines.map((line) => line.serviceId).whereType<String>().toSet(),
    ),
  );
  if (selected == null || !context.mounted) return;
  await ref.read(invoicesRepositoryProvider).addInvoiceService(selected.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã thêm ${selected.name} vào hóa đơn')),
  );
}

Future<void> _updateInvoiceLineQuantity(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
  int quantity,
) async {
  await ref.read(invoicesRepositoryProvider).updateInvoiceLineQuantity(line.id, quantity);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
}

Future<void> _openInvoiceProductPicker(BuildContext context, WidgetRef ref, InvoiceDraft draft) async {
  final products = await ref.read(retailProductsRepositoryProvider).fetchProducts();
  if (!context.mounted) return;
  final selected = await showAppDialog<RetailProductItem>(
    context: context,
    builder: (_) => _InvoiceProductPickerDialog(
      products: products.where((product) => product.isActive).toList(growable: false),
      existingProductIds: draft.lines
          .where((line) => line.isProduct)
          .map((line) => line.productId)
          .whereType<String>()
          .toSet(),
      onCreateProduct: () async {
        final created = await _openRetailProductEditor(context, ref);
        if (!context.mounted || created == null) return;
        Navigator.of(context).pop(created);
      },
    ),
  );
  if (selected == null || !context.mounted) return;
  await ref.read(invoicesRepositoryProvider).addInvoiceProduct(selected.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã thêm ${selected.name} vào hóa đơn')),
  );
}

Future<RetailProductItem?> _openRetailProductEditor(BuildContext context, WidgetRef ref) {
  return showAppDialog<RetailProductItem>(
    context: context,
    builder: (_) => _RetailProductEditorDialog(
      onSave: (input) => ref.read(retailProductsRepositoryProvider).saveProduct(input),
    ),
  );
}

Future<void> _openLineDiscountEditor(BuildContext context, WidgetRef ref, InvoiceDraftLine line) async {
  final subtotal = line.unitPrice * line.quantity;
  final discount = await showAppDialog<int>(
    context: context,
    builder: (_) => _InvoiceDiscountDialog(
      currentDiscount: line.discountAmount,
      maxDiscount: subtotal,
    ),
  );
  if (discount == null || !context.mounted) return;
  await ref.read(invoicesRepositoryProvider).updateInvoiceLineDiscount(line.id, discount);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã giảm ${_currency(discount)} cho ${line.title}')),
  );
}

Future<void> _removeInvoiceLine(BuildContext context, WidgetRef ref, InvoiceDraftLine line) async {
  await ref.read(invoicesRepositoryProvider).removeInvoiceLine(line.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã xóa ${line.title} khỏi hóa đơn')),
  );
}

Future<void> _checkoutInvoice(BuildContext context, WidgetRef ref, InvoiceDraft draft) async {
  await ref.read(invoicesRepositoryProvider).checkoutInvoice();
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ref.invalidate(invoiceHistoryProvider);
  ref.invalidate(customerInvoiceHistoryProvider(draft.customerId));
  if (draft.appointmentId != null) {
    ref.invalidate(appointmentInvoiceHistoryProvider(draft.appointmentId!));
  }
  ref.read(customersRefreshProvider.notifier).state++;
  ref.invalidate(customersRepositoryProvider);
  ref.invalidate(customersViewProvider);
  ref.invalidate(appointmentsRepositoryProvider);
  ref.invalidate(appointmentsViewProvider);
  ref.invalidate(overviewSummaryProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã thanh toán hóa đơn ${_currency(draft.totalAmount)}')),
  );
}

String _buildPaymentQrPayload(InvoiceDraft draft, CustomerProfile? customer) {
  final customerName = customer?.fullName ?? draft.customerId;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return 'SALONPAY|invoice=${draft.id}|customer=$customerName|amount=${draft.totalAmount}|method=${draft.paymentMethod}|ts=$timestamp';
}

Future<void> _showPaymentQrDialog(BuildContext context, InvoiceDraft draft, CustomerProfile? customer) async {
  final payload = _buildPaymentQrPayload(draft, customer);
  await showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          PremiumIconBadge(icon: Icons.qr_code_2_rounded, size: 38),
          SizedBox(width: 10),
          Text('QR thanh toán'),
        ],
      ),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(data: payload, version: QrVersions.auto, size: 210, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(_currency(draft.totalAmount), style: Theme.of(dialogContext).textTheme.displayMedium?.copyWith(color: AppColors.copper)),
            const SizedBox(height: 6),
            Text(customer?.fullName ?? draft.customerId, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('Nội dung: ${draft.id}', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Đóng'))],
    ),
  );
}

Future<void> _exportInvoicePdf(BuildContext context, InvoiceDraft draft, CustomerProfile? customer) async {
  try {
    final document = pw.Document();
    final generatedAt = DateTime.now();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('PHIEU THANH TOAN', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Ma hoa don: ${draft.id}'),
          pw.Text('Khach hang: ${customer?.fullName ?? draft.customerId}'),
          pw.Text('SDT: ${customer?.phone ?? '-'}'),
          pw.Text('Ngay tao: ${generatedAt.day}/${generatedAt.month}/${generatedAt.year} ${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Dich vu', 'SL', 'Don gia', 'Thanh tien'],
            data: draft.lines.map((line) => [line.title, '${line.quantity}', _currency(line.unitPrice), _currency(line.totalPrice)]).toList(growable: false),
          ),
          pw.SizedBox(height: 16),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('Tam tinh: ${_currency(draft.subtotal)}')]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('Giam gia: ${_currency(draft.discountAmount)}')]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text('Tong cong: ${_currency(draft.totalAmount)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 8),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [pw.Text('PTTT: ${draft.paymentMethod}')]),
        ],
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final invoicesDir = Directory(path.join(docsDir.path, 'HairSpaManager', 'invoices'));
    if (!await invoicesDir.exists()) await invoicesDir.create(recursive: true);
    final filePath = path.join(invoicesDir.path, 'invoice_${draft.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    final file = File(filePath);
    await file.writeAsBytes(await document.save());
    await Process.start('cmd', ['/c', 'start', '', filePath], runInShell: true, mode: ProcessStartMode.detached);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xuất PDF hóa đơn: $filePath')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xuất PDF thất bại: $error')));
  }
}

class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftState = ref.watch(invoiceDraftProvider);
    final historyState = ref.watch(invoiceHistoryProvider);
    final filteredCustomersState = ref.watch(invoiceFilteredCustomersProvider);
    final allCustomersState = ref.watch(customersViewProvider);

    return draftState.when(
      data: (draft) => historyState.when(
        data: (history) => filteredCustomersState.when(
          data: (filtered) => allCustomersState.when(
            data: (all) => _BillingView(draft: draft, history: history, filteredCustomers: filtered, allCustomers: all),
            loading: () => const PremiumLoadingState(label: 'Đang tải khách hàng…'),
            error: (error, _) => PremiumErrorState(
              title: 'Không tải được khách hàng',
              message: '$error',
              onRetry: () => ref.invalidate(customersViewProvider),
            ),
          ),
          loading: () => const PremiumLoadingState(label: 'Đang lọc khách tính tiền…'),
          error: (error, _) => PremiumErrorState(
            title: 'Không tải được khách hàng tính tiền',
            message: '$error',
            onRetry: () => ref.invalidate(invoiceFilteredCustomersProvider),
          ),
        ),
        loading: () => const PremiumLoadingState(label: 'Đang tải lịch sử hóa đơn…'),
        error: (error, _) => PremiumErrorState(
          title: 'Không tải được lịch sử hóa đơn',
          message: '$error',
          onRetry: () => ref.invalidate(invoiceHistoryProvider),
        ),
      ),
      loading: () => const PremiumLoadingState(label: 'Đang tải hóa đơn…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được hóa đơn',
        message: '$error',
        onRetry: () => ref.invalidate(invoiceDraftProvider),
      ),
    );
  }
}

class _BillingView extends ConsumerWidget {
  const _BillingView({
    required this.draft,
    required this.history,
    required this.filteredCustomers,
    required this.allCustomers,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> filteredCustomers;
  final List<CustomerProfile> allCustomers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    CustomerProfile? selectedCustomer;
    for (final customer in allCustomers) {
      if (customer.id == draft.customerId) {
        selectedCustomer = customer;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1260;
        final panelHeight = constraints.maxHeight < 760 ? 690.0 : 735.0;

        return ListView(
          primary: false,
          key: const Key('billing-premium-workspace'),
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            PremiumPageHeader(
              key: const Key('billing-premium-header'),
              icon: Icons.point_of_sale_outlined,
              eyebrow: 'Thanh toán tại quầy',
              title: 'Tính tiền',
              subtitle: 'Chọn khách, rà bill và chốt thanh toán theo một luồng liền mạch.',
              trailing: [
                PremiumStatusPill(
                  label: draft.isPaid ? 'Đã thanh toán' : 'Đang lập bill',
                  tone: draft.isPaid ? AppColors.success : AppColors.copper,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _BillingStats(draft: draft),
            const SizedBox(height: 16),
            if (wide)
              SizedBox(
                height: panelHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _CustomerSelectionPanel(
                        customers: filteredCustomers,
                        selectedCustomerId: draft.customerId,
                        isLocked: draft.isPaid || draft.appointmentId != null,
                        isAppointmentLocked: draft.appointmentId != null,
                        lockedCustomer: selectedCustomer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: _InvoiceDraftPanel(draft: draft)),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: _PaymentSummaryPanel(
                        draft: draft,
                        history: history,
                        allCustomers: allCustomers,
                        selectedCustomer: selectedCustomer,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(
                height: 390,
                child: _CustomerSelectionPanel(
                  customers: filteredCustomers,
                  selectedCustomerId: draft.customerId,
                  isLocked: draft.isPaid || draft.appointmentId != null,
                  isAppointmentLocked: draft.appointmentId != null,
                  lockedCustomer: selectedCustomer,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 500, child: _InvoiceDraftPanel(draft: draft)),
              const SizedBox(height: 16),
              _PaymentSummaryPanel(
                draft: draft,
                history: history,
                allCustomers: allCustomers,
                selectedCustomer: selectedCustomer,
                compact: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BillingStats extends StatelessWidget {
  const _BillingStats({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    final cards = [
      PremiumStatCard(icon: Icons.receipt_long_outlined, label: 'Mục trong bill', value: '${draft.lines.length}', note: 'Dịch vụ & sản phẩm'),
      PremiumStatCard(icon: Icons.calculate_outlined, label: 'Tạm tính', value: _currency(draft.subtotal), tone: AppColors.info),
      PremiumStatCard(icon: Icons.local_offer_outlined, label: 'Giảm giá', value: _currency(draft.discountAmount), tone: AppColors.warning),
      PremiumStatCard(icon: Icons.payments_outlined, label: 'Thành tiền', value: _currency(draft.totalAmount), tone: AppColors.copper),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120 ? 4 : constraints.maxWidth >= 620 ? 2 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: width, child: card)]);
      },
    );
  }
}

class _CustomerSelectionPanel extends ConsumerWidget {
  const _CustomerSelectionPanel({
    required this.customers,
    required this.selectedCustomerId,
    required this.isLocked,
    required this.isAppointmentLocked,
    required this.lockedCustomer,
  });

  final List<CustomerProfile> customers;
  final String selectedCustomerId;
  final bool isLocked;
  final bool isAppointmentLocked;
  final CustomerProfile? lockedCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCustomers = isAppointmentLocked && lockedCustomer != null ? [lockedCustomer!] : customers;

    return PremiumSectionCard(
      icon: Icons.people_outline,
      title: 'Khách hàng',
      subtitle: isAppointmentLocked ? 'Đã khóa theo lịch hẹn' : 'Chọn khách cho bill hiện tại',
      trailing: isAppointmentLocked ? const Icon(Icons.lock_outline_rounded, size: 18) : null,
      child: Expanded(
        child: Column(
          children: [
            TextFormField(
              enabled: !isAppointmentLocked,
              initialValue: ref.watch(invoiceCustomerQueryProvider),
              onChanged: (value) => ref.read(invoiceCustomerQueryProvider.notifier).state = value,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Tìm tên hoặc số điện thoại'),
            ),
            if (isAppointmentLocked) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Khách được giữ theo lịch hẹn để tránh lệch hóa đơn.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: visibleCustomers.isEmpty
                  ? const PremiumEmptyState(icon: Icons.person_search_outlined, title: 'Không tìm thấy khách', message: 'Thử từ khóa khác hoặc quay lại danh sách khách hàng.')
                  : ListView.separated(
                      primary: false,
                      itemCount: visibleCustomers.length,
                      separatorBuilder: (context, index) => const PremiumDivider(indent: 48),
                      itemBuilder: (context, index) {
                        final customer = visibleCustomers[index];
                        return _CustomerBillingRow(
                          customer: customer,
                          selected: customer.id == selectedCustomerId,
                          onTap: isLocked ? null : () => _selectInvoiceCustomer(context, ref, customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerBillingRow extends StatelessWidget {
  const _CustomerBillingRow({required this.customer, required this.selected, this.onTap});

  final CustomerProfile customer;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumInteractiveSurface(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.iconSurface,
            foregroundColor: AppColors.copper,
            child: Text(customer.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(customer.phone, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_circle_rounded, color: AppColors.copper, size: 18) else Text(customer.tier, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _InvoiceDraftPanel extends ConsumerWidget {
  const _InvoiceDraftPanel({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumSectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Bill hiện tại',
      subtitle: '${draft.lines.length} mục • ${draft.isPaid ? 'đã khóa' : 'có thể chỉnh sửa'}',
      trailing: PopupMenuButton<String>(
        enabled: !draft.isPaid,
        tooltip: 'Thêm vào bill',
        onSelected: (value) {
          if (value == 'service') _openInvoiceServicePicker(context, ref, draft);
          if (value == 'product') _openInvoiceProductPicker(context, ref, draft);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'service', child: ListTile(leading: Icon(Icons.content_cut_rounded), title: Text('Thêm dịch vụ'))),
          PopupMenuItem(value: 'product', child: ListTile(leading: Icon(Icons.shopping_bag_outlined), title: Text('Thêm sản phẩm'))),
        ],
        icon: const Icon(Icons.add_circle_outline_rounded),
      ),
      child: Expanded(
        child: draft.lines.isEmpty
            ? const PremiumEmptyState(icon: Icons.receipt_long_outlined, title: 'Bill đang trống', message: 'Thêm dịch vụ hoặc sản phẩm để bắt đầu tính tiền.')
            : Column(
                children: [
                  const _InvoiceTableHeader(),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      primary: false,
                      itemCount: draft.lines.length,
                      separatorBuilder: (context, index) => const PremiumDivider(),
                      itemBuilder: (context, index) => _InvoiceLineRow(line: draft.lines[index], isLocked: draft.isPaid),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: draft.isPaid ? null : () => _openInvoiceServicePicker(context, ref, draft),
                        icon: const Icon(Icons.content_cut_rounded, size: 16),
                        label: const Text('Dịch vụ'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: draft.isPaid ? null : () => _openInvoiceProductPicker(context, ref, draft),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                        label: const Text('Sản phẩm'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _InvoiceTableHeader extends StatelessWidget {
  const _InvoiceTableHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) return const SizedBox.shrink();
        final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('Dịch vụ / sản phẩm', style: style)),
              Expanded(flex: 2, child: Text('Đơn giá', style: style)),
              Expanded(flex: 2, child: Text('SL', style: style)),
              Expanded(flex: 3, child: Text('Thành tiền', textAlign: TextAlign.right, style: style)),
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceLineRow extends ConsumerWidget {
  const _InvoiceLineRow({required this.line, required this.isLocked});

  final InvoiceDraftLine line;
  final bool isLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final icon = line.isProduct ? Icons.shopping_bag_outlined : Icons.content_cut_rounded;
        final tone = line.isProduct ? AppColors.info : AppColors.copper;

        if (compact) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PremiumIconBadge(icon: icon, size: 34, tone: tone),
                    const SizedBox(width: 9),
                    Expanded(child: Text(line.title, style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      onPressed: isLocked ? null : () => _removeInvoiceLine(context, ref, line),
                      tooltip: 'Xóa khỏi bill',
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(_currency(line.unitPrice), style: TextStyle(color: AppColors.textSecondary)),
                    const Spacer(),
                    _QuantityControl(
                      quantity: line.quantity,
                      isLocked: isLocked,
                      onMinus: line.quantity <= 1 ? null : () => _updateInvoiceLineQuantity(context, ref, line, line.quantity - 1),
                      onPlus: () => _updateInvoiceLineQuantity(context, ref, line, line.quantity + 1),
                    ),
                    const SizedBox(width: 12),
                    Text(_currency(line.totalPrice), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                if (line.discountAmount > 0 || !isLocked) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      if (line.discountAmount > 0)
                        Text('Giảm ${_currency(line.discountAmount)}', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                      const Spacer(),
                      if (!isLocked)
                        InkWell(
                          onTap: () => _openLineDiscountEditor(context, ref, line),
                          child: Text('Giảm giá dòng', style: TextStyle(fontSize: 11, color: AppColors.copper, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        PremiumIconBadge(icon: icon, size: 32, tone: tone),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ],
                    ),
                  ),
                  Expanded(flex: 2, child: Text(_currency(line.unitPrice))),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _QuantityControl(
                        quantity: line.quantity,
                        isLocked: isLocked,
                        onMinus: line.quantity <= 1 ? null : () => _updateInvoiceLineQuantity(context, ref, line, line.quantity - 1),
                        onPlus: () => _updateInvoiceLineQuantity(context, ref, line, line.quantity + 1),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(child: Text(_currency(line.totalPrice), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const SizedBox(width: 3),
                        IconButton(
                          onPressed: isLocked ? null : () => _removeInvoiceLine(context, ref, line),
                          tooltip: 'Xóa khỏi bill',
                          icon: const Icon(Icons.close_rounded, size: 17),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (line.discountAmount > 0 || !isLocked)
                Row(
                  children: [
                    const SizedBox(width: 40),
                    if (line.discountAmount > 0)
                      Text('Giảm dòng ${_currency(line.discountAmount)}', style: TextStyle(fontSize: 10.5, color: AppColors.warning)),
                    const Spacer(),
                    if (!isLocked)
                      TextButton(
                        onPressed: () => _openLineDiscountEditor(context, ref, line),
                        child: Text(line.discountAmount > 0 ? 'Sửa giảm giá' : 'Giảm giá dòng'),
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

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({required this.quantity, required this.isLocked, this.onMinus, required this.onPlus});

  final int quantity;
  final bool isLocked;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.controlBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _QtyIcon(icon: Icons.remove_rounded, onTap: isLocked ? null : onMinus),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text('$quantity', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          _QtyIcon(icon: Icons.add_rounded, onTap: isLocked ? null : onPlus),
        ],
      ),
    );
  }
}

class _QtyIcon extends StatelessWidget {
  const _QtyIcon({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 25, height: 28, child: Icon(icon, size: 14, color: onTap == null ? AppColors.textMuted : AppColors.textPrimary)),
    );
  }
}

class _PaymentSummaryPanel extends ConsumerWidget {
  const _PaymentSummaryPanel({
    required this.draft,
    required this.history,
    required this.allCustomers,
    required this.selectedCustomer,
    this.compact = false,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> allCustomers;
  final CustomerProfile? selectedCustomer;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedCustomer != null) ...[
          _SelectedCustomerSummary(customer: selectedCustomer!, locked: draft.isPaid || draft.appointmentId != null),
          const SizedBox(height: 14),
        ],
        _TotalHero(draft: draft),
        const SizedBox(height: 14),
        _AmountLine(label: 'Tạm tính', value: _currency(draft.subtotal)),
        const SizedBox(height: 7),
        _AmountLine(
          label: 'Giảm giá',
          value: _currency(draft.discountAmount),
          action: draft.isPaid ? null : () => _openDiscountEditor(context, ref, draft),
        ),
        const SizedBox(height: 14),
        Text('Phương thức thanh toán', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 8),
        _PaymentMethodSelector(
          selected: draft.paymentMethod,
          locked: draft.isPaid,
          onSelected: (method) => _updateInvoicePaymentMethod(context, ref, method),
        ),
        if (draft.paidAt != null) ...[
          const SizedBox(height: 12),
          PremiumStatusPill(
            label: 'Đã thanh toán ${draft.paidAt!.hour.toString().padLeft(2, '0')}:${draft.paidAt!.minute.toString().padLeft(2, '0')}',
            tone: AppColors.success,
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: draft.isPaid || draft.lines.isEmpty ? null : () => _checkoutInvoice(context, ref, draft),
            icon: Icon(draft.isPaid ? Icons.check_circle_outline_rounded : Icons.payments_outlined),
            label: Text(draft.isPaid ? 'Đã thanh toán' : 'Thanh toán ${_currency(draft.totalAmount)}'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: draft.lines.isEmpty ? null : () => _showPaymentQrDialog(context, draft, selectedCustomer),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: const Text('QR'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: draft.lines.isEmpty ? null : () => _exportInvoicePdf(context, draft, selectedCustomer),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InvoiceHistoryPanel(history: history, customers: allCustomers),
      ],
    );

    return PremiumSectionCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Thanh toán',
      subtitle: 'Kiểm tra tổng tiền và chốt phương thức.',
      child: compact ? content : Expanded(child: SingleChildScrollView(primary: false, child: content)),
    );
  }
}

class _SelectedCustomerSummary extends StatelessWidget {
  const _SelectedCustomerSummary({required this.customer, required this.locked});

  final CustomerProfile customer;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: AppColors.iconSurface,
          foregroundColor: AppColors.copper,
          child: Text(customer.initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(customer.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(customer.phone, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        if (locked) Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
      ],
    );
  }
}

class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.selectedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.copper.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THÀNH TIỀN', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.copper, letterSpacing: 1.0, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_currency(draft.totalAmount), style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 30, color: AppColors.copper, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 3),
          Text('${draft.lines.length} mục • ${draft.paymentMethod}', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value, this.action});

  final String label;
  final String value;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
        if (action != null)
          InkWell(
            onTap: action,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text('Sửa', style: TextStyle(fontSize: 11, color: AppColors.copper, fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _PaymentMethodSelector extends StatelessWidget {
  const _PaymentMethodSelector({required this.selected, required this.locked, required this.onSelected});

  final String selected;
  final bool locked;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final methods = [
      (label: 'Tiền mặt', icon: Icons.payments_outlined),
      (label: 'Chuyển khoản', icon: Icons.account_balance_outlined),
      (label: 'Thẻ', icon: Icons.credit_card_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final method in methods)
          _PaymentMethodButton(
            label: method.label,
            icon: method.icon,
            selected: selected == method.label,
            onTap: locked ? null : () => onSelected(method.label),
          ),
      ],
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  const _PaymentMethodButton({required this.label, required this.icon, required this.selected, this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: AppMotion.duration(context, AppMotion.quick),
          curve: AppMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.selectedSurface : AppColors.panel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? AppColors.copper.withValues(alpha: 0.54) : AppColors.controlBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? AppColors.copper : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? AppColors.copper : AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceHistoryPanel extends StatelessWidget {
  const _InvoiceHistoryPanel({required this.history, required this.customers});

  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;

  @override
  Widget build(BuildContext context) {
    final visibleHistory = history.take(3).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 17, color: AppColors.copper),
            const SizedBox(width: 7),
            Text('Gần đây', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        if (visibleHistory.isEmpty)
          Text('Chưa có hóa đơn đã thanh toán.', style: TextStyle(color: AppColors.textMuted))
        else
          for (var index = 0; index < visibleHistory.length; index++) ...[
            _HistoryRow(
              invoice: visibleHistory[index],
              customerName: _customerNameFor(visibleHistory[index].customerId, customers),
            ),
            if (index < visibleHistory.length - 1) const PremiumDivider(indent: 34),
          ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.invoice, required this.customerName});

  final InvoiceDraft invoice;
  final String customerName;

  @override
  Widget build(BuildContext context) {
    final paidAt = invoice.paidAt;
    final time = paidAt == null
        ? ''
        : '${paidAt.day.toString().padLeft(2, '0')}/${paidAt.month.toString().padLeft(2, '0')} ${paidAt.hour.toString().padLeft(2, '0')}:${paidAt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.iconSurface, borderRadius: BorderRadius.circular(9)),
            child: Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.copper),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text('$time • ${invoice.paymentMethod}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(_currency(invoice.totalAmount), style: TextStyle(fontSize: 11.5, color: AppColors.copper, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _InvoiceDiscountDialog extends StatefulWidget {
  const _InvoiceDiscountDialog({required this.currentDiscount, required this.maxDiscount});

  final int currentDiscount;
  final int maxDiscount;

  @override
  State<_InvoiceDiscountDialog> createState() => _InvoiceDiscountDialogState();
}

class _InvoiceDiscountDialogState extends State<_InvoiceDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentDiscount.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [PremiumIconBadge(icon: Icons.local_offer_outlined, size: 36), SizedBox(width: 9), Text('Cập nhật giảm giá')]),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 420),
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Giảm giá (đ)', helperText: 'Tối đa ${_currency(widget.maxDiscount)}', prefixIcon: const Icon(Icons.sell_outlined)),
            validator: (value) {
              final amount = int.tryParse(value?.trim() ?? '');
              return amount == null || amount < 0 ? 'Nhập số tiền hợp lệ' : null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: const Text('Lưu giảm giá')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = int.parse(_controller.text.trim());
    Navigator.of(context).pop(amount > widget.maxDiscount ? widget.maxDiscount : amount);
  }
}

class _InvoiceServicePickerDialog extends StatelessWidget {
  const _InvoiceServicePickerDialog({required this.services, required this.existingServiceIds});

  final List<ServiceCatalogItem> services;
  final Set<String> existingServiceIds;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [PremiumIconBadge(icon: Icons.content_cut_rounded, size: 36), SizedBox(width: 9), Text('Thêm dịch vụ')]),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 540),
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
                    onTap: () => Navigator.of(context).pop(service),
                    title: Text(service.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${service.category} • ${service.durationLabel}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(service.priceLabel, style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w800)),
                        if (existingServiceIds.contains(service.id)) Text('Tăng SL', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Đóng'))],
    );
  }
}

class _InvoiceProductPickerDialog extends StatelessWidget {
  const _InvoiceProductPickerDialog({required this.products, required this.existingProductIds, required this.onCreateProduct});

  final List<RetailProductItem> products;
  final Set<String> existingProductIds;
  final Future<void> Function() onCreateProduct;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [PremiumIconBadge(icon: Icons.shopping_bag_outlined, size: 36), SizedBox(width: 9), Text('Thêm sản phẩm')]),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 540),
        child: products.isEmpty
            ? const PremiumEmptyState(icon: Icons.inventory_2_outlined, title: 'Chưa có sản phẩm', message: 'Tạo sản phẩm mới để thêm vào bill.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (context, index) => const PremiumDivider(indent: 44),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    leading: const PremiumIconBadge(icon: Icons.shopping_bag_outlined, size: 34),
                    onTap: () => Navigator.of(context).pop(product),
                    title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${product.productType}${product.brand.isEmpty ? '' : ' • ${product.brand}'}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(product.salePriceLabel, style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w800)),
                        if (existingProductIds.contains(product.id)) Text('Tăng SL', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(onPressed: onCreateProduct, icon: const Icon(Icons.add_box_outlined), label: const Text('Tạo sản phẩm')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Đóng')),
      ],
    );
  }
}

class _RetailProductEditorDialog extends StatefulWidget {
  const _RetailProductEditorDialog({required this.onSave});

  final Future<RetailProductItem> Function(RetailProductUpsertInput input) onSave;

  @override
  State<_RetailProductEditorDialog> createState() => _RetailProductEditorDialogState();
}

class _RetailProductEditorDialogState extends State<_RetailProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _volumeController = TextEditingController();
  final _priceController = TextEditingController();
  String _type = RetailProductUpsertInput.productTypes.first;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _volumeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [PremiumIconBadge(icon: Icons.add_box_outlined, size: 36), SizedBox(width: 9), Text('Thêm sản phẩm bán lẻ')]),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Tên sản phẩm'), validator: (value) => value == null || value.trim().isEmpty ? 'Nhập tên sản phẩm' : null),
                const SizedBox(height: 10),
                TextFormField(controller: _brandController, decoration: const InputDecoration(labelText: 'Thương hiệu')),
                const SizedBox(height: 10),
                TextFormField(controller: _volumeController, decoration: const InputDecoration(labelText: 'Dung tích / quy cách')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Nhóm sản phẩm'),
                  items: RetailProductUpsertInput.productTypes.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                  onChanged: (value) { if (value != null) setState(() => _type = value); },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Giá bán (đ)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    return parsed == null || parsed <= 0 ? 'Nhập giá hợp lệ' : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('Hủy')),
        FilledButton(onPressed: _isSaving ? null : _save, child: const Text('Lưu sản phẩm')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final input = RetailProductUpsertInput(
      name: _nameController.text.trim(),
      brand: _brandController.text.trim(),
      volumeLabel: _volumeController.text.trim(),
      productType: _type,
      salePrice: int.parse(_priceController.text.trim()),
      commissionPercent: 0,
      isHiddenFromStaff: false,
      isActive: true,
    );
    final created = await widget.onSave(input);
    if (!mounted) return;
    Navigator.of(context).pop(created);
  }
}

String _customerNameFor(String id, List<CustomerProfile> customers) {
  for (final customer in customers) {
    if (customer.id == id) return customer.fullName;
  }
  return id;
}

String _currency(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final reverseIndex = digits.length - index;
    buffer.write(digits[index]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write('.');
  }
  return '${value < 0 ? '-' : ''}${buffer.toString()}đ';
}
