class StockSupplier {
  const StockSupplier({required this.id, required this.name, this.phone = '', this.email = '', this.address = '', this.note = '', this.isActive = true});
  final String id, name, phone, email, address, note;
  final bool isActive;
}
enum StockDocumentKind {
  receipt('receipt', 'Phiếu nhập', 'PN'),
  issue('issue', 'Phiếu xuất', 'PX'),
  adjustment('adjustment', 'Kiểm kê', 'KK');
  const StockDocumentKind(this.value, this.label, this.prefix);
  final String value, label, prefix;
  static StockDocumentKind parse(String value) => values.firstWhere((v) => v.value == value);
}
class StockDocumentLineInput {
  const StockDocumentLineInput({required this.productId, required this.quantity, this.unitCost = 0});
  final String productId;
  final int quantity, unitCost;
}
class StockDocumentLine {
  const StockDocumentLine({required this.id, required this.productId, required this.productName, required this.unitName, required this.quantity, required this.unitCost});
  final String id, productId, productName, unitName;
  final int quantity, unitCost;
  int get amount => quantity * unitCost;
}
class StockDocumentInput {
  const StockDocumentInput({required this.id, required this.kind, required this.date, required this.preparedBy, required this.lines, this.supplierId, this.externalReference = '', this.note = '', this.expectedRevision});
  final String id, preparedBy, externalReference, note;
  final StockDocumentKind kind;
  final DateTime date;
  final String? supplierId;
  final List<StockDocumentLineInput> lines;
  final int? expectedRevision;
}
class StockDocument {
  const StockDocument({required this.id, required this.number, required this.kind, required this.date, required this.preparedBy, required this.status, required this.revision, required this.lines, this.supplierId, this.supplierName = '', this.externalReference = '', this.note = '', this.postedBy = '', this.cancellationReason = ''});
  final String id, number, preparedBy, status, supplierName, externalReference, note, postedBy, cancellationReason;
  final String? supplierId;
  final StockDocumentKind kind;
  final DateTime date;
  final int revision;
  final List<StockDocumentLine> lines;
  bool get isDraft => status == 'draft';
  bool get isPosted => status == 'posted';
  int get total => lines.fold(0, (sum, line) => sum + line.amount);
  String get statusLabel => switch(status) {'draft' => 'Nháp', 'posted' => 'Đã nhập / ghi kho', _ => 'Đã hủy'};
}
