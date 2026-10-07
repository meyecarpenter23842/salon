class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.isActive,
    required this.revision,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final int revision;
  final DateTime updatedAt;
}

class ExpenseEntry {
  const ExpenseEntry({
    required this.id,
    required this.kind,
    required this.categoryId,
    required this.categoryName,
    required this.date,
    required this.payee,
    required this.amount,
    required this.reason,
    required this.externalReference,
    required this.actor,
    required this.createdAt,
    this.originalId,
  });

  final String id;
  final String kind;
  final String? originalId;
  final String categoryId;
  final String categoryName;
  final DateTime date;
  final String payee;
  final int amount;
  final String reason;
  final String externalReference;
  final String actor;
  final DateTime createdAt;
}

class ExpensePayment {
  const ExpensePayment({
    required this.id,
    required this.expenseId,
    required this.kind,
    required this.amount,
    required this.method,
    required this.reference,
    required this.note,
    required this.actor,
    required this.createdAt,
    this.originalPaymentId,
    this.cashMovementId,
  });

  final String id;
  final String expenseId;
  final String kind;
  final String? originalPaymentId;
  final int amount;
  final String method;
  final String reference;
  final String note;
  final String actor;
  final String? cashMovementId;
  final DateTime createdAt;
}

class ExpenseAccount {
  const ExpenseAccount({
    required this.expense,
    required this.paid,
    required this.reversed,
  });

  final ExpenseEntry expense;
  final int paid;
  final bool reversed;

  int get balance => reversed ? 0 : expense.amount - paid;

  String get state {
    if (reversed) return 'reversed';
    if (paid <= 0) return 'unpaid';
    if (balance <= 0) return 'paid';
    return 'partial';
  }
}

class ExpenseSnapshot {
  const ExpenseSnapshot({
    required this.categories,
    required this.accounts,
    required this.payments,
    required this.pendingPayment,
  });

  final List<ExpenseCategory> categories;
  final List<ExpenseAccount> accounts;
  final List<ExpensePayment> payments;
  final Map<String, Object?>? pendingPayment;
}
