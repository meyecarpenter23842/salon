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
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

part 'pos_bill_panel.dart';
part 'pos_catalog_panel.dart';
part 'pos_checkout_panel.dart';
part 'pos_dialogs.dart';

enum _PosCatalogKind { services, products }

final _invoiceCatalogKindProvider = StateProvider<_PosCatalogKind>(
  (ref) => _PosCatalogKind.services,
);
final _invoiceCatalogQueryProvider = StateProvider<String>((ref) => '');

Future<void> _selectInvoiceCustomer(
  BuildContext context,
  WidgetRef ref,
  CustomerProfile customer,
) async {
  await ref.read(invoicesRepositoryProvider).selectInvoiceCustomer(customer.id);
  if (!context.mounted) return;
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
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
}

Future<void> _addInvoiceService(
  BuildContext context,
  WidgetRef ref,
  ServiceCatalogItem service,
) async {
  await ref.read(invoicesRepositoryProvider).addInvoiceService(service.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Đã thêm ${service.name} vào bill')));
}

Future<void> _addInvoiceProduct(
  BuildContext context,
  WidgetRef ref,
  RetailProductItem product,
) async {
  await ref.read(invoicesRepositoryProvider).addInvoiceProduct(product.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Đã thêm ${product.name} vào bill')));
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
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
}

Future<void> _removeInvoiceLine(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
) async {
  await ref.read(invoicesRepositoryProvider).removeInvoiceLine(line.id);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Đã xóa ${line.title} khỏi bill')));
}

Future<void> _openDiscountEditor(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraft draft,
) async {
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
}

Future<void> _openLineDiscountEditor(
  BuildContext context,
  WidgetRef ref,
  InvoiceDraftLine line,
) async {
  final discount = await showAppDialog<int>(
    context: context,
    builder: (_) => _InvoiceDiscountDialog(
      currentDiscount: line.discountAmount,
      maxDiscount: line.subtotal,
    ),
  );
  if (discount == null || !context.mounted) return;
  await ref
      .read(invoicesRepositoryProvider)
      .updateInvoiceLineDiscount(line.id, discount);
  if (!context.mounted) return;
  ref.invalidate(invoiceDraftProvider);
}

Future<RetailProductItem?> _openRetailProductEditor(
  BuildContext context,
  WidgetRef ref,
) {
  return showAppDialog<RetailProductItem>(
    context: context,
    builder: (_) => _RetailProductEditorDialog(
      onSave: (input) =>
          ref.read(retailProductsRepositoryProvider).saveProduct(input),
    ),
  );
}

Future<void> _createProductAndAdd(BuildContext context, WidgetRef ref) async {
  final product = await _openRetailProductEditor(context, ref);
  if (product == null || !context.mounted) return;
  ref.invalidate(retailProductsViewProvider);
  await _addInvoiceProduct(context, ref, product);
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 210,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _currency(draft.totalAmount),
              style: Theme.of(dialogContext).textTheme.displayMedium
                  ?.copyWith(color: AppColors.copper),
            ),
            const SizedBox(height: 6),
            Text(
              customer?.fullName ?? draft.customerId,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
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
        build: (_) => [
          pw.Text(
            'PHIEU THANH TOAN',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Ma hoa don: ${draft.id}'),
          pw.Text('Khach hang: ${customer?.fullName ?? draft.customerId}'),
          pw.Text('SDT: ${customer?.phone ?? '-'}'),
          pw.Text(
            'Ngay tao: ${generatedAt.day}/${generatedAt.month}/${generatedAt.year} '
            '${generatedAt.hour.toString().padLeft(2, '0')}:'
            '${generatedAt.minute.toString().padLeft(2, '0')}',
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã xuất PDF hóa đơn: $filePath')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Xuất PDF thất bại: $error')));
  }
}

class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftState = ref.watch(invoiceDraftProvider);
    final historyState = ref.watch(invoiceHistoryProvider);
    final customersState = ref.watch(customersViewProvider);
    final servicesState = ref.watch(servicesViewProvider);
    final productsState = ref.watch(retailProductsViewProvider);

    return draftState.when(
      data: (draft) => historyState.when(
        data: (history) => customersState.when(
          data: (customers) => _BillingView(
            draft: draft,
            history: history,
            customers: customers,
            servicesState: servicesState,
            productsState: productsState,
          ),
          loading: () =>
              const PremiumLoadingState(label: 'Đang tải khách hàng…'),
          error: (error, _) => PremiumErrorState(
            title: 'Không tải được khách hàng',
            message: '$error',
            onRetry: () => ref.invalidate(customersViewProvider),
          ),
        ),
        loading: () =>
            const PremiumLoadingState(label: 'Đang tải lịch sử hóa đơn…'),
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

class _BillingView extends StatelessWidget {
  const _BillingView({
    required this.draft,
    required this.history,
    required this.customers,
    required this.servicesState,
    required this.productsState,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;
  final AsyncValue<List<ServiceCatalogItem>> servicesState;
  final AsyncValue<List<RetailProductItem>> productsState;

  @override
  Widget build(BuildContext context) {
    CustomerProfile? selectedCustomer;
    for (final customer in customers) {
      if (customer.id == draft.customerId) {
        selectedCustomer = customer;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense =
            constraints.maxWidth < 1180 || constraints.maxHeight < 720;
        final gap = dense ? 10.0 : 14.0;

        return Column(
          key: const Key('billing-premium-workspace'),
          children: [
            _PosHeader(
              draft: draft,
              history: history,
              customers: customers,
              dense: dense,
            ),
            SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
                    child: _InvoiceDraftPanel(draft: draft, dense: dense),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 5,
                    child: _CatalogPanel(
                      draft: draft,
                      servicesState: servicesState,
                      productsState: productsState,
                      dense: dense,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    flex: 5,
                    child: _CheckoutPanel(
                      draft: draft,
                      customers: customers,
                      selectedCustomer: selectedCustomer,
                      dense: dense,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PosHeader extends StatelessWidget {
  const _PosHeader({
    required this.draft,
    required this.history,
    required this.customers,
    required this.dense,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('billing-premium-header'),
      height: 42,
      child: Row(
        children: [
          PremiumStatusPill(
            label: draft.isPaid ? 'Đã thanh toán' : 'Đang lập bill',
            tone: draft.isPaid ? AppColors.success : AppColors.copper,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${draft.lines.length} mục · ${_currency(draft.subtotal)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!dense) ...[
            const SizedBox(width: 8),
            Text(
              '• ${draft.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
            ),
          ],
          const Spacer(),
          OutlinedButton.icon(
            key: const Key('billing-history-action'),
            onPressed: () =>
                _showInvoiceHistoryDialog(context, history, customers),
            icon: const Icon(Icons.history_rounded, size: 17),
            label: const Text('Lịch sử hóa đơn'),
          ),
        ],
      ),
    );
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
