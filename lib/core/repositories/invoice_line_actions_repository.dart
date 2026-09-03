import '../models/invoice_draft.dart';

abstract interface class InvoiceLineActionsRepository {
  Future<InvoiceDraft> splitInvoiceLine(String lineId);
}
