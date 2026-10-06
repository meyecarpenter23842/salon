class InventoryProductItem {
  const InventoryProductItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.volumeLabel,
    this.unitName = '',
    this.lowStockThreshold = 5,
    required this.productType,
    required this.stockOnHand,
    required this.isActive,
  });

  final String id;
  final String name;
  final String brand;
  final String volumeLabel;
  final String unitName;
  final int lowStockThreshold;
  final String productType;
  final int stockOnHand;
  final bool isActive;

  bool get isNegativeStock => stockOnHand < 0;
  String get stockLabel => isNegativeStock ? 'Âm kho' : isOutOfStock ? 'Hết hàng' : isLowStock ? 'Sắp hết' : 'Còn hàng';

  bool get isOutOfStock => stockOnHand == 0;
  bool get isLowStock => stockOnHand > 0 && stockOnHand <= lowStockThreshold;

  String get metaLabel => [
    productType,
    if (unitName.isNotEmpty) unitName,
    if (brand.trim().isNotEmpty) brand.trim(),
    if (volumeLabel.trim().isNotEmpty) volumeLabel.trim(),
  ].join(' • ');
}

class InventoryMovementItem {
  const InventoryMovementItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.documentId,
    this.documentNumber,
    this.documentLineId,
    this.source = 'legacy',
    required this.movementType,
    required this.quantityDelta,
    required this.stockBefore,
    required this.stockAfter,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final String? documentId, documentNumber, documentLineId;
  final String source;
  String get sourceLabel => source == 'document' ? 'Chứng từ ${documentNumber ?? documentId}' : isSale ? 'Bán theo hóa đơn' : movementType == 'void' ? 'Hủy hóa đơn' : 'Lịch sử cũ (legacy)';
  final String movementType;
  final int quantityDelta;
  final int stockBefore;
  final int stockAfter;
  final String note;
  final DateTime createdAt;

  bool get isReceipt =>
      movementType == 'receive' || movementType == 'void';
  bool get isSale => movementType == 'sale';

  String get movementLabel => switch (movementType) {
    'receive' => 'Nhập kho',
    'sale' => 'Bán hàng',
    'void' => 'Hoàn tồn do hủy bill',
    'reverse' => 'Đảo phiếu kho',
    'issue' => 'Xuất kho',
    _ => 'Điều chỉnh',
  };
  String get quantityDeltaLabel => quantityDelta > 0
      ? '+$quantityDelta'
      : quantityDelta.toString();
}
