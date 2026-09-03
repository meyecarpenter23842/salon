part of 'appointments_page.dart';

class _AppointmentInvoiceSummary extends StatelessWidget {
  const _AppointmentInvoiceSummary({required this.invoiceState});

  final AsyncValue<InvoiceDraft?> invoiceState;

  @override
  Widget build(BuildContext context) {
    return invoiceState.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => _DetailInfoTile(
        icon: Icons.receipt_long_outlined,
        label: 'Hóa đơn',
        value: 'Không tải được: $error',
      ),
      data: (invoice) {
        if (invoice == null) {
          return const _DetailInfoTile(
            icon: Icons.receipt_long_outlined,
            label: 'Hóa đơn',
            value: 'Chưa có hóa đơn đã thanh toán',
          );
        }
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.selectedSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              PremiumIconBadge(
                icon: Icons.receipt_long_outlined,
                size: 32,
                tone: AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_currency(invoice.totalAmount)} • ${invoice.paymentMethod}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
