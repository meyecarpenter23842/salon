import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_payment_allocation.dart';
import 'billing_sessions_repository.dart';
import 'guarded_salon_repositories.dart';
import 'sqlite_invoices_repository.dart';

class SqliteBillingSessionsRepository implements BillingSessionsRepository {
  SqliteBillingSessionsRepository(this._database);

  final SalonDatabase _database;
  final Set<String> _checkoutInFlight = <String>{};
  int _walkInSequence = 0;

  @override
  Future<List<InvoiceDraft>> fetchActiveSessions() async {
    final database = await _database.database;
    final drafts = <String, InvoiceDraft>{};

    final invoiceRows = await database.query(
      'invoices',
      columns: const ['id'],
      where: 'paid_at IS NULL',
      orderBy: 'updated_at DESC',
    );
    for (final row in invoiceRows) {
      final sessionId = row['id']?.toString().trim() ?? '';
      if (sessionId.isEmpty) {
        continue;
      }
      drafts[sessionId] = await _raw(sessionId).fetchInvoiceDraft();
    }

    final stateRows = await database.query(
      'app_settings',
      columns: const ['key'],
      where: 'key = ? OR key LIKE ?',
      whereArgs: [
        SqliteInvoicesRepository.legacyDraftStateSettingsKey,
        '${SqliteInvoicesRepository.sessionDraftStateSettingsPrefix}%',
      ],
    );
    for (final row in stateRows) {
      final key = row['key']?.toString() ?? '';
      final sessionId = _sessionIdFromStateKey(key);
      if (sessionId == null || drafts.containsKey(sessionId)) {
        continue;
      }
      final draft = await _raw(sessionId).fetchInvoiceDraft();
      if (!draft.isPaid) {
        drafts[sessionId] = draft;
      }
    }

    final results = drafts.values.toList(growable: false);
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }

  @override
  Future<InvoiceDraft> fetchSession(String sessionId) {
    final normalized = _normalizeSessionId(sessionId);
    return _raw(normalized).fetchInvoiceDraft();
  }

  @override
  Future<InvoiceDraft> openAppointmentSession(
    AppointmentEntry appointment,
  ) async {
    final appointmentId = appointment.id.trim();
    if (appointmentId.isEmpty) {
      throw ArgumentError.value(
        appointment.id,
        'appointment.id',
        'Appointment id cannot be empty.',
      );
    }

    final activeSessions = await fetchActiveSessions();
    for (final draft in activeSessions) {
      if (draft.appointmentId == appointmentId) {
        return draft;
      }
    }

    final sessionId = 'invoice-draft-appointment-$appointmentId';
    return _guarded(sessionId).prefillDraftFromAppointment(appointment);
  }

  @override
  Future<InvoiceDraft> createWalkInSession() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final sequence = _walkInSequence++;
    final sessionId = 'invoice-draft-walkin-$now-$sequence';
    return _raw(sessionId).createEmptyDraft();
  }

  @override
  Future<InvoiceDraft> selectCustomer(String sessionId, String customerId) {
    return _guarded(_normalizeSessionId(sessionId))
        .selectInvoiceCustomer(customerId);
  }

  @override
  Future<InvoiceDraft> updatePaymentMethod(
    String sessionId,
    String paymentMethod,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoicePaymentMethod(paymentMethod);
  }

  @override
  Future<InvoiceDraft> updatePaymentAllocations(
    String sessionId,
    List<InvoicePaymentAllocation> allocations,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoicePaymentAllocations(allocations);
  }

  @override
  Future<InvoiceDraft> updateDiscount(
    String sessionId,
    int discountAmount,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoiceDiscount(discountAmount);
  }

  @override
  Future<InvoiceDraft> addService(
    String sessionId,
    String serviceId, {
    String? employeeId,
  }) {
    return _guarded(_normalizeSessionId(sessionId)).addInvoiceService(
      serviceId,
      employeeId: employeeId,
    );
  }

  @override
  Future<InvoiceDraft> addProduct(String sessionId, String productId) {
    return _guarded(_normalizeSessionId(sessionId))
        .addInvoiceProduct(productId);
  }

  @override
  Future<InvoiceDraft> updateLineQuantity(
    String sessionId,
    String lineId,
    int quantity,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoiceLineQuantity(lineId, quantity);
  }

  @override
  Future<InvoiceDraft> updateLineDiscount(
    String sessionId,
    String lineId,
    int discountAmount,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoiceLineDiscount(lineId, discountAmount);
  }

  @override
  Future<InvoiceDraft> updateLineEmployee(
    String sessionId,
    String lineId,
    String? employeeId,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoiceLineEmployee(lineId, employeeId);
  }

  @override
  Future<InvoiceDraft> updateLineUnitPrice(
    String sessionId,
    String lineId,
    int unitPrice,
  ) {
    return _guarded(_normalizeSessionId(sessionId))
        .updateInvoiceLineUnitPrice(lineId, unitPrice);
  }

  @override
  Future<InvoiceDraft> splitLine(String sessionId, String lineId) {
    return _guarded(_normalizeSessionId(sessionId)).splitInvoiceLine(lineId);
  }

  @override
  Future<InvoiceDraft> removeLine(String sessionId, String lineId) {
    return _guarded(_normalizeSessionId(sessionId)).removeInvoiceLine(lineId);
  }

  @override
  Future<InvoiceDraft> checkout(String sessionId) async {
    final normalized = _normalizeSessionId(sessionId);
    if (!_checkoutInFlight.add(normalized)) {
      throw StateError(
        'Thanh toán đang được xử lý. Không thể chốt trùng hóa đơn.',
      );
    }

    try {
      return await _guarded(normalized).checkoutInvoice();
    } finally {
      _checkoutInFlight.remove(normalized);
    }
  }

  SqliteInvoicesRepository _raw(String sessionId) {
    return SqliteInvoicesRepository(_database, null, sessionId);
  }

  GuardedInvoicesRepository _guarded(String sessionId) {
    return GuardedInvoicesRepository(_database, _raw(sessionId));
  }

  String _normalizeSessionId(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'Billing session id cannot be empty.',
      );
    }
    return normalized;
  }

  String? _sessionIdFromStateKey(String key) {
    if (key == SqliteInvoicesRepository.legacyDraftStateSettingsKey) {
      return SqliteInvoicesRepository.legacyDraftInvoiceId;
    }

    const prefix = SqliteInvoicesRepository.sessionDraftStateSettingsPrefix;
    if (!key.startsWith(prefix)) {
      return null;
    }

    final sessionId = key.substring(prefix.length).trim();
    return sessionId.isEmpty ? null : sessionId;
  }
}
