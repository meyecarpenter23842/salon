enum FinanceBook { expense, supplier }

class FinanceAccount {
  FinanceAccount(this.book, Map<String, Object?> row, this.paid, this.reversed)
    : row = Map.unmodifiable(row);
  final FinanceBook book;
  final Map<String, Object?> row;
  final int paid;
  final bool reversed;
  String get id => row['id'] as String;
  String get entityId =>
      row[book == FinanceBook.expense ? 'category_id' : 'supplier_id']
          as String;
  String get name =>
      row[book == FinanceBook.expense ? 'category_name' : 'supplier_name']
          as String;
  String get source => book == FinanceBook.expense
      ? 'Chi phí vận hành'
      : row['source_number'] as String;
  String get sourceType =>
      book == FinanceBook.expense ? 'expense' : row['source_type'] as String;
  String? get sourceId => row['source_id'] as String?;
  DateTime get date => DateTime.parse(
    row[book == FinanceBook.expense ? 'expense_date' : 'source_date'] as String,
  );
  int get amount => row['amount'] as int;
  int get balance => reversed ? 0 : amount - paid;
  String get state => reversed
      ? 'reversed'
      : paid == 0
      ? 'unpaid'
      : balance == 0
      ? 'paid'
      : 'partial';
  String get reason => row['reason'] as String;
  String get payee => row['payee'] as String? ?? name;
  String get reference => row['external_reference'] as String;
}

class FinanceProof {
  FinanceProof(
    this.book,
    Map<String, Object?> row,
    Map<String, int> allocations,
  ) : row = Map.unmodifiable(row),
      allocations = Map.unmodifiable(allocations);
  final FinanceBook book;
  final Map<String, Object?> row;
  final Map<String, int> allocations;
  String get id => row['id'] as String;
  String get kind => row['kind'] as String;
  String? get originalId => row['original_payment_id'] as String?;
  int get amount => row['amount'] as int;
  String get method => row['method'] as String;
  String get reference => row['reference'] as String;
  DateTime get date => DateTime.parse(row['created_at'] as String);
}

class FinanceFilter {
  const FinanceFilter({
    required this.book,
    this.entityId,
    this.state,
    this.sourceType,
    this.from,
    this.to,
    this.query = '',
  });
  final FinanceBook book;
  final String? entityId, state, sourceType;
  final DateTime? from, to;
  final String query;
  bool dateMatches(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return (from == null || !day.isBefore(from!)) &&
        (to == null || !day.isAfter(to!));
  }

  bool accountMatches(
    FinanceAccount a, {
    bool useDate = true,
    bool useState = true,
  }) =>
      a.book == book &&
      (entityId == null || entityId == a.entityId) &&
      (!useState || state == null || state == a.state) &&
      (sourceType == null || sourceType == a.sourceType) &&
      (!useDate || dateMatches(a.date)) &&
      [
        a.name,
        a.payee,
        a.source,
        a.reference,
        a.reason,
        a.id,
      ].any((v) => v.toLowerCase().contains(query.trim().toLowerCase()));
}

class FinanceWorkspace {
  FinanceWorkspace({
    required this.at,
    required List<FinanceAccount> accounts,
    required List<FinanceProof> proofs,
    required List<Map<String, Object?>> categories,
    required List<Map<String, Object?>> suppliers,
    required Map<FinanceBook, Map<String, Object?>> pending,
    required Map<FinanceBook, List<Map<String, Object?>>> events,
  }) : accounts = List.unmodifiable(accounts),
       proofs = List.unmodifiable(proofs),
       categories = List.unmodifiable(
         categories.map(Map<String, Object?>.unmodifiable),
       ),
       suppliers = List.unmodifiable(
         suppliers.map(Map<String, Object?>.unmodifiable),
       ),
       pending = Map.unmodifiable(
         pending.map(
           (k, v) => MapEntry(k, Map<String, Object?>.unmodifiable(v)),
         ),
       ),
       events = Map.unmodifiable(
         events.map(
           (k, v) => MapEntry(
             k,
             List<Map<String, Object?>>.unmodifiable(
               v.map(Map<String, Object?>.unmodifiable),
             ),
           ),
         ),
       );
  final DateTime at;
  final List<FinanceAccount> accounts;
  final List<FinanceProof> proofs;
  final List<Map<String, Object?>> categories, suppliers;
  final Map<FinanceBook, Map<String, Object?>> pending;
  final Map<FinanceBook, List<Map<String, Object?>>> events;
  List<FinanceAccount> select(FinanceFilter filter) =>
      accounts.where((a) => filter.accountMatches(a)).toList();
  // Payment dates are independent of obligation dates and current status.
  // Count allocations, never the full multi-obligation receipt more than once.
  List<FinanceProof> cashFlow(FinanceFilter filter) {
    final ids = accounts
        .where((a) => filter.accountMatches(a, useDate: false, useState: false))
        .map((a) => a.id)
        .toSet();
    return proofs
        .where((p) => p.book == filter.book && filter.dateMatches(p.date))
        .map(
          (p) => FinanceProof(
            p.book,
            p.row,
            Map.fromEntries(
              p.allocations.entries.where((a) => ids.contains(a.key)),
            ),
          ),
        )
        .where((p) => p.allocations.isNotEmpty)
        .toList();
  }

  int flowTotal(FinanceFilter filter, String method) => cashFlow(filter)
      .where((p) => p.method == method)
      .fold(
        0,
        (sum, p) => sum + p.allocations.values.fold<int>(0, (a, b) => a + b),
      );
}
