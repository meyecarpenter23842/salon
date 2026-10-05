import 'package:intl/intl.dart';

class RetailProductItem {
  const RetailProductItem({
    required this.id,
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
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
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
  final DateTime createdAt;
  final DateTime updatedAt;

  String get salePriceLabel =>
      _currencyFormatter.format(salePrice).replaceAll(',', '.');

  RetailProductItem copyWith({
    String? id,
    String? name,
    String? unitOptionId,
    String? brandOptionId,
    String? groupOptionId,
    String? brand,
    String? volumeLabel,
    String? unitName,
    String? productType,
    int? salePrice,
    double? commissionPercent,
    bool? isActive,
    bool? isHiddenFromStaff,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RetailProductItem(
      id: id ?? this.id,
      name: name ?? this.name,
      unitOptionId: unitOptionId ?? this.unitOptionId,
      brandOptionId: brandOptionId ?? this.brandOptionId,
      groupOptionId: groupOptionId ?? this.groupOptionId,
      brand: brand ?? this.brand,
      volumeLabel: volumeLabel ?? this.volumeLabel,
      unitName: unitName ?? this.unitName,
      productType: productType ?? this.productType,
      salePrice: salePrice ?? this.salePrice,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      isActive: isActive ?? this.isActive,
      isHiddenFromStaff: isHiddenFromStaff ?? this.isHiddenFromStaff,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
}
