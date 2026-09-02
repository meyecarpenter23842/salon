import '../models/invoice_draft.dart';

class InvoiceMapper {
  const InvoiceMapper._();

  static InvoiceDraft fromDatabase(
    Map<String, Object?> row, {
    required List<dynamic> lines,
  }) {
    return InvoiceDraft(
      id: row['id'].toString(),
      appointmentId: row['appointment_id']?.toString(),
      customerId: row['customer_id'].toString(),
      discountAmount: _toInt(row['discount_amount']),
      paymentMethod: InvoiceDraft.normalizePaymentMethod(
        row['payment_method']?.toString() ?? '',
      ),
      paidAt: _parseDateTime(row['paid_at']),
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
      lines: lines.cast(),
    );
  }

  static Map<String, Object?> toDatabase(InvoiceDraft draft) {
    return {
      'id': draft.id,
      'appointment_id': draft.appointmentId,
      'customer_id': draft.customerId,
      'subtotal': draft.subtotal,
      'discount_amount': draft.discountAmount,
      'total_amount': draft.totalAmount,
      'payment_method': draft.paymentMethod,
      'paid_at': draft.paidAt?.toIso8601String(),
      'created_at': draft.createdAt.toIso8601String(),
      'updated_at': draft.updatedAt.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
