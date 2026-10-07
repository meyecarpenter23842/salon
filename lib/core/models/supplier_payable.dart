class SupplierPayableObligation {
  const SupplierPayableObligation({
    required this.id,
    required this.kind,
    required this.supplierId,
    required this.supplierName,
    required this.sourceType,
    required this.sourceNumber,
    required this.sourceDate,
    required this.amount,
    required this.reason,
    required this.externalReference,
    required this.actor,
    required this.createdAt,
    this.originalId,
    this.sourceId,
  });

  final String id;
  final String kind;
  final String? originalId;
  final String supplierId;
  final String supplierName;
  final String sourceType;
  final String? sourceId;
  final String sourceNumber;
  final DateTime sourceDate;
  final int amount;
  final String reason;
  final String externalReference;
  final String actor;
  final DateTime createdAt;
}

class SupplierPayableAccount {
  const SupplierPayableAccount({
    required this.obligation,
    required this.paid,
    required this.reversed,
  });

  final SupplierPayableObligation obligation;
  final int paid;
  final bool reversed;

  int get balance => reversed ? 0 : obligation.amount - paid;

  String get state {
    if (reversed) return 'reversed';
    if (paid <= 0) return 'unpaid';
    if (balance <= 0) return 'paid';
    return 'partial';
  }
}

class SupplierPaymentAllocationInput {
  const SupplierPaymentAllocationInput({
    required this.obligationId,
    required this.amount,
  });

  final String obligationId;
  final int amount;
}

class SupplierPaymentAllocation {
  const SupplierPaymentAllocation({
    required this.id,
    required this.paymentId,
    required this.obligationId,
    required this.amount,
  });

  final String id;
  final String paymentId;
  final String obligationId;
  final int amount;
}

class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.kind,
    required this.amount,
    required this.method,
    required this.reference,
    required this.note,
    required this.actor,
    required this.createdAt,
    required this.allocations,
    this.originalPaymentId,
    this.cashMovementId,
  });

  final String id;
  final String supplierId;
  final String supplierName;
  final String kind;
  final String? originalPaymentId;
  final int amount;
  final String method;
  final String reference;
  final String note;
  final String actor;
  final String? cashMovementId;
  final DateTime createdAt;
  final List<SupplierPaymentAllocation> allocations;
}

class SupplierPayableSnapshot {
  const SupplierPayableSnapshot({
    required this.accounts,
    required this.payments,
    required this.pendingPayment,
  });

  final List<SupplierPayableAccount> accounts;
  final List<SupplierPayment> payments;
  final Map<String, Object?>? pendingPayment;
}
