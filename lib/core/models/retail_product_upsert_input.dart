class RetailProductUpsertInput {
  const RetailProductUpsertInput({
    required this.name,
    this.unitOptionId,
    this.brandOptionId,
    this.groupOptionId,
    required this.brand,
    required this.volumeLabel,
    this.unitName = '',
    required this.productType,
    required this.salePrice,
    required this.commissionPercent,
    required this.isActive,
    required this.isHiddenFromStaff,
  });

  final String name;
  final String? unitOptionId;
  final String? brandOptionId;
  final String? groupOptionId;
  final String brand;
  final String volumeLabel;
  final String unitName;
  final String productType;
  final int salePrice;
  final double commissionPercent;
  final bool isActive;
  final bool isHiddenFromStaff;

  static const List<String> productTypes = [
    'Gội',
    'Xả',
    'Hấp dầu',
    'Serum',
    'Tạo kiểu',
    'Khác',
  ];
}
