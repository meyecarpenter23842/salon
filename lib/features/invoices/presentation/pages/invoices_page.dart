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
import '../../../../core/theme/app_dimens.dart';
import '../../../../shared/widgets/app_primitives.dart';

final invoiceCustomerQueryProvider = StateProvider<String>((ref) => '');

final invoiceFilteredCustomersProvider = FutureProvider<List<CustomerProfile>>((
  ref,
) {
  ref.watch(customersRefreshProvider);
  final query = ref.watch(invoiceCustomerQueryProvider).trim();
  return ref
      .watch(customersRepositoryProvider)
      .fetchCustomersView(query: query.isEmpty ? null : query);
});

Future<void> _selectInvoiceCustomer(
  BuildContext context,
  WidgetRef ref,
  CustomerProfile customer,
) async {
  await ref.read(invoicesRepositoryProvider).selectInvoiceCustomer(customer.id);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã chọn khách ${customer.fullName} cho hóa đơn')),
  );
}

Future<void> _updateInvoicePaymentMethod(
  BuildContext context,
  WidgetRef ref,
  String paymentMethod,
) async {
  await ref
      .read(invoicesRepositoryProvider)
      .updateInvoicePaymentMethod(paymentMethod);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
}

Future<void> _openDiscountEditor(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
  final discount = await showDialog<int>(
    context: context,
    builder: (dialogContext) => _InvoiceDiscountDialog(
      currentDiscount: draft.discountAmount,
      maxDiscount: draft.subtotal,
    ),
  );

  if (discount == null || !context.mounted) {
    return;
  }

  await ref.read(invoicesRepositoryProvider).updateInvoiceDiscount(discount);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã cập nhật giảm giá ${_currency(discount)}')),
  );
}

Future<void> _openInvoiceServicePicker(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
  final services = await ref
      .read(servicesRepositoryProvider)
      .fetchServicesView();

  if (!context.mounted) {
    return;
  }

  final selectedService = await showDialog<ServiceCatalogItem>(
    context: context,
    builder: (dialogContext) => _InvoiceServicePickerDialog(
      services: services
          .where((service) => service.isActive)
          .toList(growable: false),
      existingServiceIds: draft.lines
          .map((line) => line.serviceId)
          .whereType<String>()
          .toSet(),
    ),
  );

  if (selectedService == null || !context.mounted) {
    return;
  }

  await ref
      .read(invoicesRepositoryProvider)
      .addInvoiceService(selectedService.id);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã thêm ${selectedService.name} vào hóa đơn')),
  );
}

Future<void> _updateInvoiceLineQuantity(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
  int quantity,
) async {
  await ref
      .read(invoicesRepositoryProvider)
      .updateInvoiceLineQuantity(line.id, quantity);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
}

Future<void> _openInvoiceProductPicker(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
  final products = await ref
      .read(retailProductsRepositoryProvider)
      .fetchProducts();

  if (!context.mounted) {
    return;
  }

  final selected = await showDialog<RetailProductItem>(
    context: context,
    builder: (_) => _InvoiceProductPickerDialog(
      products: products.where((p) => p.isActive).toList(growable: false),
      existingProductIds: draft.lines
          .where((l) => l.isProduct)
          .map((l) => l.productId)
          .whereType<String>()
          .toSet(),
      onCreateProduct: () async {
        final created = await _openRetailProductEditor(context, ref);
        if (!context.mounted || created == null) {
          return;
        }
        Navigator.of(context).pop(created);
      },
    ),
  );

  if (selected == null || !context.mounted) {
    return;
  }

  await ref.read(invoicesRepositoryProvider).addInvoiceProduct(selected.id);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã thêm ${selected.name} vào hóa đơn')),
  );
}

Future<RetailProductItem?> _openRetailProductEditor(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<RetailProductItem>(
    context: context,
    builder: (_) => _RetailProductEditorDialog(
      onSave: (input) =>
          ref.read(retailProductsRepositoryProvider).saveProduct(input),
    ),
  );
}

Future<void> _openLineDiscountEditor(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
) async {
  final subtotal = line.unitPrice * line.quantity;
  final discount = await showDialog<int>(
    context: context,
    builder: (_) => _InvoiceDiscountDialog(
      currentDiscount: line.discountAmount,
      maxDiscount: subtotal,
    ),
  );

  if (discount == null || !context.mounted) {
    return;
  }

  await ref
      .read(invoicesRepositoryProvider)
      .updateInvoiceLineDiscount(line.id, discount);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Đã giảm ${_currency(discount)} cho ${line.title}')),
  );
}

