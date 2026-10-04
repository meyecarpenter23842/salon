enum InvoiceAdjustmentType {
  refund,
  voided;

  String get databaseValue => switch (this) {
    InvoiceAdjustmentType.refund => 'refund',
    InvoiceAdjustmentType.voided => 'void',
  };

  String get actionLabel => switch (this) {
    InvoiceAdjustmentType.refund => 'Hoàn tiền toàn bộ',
    InvoiceAdjustmentType.voided => 'Hủy giao dịch',
  };

  String get statusLabel => switch (this) {
    InvoiceAdjustmentType.refund => 'Đã hoàn tiền',
    InvoiceAdjustmentType.voided => 'Đã hủy giao dịch',
  };

  static InvoiceAdjustmentType fromDatabase(String value) {
    return switch (value.trim().toLowerCase()) {
      'refund' => InvoiceAdjustmentType.refund,
      'void' => InvoiceAdjustmentType.voided,
      _ => throw StateError('Unknown invoice adjustment type: $value'),
    };
  }
}

class InvoiceAdjustment {
  const InvoiceAdjustment({
    required this.id,
    required this.invoiceId,
    required this.type,
    required this.reason,
    required this.amount,
    required this.paymentMethod,
    required this.customerId,
    required this.appointmentId,
    required this.createdAt,
  });

  final String id;
  final String invoiceId;
  final InvoiceAdjustmentType type;
  final String reason;
  final int amount;
  final String paymentMethod;
  final String customerId;
  final String? appointmentId;
  final DateTime createdAt;
}
