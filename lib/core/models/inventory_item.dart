class InventoryProductItem {
  const InventoryProductItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.volumeLabel,
    required this.productType,
    required this.stockOnHand,
    required this.isActive,
  });

  final String id;
  final String name;
  final String brand;
  final String volumeLabel;
  final String productType;
  final int stockOnHand;
  final bool isActive;

  bool get isOutOfStock => stockOnHand == 0;
  bool get isLowStock => stockOnHand > 0 && stockOnHand <= 5;

  String get metaLabel => [
    productType,
    if (brand.trim().isNotEmpty) brand.trim(),
    if (volumeLabel.trim().isNotEmpty) volumeLabel.trim(),
  ].join(' • ');
}

class InventoryMovementItem {
  const InventoryMovementItem({
    required this.id,
    required this.productId,
    required this.productName,
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
  final String movementType;
  final int quantityDelta;
  final int stockBefore;
  final int stockAfter;
  final String note;
  final DateTime createdAt;

  bool get isReceipt => movementType == 'receive';
  String get movementLabel => isReceipt ? 'Nhập kho' : 'Điều chỉnh';
  String get quantityDeltaLabel => quantityDelta > 0
      ? '+$quantityDelta'
      : quantityDelta.toString();
}
