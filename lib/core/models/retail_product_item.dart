import 'package:intl/intl.dart';

class RetailProductItem {
  const RetailProductItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.volumeLabel,
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
  final String brand;
  final String volumeLabel;
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
    String? brand,
    String? volumeLabel,
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
      brand: brand ?? this.brand,
      volumeLabel: volumeLabel ?? this.volumeLabel,
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
