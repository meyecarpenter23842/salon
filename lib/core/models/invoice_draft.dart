import 'invoice_draft_line.dart';

class InvoiceDraft {
  InvoiceDraft({
    required this.id,
    this.appointmentId,
    required this.customerId,
    required this.discountAmount,
    required this.paymentMethod,
    required this.createdAt,
    required this.updatedAt,
    required this.lines,
    this.paidAt,
  });

  final String id;
  final String? appointmentId;
  final String customerId;
  final int discountAmount;
  final String paymentMethod;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<InvoiceDraftLine> lines;

  static const List<String> paymentMethods = [
    'Tiền mặt',
    'Chuyển khoản',
    'Thẻ',
  ];

  int get subtotal => lines.fold(0, (sum, line) => sum + line.totalPrice);

  int get totalAmount {
    final total = subtotal - discountAmount;
    return total < 0 ? 0 : total;
  }

  bool get isPaid => paidAt != null;

  InvoiceDraft copyWith({
    String? id,
    String? appointmentId,
    String? customerId,
    int? discountAmount,
    String? paymentMethod,
    DateTime? paidAt,
    bool clearPaidAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<InvoiceDraftLine>? lines,
  }) {
    return InvoiceDraft(
      id: id ?? this.id,
      appointmentId: appointmentId ?? this.appointmentId,
      customerId: customerId ?? this.customerId,
      discountAmount: discountAmount ?? this.discountAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAt: clearPaidAt ? null : paidAt ?? this.paidAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lines: lines ?? this.lines,
    );
  }

  static String normalizePaymentMethod(String value) {
    final normalizedValue = value.trim().toLowerCase();
    for (final method in paymentMethods) {
      if (method.toLowerCase() == normalizedValue) {
        return method;
      }
    }

    return paymentMethods.first;
  }
}
