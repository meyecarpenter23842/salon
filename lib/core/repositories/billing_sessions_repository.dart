import '../models/appointment_entry.dart';
import '../models/invoice_draft.dart';

abstract interface class BillingSessionsRepository {
  Future<List<InvoiceDraft>> fetchActiveSessions();

  Future<InvoiceDraft> fetchSession(String sessionId);

  Future<InvoiceDraft> openAppointmentSession(AppointmentEntry appointment);

  Future<InvoiceDraft> createWalkInSession();

  Future<InvoiceDraft> selectCustomer(String sessionId, String customerId);

  Future<InvoiceDraft> updatePaymentMethod(
    String sessionId,
    String paymentMethod,
  );

  Future<InvoiceDraft> updateDiscount(String sessionId, int discountAmount);

  Future<InvoiceDraft> addService(
    String sessionId,
    String serviceId, {
    String? employeeId,
  });

  Future<InvoiceDraft> addProduct(String sessionId, String productId);

  Future<InvoiceDraft> updateLineQuantity(
    String sessionId,
    String lineId,
    int quantity,
  );

  Future<InvoiceDraft> updateLineDiscount(
    String sessionId,
    String lineId,
    int discountAmount,
  );

  Future<InvoiceDraft> updateLineEmployee(
    String sessionId,
    String lineId,
    String? employeeId,
  );

  Future<InvoiceDraft> updateLineUnitPrice(
    String sessionId,
    String lineId,
    int unitPrice,
  );

  Future<InvoiceDraft> splitLine(String sessionId, String lineId);

  Future<InvoiceDraft> removeLine(String sessionId, String lineId);

  Future<InvoiceDraft> checkout(String sessionId);
}
