import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/models/customer_profile.dart';
import '../../../../core/models/invoice_draft.dart';
import '../../../../core/models/invoice_draft_line.dart';
import '../../../../core/models/receipt_template_config.dart';
import '../../../../core/models/retail_product_item.dart';
import '../../../../core/models/retail_product_upsert_input.dart';
import '../../../../core/models/service_catalog_item.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/settings/receipt_template_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_motion.dart';
import '../../../../shared/widgets/app_primitives.dart';
import '../../../../shared/widgets/premium_workspace.dart';

part 'pos_bill_panel.dart';
part 'pos_catalog_panel.dart';
part 'pos_checkout_panel.dart';
part 'pos_dialogs.dart';
part 'receipt_pdf_renderer.dart';
part 'receipt_settings_dialog.dart';

enum _PosCatalogKind { services, products }

final _invoiceCatalogKindProvider = StateProvider<_PosCatalogKind>(
  (ref) => _PosCatalogKind.services,
);
final _invoiceCatalogQueryProvider = StateProvider<String>((ref) => '');
final _invoiceServiceEmployeeIdProvider = StateProvider<String?>((ref) => null);

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
  String? employeeId,
) async {
  if (employeeId == null || employeeId.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chọn nhân viên thực hiện trước khi thêm dịch vụ.'),
      ),
    );
    return;
  }
  await ref
      .read(invoicesRepositoryProvider)
      .addInvoiceService(service.id, employeeId: employeeId);
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
    final file = await _createInvoicePdfFile(draft, customer);
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        ['/select,${file.path}'],
        mode: ProcessStartMode.detached,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xuất PDF hóa đơn: ${file.path}')),
    );
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
    final employeesState = ref.watch(employeesViewProvider);

    return draftState.when(
      data: (draft) => historyState.when(
        data: (history) => customersState.when(
          data: (customers) => _BillingView(
            draft: draft,
            history: history,
            customers: customers,
            servicesState: servicesState,
            productsState: productsState,
            employeesState: employeesState,
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
    required this.employeesState,
  });

  final InvoiceDraft draft;
  final List<InvoiceDraft> history;
  final List<CustomerProfile> customers;
  final AsyncValue<List<ServiceCatalogItem>> servicesState;
  final AsyncValue<List<RetailProductItem>> productsState;
  final AsyncValue<List<Map<String, Object?>>> employeesState;

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
                      employeesState: employeesState,
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

class _PosHeader extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsViewProvider).valueOrNull;
    final salonName = settings?['salonName']?.toString() ?? 'Hair Spa Manager';

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
          if (dense)
            IconButton(
              key: const Key('billing-receipt-settings-action'),
              tooltip: 'Thiết lập phiếu in',
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => _ReceiptSettingsDialog(
                  fallbackSalonName: salonName,
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
            )
          else ...[
            OutlinedButton.icon(
              key: const Key('billing-receipt-settings-action'),
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => _ReceiptSettingsDialog(
                  fallbackSalonName: salonName,
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Phiếu in'),
            ),
            const SizedBox(width: 8),
          ],
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