Future<void> _removeInvoiceLine(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
) async {
  await ref.read(invoicesRepositoryProvider).removeInvoiceLine(line.id);

  if (!context.mounted) {
    return;
  }

  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Đã xóa ${line.title} khỏi hóa đơn')));
}

Future<void> _checkoutInvoice(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
  await ref.read(invoicesRepositoryProvider).checkoutInvoice();

  if (!context.mounted) {
    return;
  }

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
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Đã thanh toán hóa đơn ${_currency(draft.totalAmount)}'),
    ),
  );
}

String _buildPaymentQrPayload(InvoiceDraft draft, CustomerProfile? customer) {
  final customerName = customer?.fullName ?? draft.customerId;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return 'SALONPAY|invoice=${draft.id}|customer=$customerName|amount=${draft.totalAmount}|method=${draft.paymentMethod}|ts=$timestamp';
}

Future<void> _showPaymentQrDialog(
  BuildContext context,
  InvoiceDraft draft,
  CustomerProfile? customer,
) async {
  final payload = _buildPaymentQrPayload(draft, customer);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('QR thanh toán'),
      content: SizedBox(
        width: adaptiveDialogWidth(dialogContext, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 12),
            Text(
              'Số tiền: ${_currency(draft.totalAmount)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Khách: ${customer?.fullName ?? draft.customerId}'),
            const SizedBox(height: 6),
            Text(
              'Nội dung: ${draft.id}',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
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

Future<void> _exportInvoicePdf(
  BuildContext context,
  InvoiceDraft draft,
  CustomerProfile? customer,
) async {
  try {
    final document = pw.Document();
    final generatedAt = DateTime.now();
    document.addPage(
      pw.MultiPage(
        build: (pw.Context pdfContext) => [
          pw.Text(
            'PHIEU THANH TOAN',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Ma hoa don: ${draft.id}'),
          pw.Text('Khach hang: ${customer?.fullName ?? draft.customerId}'),
          pw.Text('SDT: ${customer?.phone ?? '-'}'),
          pw.Text(
            'Ngay tao: ${generatedAt.day}/${generatedAt.month}/${generatedAt.year} ${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Dich vu', 'SL', 'Don gia', 'Thanh tien'],
            data: draft.lines
                .map(
                  (line) => [
                    line.title,
                    '${line.quantity}',
                    _currency(line.unitPrice),
                    _currency(line.totalPrice),
                  ],
                )
                .toList(growable: false),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Text('Tam tinh: ${_currency(draft.subtotal)}')],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Text('Giam gia: ${_currency(draft.discountAmount)}')],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Tong cong: ${_currency(draft.totalAmount)}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Text('PTTT: ${draft.paymentMethod}')],
          ),
        ],
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final invoicesDir = Directory(
      path.join(docsDir.path, 'HairSpaManager', 'invoices'),
    );
    if (!await invoicesDir.exists()) {
      await invoicesDir.create(recursive: true);
    }

    final filePath = path.join(
      invoicesDir.path,
      'invoice_${draft.id}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    final file = File(filePath);
    await file.writeAsBytes(await document.save());

    await Process.start(
      'cmd',
      ['/c', 'start', '', filePath],
      runInShell: true,
      mode: ProcessStartMode.detached,
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã xuất PDF hóa đơn: $filePath')));
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Xuất PDF thất bại: $error')));
  }
}

class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceDraft = ref.watch(invoiceDraftProvider);
    final invoiceHistory = ref.watch(invoiceHistoryProvider);
    final filteredCustomers = ref.watch(invoiceFilteredCustomersProvider);
    final allCustomers = ref.watch(customersViewProvider);

    return invoiceDraft.when(
      data: (draft) => invoiceHistory.when(
        data: (history) => filteredCustomers.when(
          data: (filteredCustomerItems) => allCustomers.when(
            data: (allCustomerItems) => _BillingView(
              draft: draft,
              history: history,
              filteredCustomers: filteredCustomerItems,
              allCustomers: allCustomerItems,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) =>
                Center(child: Text('Không tải được khách hàng: $error')),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Text('Không tải được khách hàng tính tiền: $error'),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text('Không tải được lịch sử hóa đơn: $error')),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Không tải được hóa đơn: $error')),
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
      builder: (context, viewport) {
        final shortViewport = viewport.maxHeight < 560;

        Widget buildBody() {
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1240;
              final customerPanel = _CustomerSelectionPanel(
                customers: filteredCustomers,
                selectedCustomerId: draft.customerId,
                isLocked: draft.isPaid || draft.appointmentId != null,
                isAppointmentLocked: draft.appointmentId != null,
                lockedCustomer: selectedCustomer,
              );
              final invoicePanel = _InvoiceDraftPanel(draft: draft);
              final paymentPanel = _PaymentSummaryPanel(
                draft: draft,
                history: history,
                allCustomers: allCustomers,
                selectedCustomer: selectedCustomer,
              );

              if (compact) {
                return Column(
                  children: [
                    Expanded(child: customerPanel),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(child: invoicePanel),
                    const SizedBox(height: AppDimens.cardGap),
                    Expanded(child: paymentPanel),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: customerPanel),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(flex: 5, child: invoicePanel),
                  const SizedBox(width: AppDimens.cardGap),
                  Expanded(flex: 4, child: paymentPanel),
                ],
              );
            },
          );
        }

        if (shortViewport) {
          return ListView(
            primary: false,
            children: [
              const _BillingHero(),
              const SizedBox(height: AppDimens.heroGap),
              _BillingSummaryRow(
                lineCount: draft.lines.length,
                subtotal: draft.subtotal,
                discount: draft.discountAmount,
                total: draft.totalAmount,
              ),
              const SizedBox(height: AppDimens.sectionGap),
              SizedBox(height: 1040, child: buildBody()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BillingHero(),
            const SizedBox(height: AppDimens.heroGap),
            _BillingSummaryRow(
              lineCount: draft.lines.length,
              subtotal: draft.subtotal,
              discount: draft.discountAmount,
              total: draft.totalAmount,
            ),
            const SizedBox(height: AppDimens.sectionGap),
            Expanded(child: buildBody()),
          ],
        );
      },
    );
  }
}

class _BillingHero extends StatelessWidget {
  const _BillingHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tính tiền',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text(
            'Workflow desktop bám UI mẫu: chọn khách, xem dịch vụ đã chọn, kiểm tra tạm tính và chốt phương thức thanh toán.',
            style: TextStyle(color: AppColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _BillingSummaryRow extends StatelessWidget {
  const _BillingSummaryRow({
    required this.lineCount,
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  final int lineCount;
  final int subtotal;
  final int discount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _BillingSummaryCard(label: 'Dịch vụ đã chọn', value: '$lineCount'),
      _BillingSummaryCard(label: 'Tạm tính', value: _currency(subtotal)),
      _BillingSummaryCard(label: 'Giảm giá', value: _currency(discount)),
      _BillingSummaryCard(label: 'Thành tiền', value: _currency(total)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
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

class _BillingSummaryCard extends StatelessWidget {
  const _BillingSummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
    final visibleCustomers = isAppointmentLocked && lockedCustomer != null
        ? [lockedCustomer!]
        : customers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Khách hàng',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (isAppointmentLocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.panelRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Khách hàng được khóa theo lịch hẹn. Muốn đổi khách, hãy quay lại tạo hóa đơn mới ngoài flow lịch hẹn.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              enabled: !isAppointmentLocked,
              initialValue: ref.watch(invoiceCustomerQueryProvider),
              onChanged: (value) {
                ref.read(invoiceCustomerQueryProvider.notifier).state = value;
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Tìm khách hàng...',
              ),
            ),
            const SizedBox(height: 16),
            if (visibleCustomers.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Không tìm thấy khách hàng phù hợp.'),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  primary: false,
                  itemCount: visibleCustomers.length,
                  itemBuilder: (context, index) {
                    final customer = visibleCustomers[index];
                    return _CustomerBillingTile(
                      customer: customer,
                      selected: customer.id == selectedCustomerId,
                      onTap: isLocked
                          ? null
                          : () =>
                                _selectInvoiceCustomer(context, ref, customer),
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

class _CustomerBillingTile extends StatelessWidget {
  const _CustomerBillingTile({
    required this.customer,
    required this.selected,
    this.onTap,
  });

  final CustomerProfile customer;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? AppColors.panelRaised : AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.copper : AppColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: AppColors.avatarFill,
            foregroundColor: AppColors.textPrimary,
            child: Text(customer.initials),
          ),
          title: Text(
            customer.fullName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(customer.phone),
              const SizedBox(height: 2),
              Text(
                customer.tier,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceDraftPanel extends ConsumerWidget {
  const _InvoiceDraftPanel({required this.draft});

  final InvoiceDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dịch vụ đã chọn',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Dịch vụ',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Đơn giá',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'SL',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Thành tiền',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: draft.lines.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có dịch vụ hoặc sản phẩm trong hóa đơn.',
                      ),
                    )
                  : ListView.builder(
                      primary: false,
                      itemCount: draft.lines.length,
                      itemBuilder: (context, index) => _InvoiceLineTile(
                        line: draft.lines[index],
                        isLocked: draft.isPaid,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: draft.isPaid
                      ? null
                      : () => _openInvoiceServicePicker(context, ref, draft),
                  icon: const Icon(Icons.content_cut_rounded, size: 16),
                  label: const Text('Thêm dịch vụ'),
                ),
                TextButton.icon(
                  onPressed: draft.isPaid
                      ? null
                      : () => _openInvoiceProductPicker(context, ref, draft),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                  label: const Text('Thêm sản phẩm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceLineTile extends ConsumerWidget {
  const _InvoiceLineTile({required this.line, required this.isLocked});

  final InvoiceDraftLine line;
  final bool isLocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitPrice = line.unitPrice;
    final quantity = line.quantity;
    final lineTotal = line.totalPrice;
    final hasDiscount = line.discountAmount > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 540;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.panelRaised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (line.isProduct)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.selectedSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SP',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.copper,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            line.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: isLocked
                              ? null
                              : () => _removeInvoiceLine(context, ref, line),
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Đơn giá: ${_currency(unitPrice)}'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QtyButton(
                              icon: Icons.remove,
                              onTap: isLocked || quantity <= 1
                                  ? null
                                  : () => _updateInvoiceLineQuantity(
                                      context,
                                      ref,
                                      line,
                                      quantity - 1,
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text('$quantity'),
                            ),
                            _QtyButton(
                              icon: Icons.add,
                              onTap: isLocked
                                  ? null
                                  : () => _updateInvoiceLineQuantity(
                                      context,
                                      ref,
                                      line,
                                      quantity + 1,
                                    ),
                            ),
                          ],
                        ),
                        if (hasDiscount)
                          Text(
                            'Giảm: ${_currency(line.discountAmount)}',
                            style: TextStyle(color: AppColors.copper),
                          ),
                        Text(
                          'Thành tiền: ${_currency(lineTotal)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (!isLocked)
                          GestureDetector(
                            onTap: () =>
                                _openLineDiscountEditor(context, ref, line),
                            child: Text(
                              'Giảm giá dòng',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (line.isProduct)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.selectedSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SP',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.copper,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Expanded(
                          flex: 5,
                          child: Text(
                            line.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(flex: 2, child: Text(_currency(unitPrice))),
                        Expanded(
                          flex: 2,
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Row(
                              children: [
                                _QtyButton(
                                  icon: Icons.remove,
                                  onTap: isLocked || quantity <= 1
                                      ? null
                                      : () => _updateInvoiceLineQuantity(
                                          context,
                                          ref,
                                          line,
                                          quantity - 1,
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text('$quantity'),
                                ),
                                _QtyButton(
                                  icon: Icons.add,
                                  onTap: isLocked
                                      ? null
                                      : () => _updateInvoiceLineQuantity(
                                          context,
                                          ref,
                                          line,
                                          quantity + 1,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: FittedBox(
                            alignment: Alignment.centerRight,
                            fit: BoxFit.scaleDown,
                            child: Row(
                              children: [
                                Text(
                                  _currency(lineTotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  onPressed: isLocked
                                      ? null
                                      : () => _removeInvoiceLine(
                                          context,
                                          ref,
                                          line,
                                        ),
                                  icon: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasDiscount || !isLocked) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (hasDiscount) ...[
                            const SizedBox(width: 4),
                            Text(
                              'Giảm dòng: ${_currency(line.discountAmount)}',
                              style: TextStyle(
                                color: AppColors.copper,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (!isLocked)
                            GestureDetector(
                              onTap: () =>
                                  _openLineDiscountEditor(context, ref, line),
                              child: Text(
                                hasDiscount
                                    ? 'Sửa giảm giá dòng'
                                    : 'Giảm giá dòng',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? AppColors.textMuted : null,
        ),
      ),
    );
  }
}

class _PaymentSummaryPanel extends ConsumerWidget {
  const _PaymentSummaryPanel({
    required this.draft,
    required this.history,
    required this.allCustomers,
    required this.selectedCustomer,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> allCustomers;
  final CustomerProfile? selectedCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = selectedCustomer;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thanh toán',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (customer != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.panelRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.copper.withValues(
                                alpha: 0.18,
                              ),
                              foregroundColor: AppColors.textPrimary,
                              child: Text(customer.initials),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    customer.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    customer.phone,
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: draft.isPaid
                                  ? null
                                  : () =>
                                        ref
                                                .read(
                                                  invoiceCustomerQueryProvider
                                                      .notifier,
                                                )
                                                .state =
                                            '',
                              child: const Text('Đổi khách'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    _AmountRow(
                      label: 'Tạm tính',
                      value: _currency(draft.subtotal),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _AmountRow(
                            label: 'Giảm giá',
                            value: _currency(draft.discountAmount),
                          ),
                        ),
                        TextButton(
                          onPressed: draft.isPaid
                              ? null
                              : () => _openDiscountEditor(context, ref, draft),
                          child: const Text('Sửa giảm giá'),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    _AmountRow(
                      label: 'Thành tiền',
                      value: _currency(draft.totalAmount),
                      emphasized: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Phương thức thanh toán',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppChoiceButton(
                            label: 'Tiền mặt',
                            selected: draft.paymentMethod == 'Tiền mặt',
                            onTap: draft.isPaid
                                ? null
                                : () => _updateInvoicePaymentMethod(
                                    context,
                                    ref,
                                    'Tiền mặt',
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppChoiceButton(
                            label: 'Chuyển khoản',
                            selected: draft.paymentMethod == 'Chuyển khoản',
                            onTap: draft.isPaid
                                ? null
                                : () => _updateInvoicePaymentMethod(
                                    context,
                                    ref,
                                    'Chuyển khoản',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppChoiceButton(
                            label: 'Thẻ',
                            selected: draft.paymentMethod == 'Thẻ',
                            onTap: draft.isPaid
                                ? null
                                : () => _updateInvoicePaymentMethod(
                                    context,
                                    ref,
                                    'Thẻ',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (draft.paidAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Đã thanh toán lúc ${draft.paidAt!.hour.toString().padLeft(2, '0')}:${draft.paidAt!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _InvoiceHistoryPanel(
                      history: history,
                      customers: allCustomers,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: draft.isPaid || draft.lines.isEmpty
                    ? null
                    : () => _checkoutInvoice(context, ref, draft),
                child: Text(
                  draft.isPaid
                      ? 'Đã thanh toán • ${_currency(draft.totalAmount)}'
                      : 'Thanh toán • ${_currency(draft.totalAmount)}',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: draft.lines.isEmpty
                        ? null
                        : () => _showPaymentQrDialog(context, draft, customer),
                    icon: const Icon(Icons.qr_code_2_outlined),
                    label: const Text('QR thanh toán'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: draft.lines.isEmpty
                        ? null
                        : () => _exportInvoicePdf(context, draft, customer),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Xuất PDF'),
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

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: emphasized ? 28 : 16,
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
      color: emphasized ? AppColors.copper : AppColors.textPrimary,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 320;

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: emphasized
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: style),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: emphasized
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: style),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InvoiceDiscountDialog extends StatefulWidget {
  const _InvoiceDiscountDialog({
    required this.currentDiscount,
    required this.maxDiscount,
  });

  final int currentDiscount;
  final int maxDiscount;

  @override
  State<_InvoiceDiscountDialog> createState() => _InvoiceDiscountDialogState();
}

class _InvoiceDiscountDialogState extends State<_InvoiceDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _discountController;

  @override
  void initState() {
    super.initState();
    _discountController = TextEditingController(
      text: widget.currentDiscount.toString(),
    );
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Cập nhật giảm giá'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 420),
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _discountController,
            decoration: InputDecoration(
              labelText: 'Giảm giá (đ)',
              helperText: 'Tối đa ${_currency(widget.maxDiscount)}',
            ),
            validator: (value) {
              final amount = int.tryParse(value?.trim() ?? '');
              if (amount == null || amount < 0) {
                return 'Nhập số tiền hợp lệ';
              }
              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu giảm giá')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = int.parse(_discountController.text.trim());
    final normalized = amount > widget.maxDiscount
        ? widget.maxDiscount
        : amount;
    Navigator.of(context).pop(normalized);
  }
}

class _InvoiceServicePickerDialog extends StatelessWidget {
  const _InvoiceServicePickerDialog({
    required this.services,
    required this.existingServiceIds,
  });

  final List<ServiceCatalogItem> services;
  final Set<String> existingServiceIds;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Thêm dịch vụ vào hóa đơn'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: services
                .map(
                  (service) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => Navigator.of(context).pop(service),
                    title: Text(service.name),
                    subtitle: Text(
                      '${service.category} â€¢ ${service.durationLabel} â€¢ ${service.priceLabel}',
                    ),
                    trailing: existingServiceIds.contains(service.id)
                        ? Text(
                            'Tăng SL',
                            style: TextStyle(color: AppColors.copper),
                          )
                        : const Icon(Icons.add),
                  ),
                )
                .toList(),
          ),
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

class _InvoiceHistoryPanel extends StatelessWidget {
  const _InvoiceHistoryPanel({required this.history, required this.customers});

  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panelRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lịch sử thanh toán gần đây',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Text(
              'Chưa có hóa đơn đã thanh toán.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            ...history.map((invoice) {
              CustomerProfile? customer;
              for (final item in customers) {
                if (item.id == invoice.customerId) {
                  customer = item;
                  break;
                }
              }

              final paidAt = invoice.paidAt!;
              final paidTime =
                  '${paidAt.day.toString().padLeft(2, '0')}/${paidAt.month.toString().padLeft(2, '0')} '
                  '${paidAt.hour.toString().padLeft(2, '0')}:${paidAt.minute.toString().padLeft(2, '0')}';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer?.fullName ?? invoice.customerId,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _currency(invoice.totalAmount),
                          style: TextStyle(
                            color: AppColors.copper,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$paidTime • ${invoice.paymentMethod} • ${invoice.lines.length} dịch vụ',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                    if (invoice.appointmentId != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Từ lịch hẹn ${invoice.appointmentId}',
                        style: TextStyle(
                          color: AppColors.copper,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _InvoiceProductPickerDialog extends StatelessWidget {
  const _InvoiceProductPickerDialog({
    required this.products,
    required this.existingProductIds,
    required this.onCreateProduct,
  });

  final List<RetailProductItem> products;
  final Set<String> existingProductIds;
  final Future<void> Function() onCreateProduct;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Thêm sản phẩm vào hóa đơn'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: products.isEmpty
                ? [
                    const Text(
                      'Chưa có sản phẩm nào. Vui lòng thêm sản phẩm trước.',
                    ),
                  ]
                : products
                      .map(
                        (product) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => Navigator.of(context).pop(product),
                          title: Text(product.name),
                          subtitle: Text(
                            '${product.productType}${product.brand.isNotEmpty ? ' â€¢ ${product.brand}' : ''} â€¢ ${product.salePriceLabel}',
                          ),
                          trailing: existingProductIds.contains(product.id)
                              ? Text(
                                  'Tăng SL',
                                  style: TextStyle(color: AppColors.copper),
                                )
                              : const Icon(Icons.add),
                        ),
                      )
                      .toList(),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: onCreateProduct,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Thêm sản phẩm mới'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class _RetailProductEditorDialog extends StatefulWidget {
  const _RetailProductEditorDialog({required this.onSave});

  final Future<RetailProductItem> Function(RetailProductUpsertInput input)
  onSave;

  @override
  State<_RetailProductEditorDialog> createState() =>
      _RetailProductEditorDialogState();
}

class _RetailProductEditorDialogState
    extends State<_RetailProductEditorDialog> {
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
      backgroundColor: AppColors.panel,
      title: const Text('Thêm sản phẩm bán lẻ'),
      content: SizedBox(
        width: adaptiveDialogWidth(context, 480),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Nhập tên sản phẩm'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(labelText: 'Thương hiệu'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _volumeController,
                  decoration: const InputDecoration(
                    labelText: 'Dung tích/Quy cách',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Nhóm sản phẩm'),
                  items: RetailProductUpsertInput.productTypes
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
                      _type = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Giá bán (đ)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final parsed = int.tryParse(value?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Nhập giá hợp lệ';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: const Text('Lưu sản phẩm'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

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
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(created);
  }
}

String _currency(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    final reverseIndex = digits.length - index;
    buffer.write(digits[index]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) {
      buffer.write('.');
    }
  }

  return '${value < 0 ? '-' : ''}${buffer.toString()}đ';
}
