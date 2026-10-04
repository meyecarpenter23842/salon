import '../models/invoice_adjustment.dart';

abstract interface class InvoiceAdjustmentRepository {
  Future<List<InvoiceAdjustment>> fetchInvoiceAdjustments({
    String? invoiceId,
    int? limit,
  });

  Future<InvoiceAdjustment> refundInvoice(
    String invoiceId, {
    required String reason,
  });

  Future<InvoiceAdjustment> voidInvoice(
    String invoiceId, {
    required String reason,
  });
}
