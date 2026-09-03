import '../models/invoice_draft.dart';

abstract interface class InvoiceLineActionsRepository {
  Future<InvoiceDraft> splitInvoiceLine(String lineId);

  Future<InvoiceDraft> updateInvoiceLineUnitPrice(String lineId, int unitPrice);
}
