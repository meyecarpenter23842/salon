import 'package:intl/intl.dart';

import 'service_upsert_input.dart';

class ServiceCatalogItem {
  ServiceCatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.durationMinutes,
    required this.price,
    required this.description,
    required this.isActive,
    required this.popularityLabel,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final int durationMinutes;
  final int price;
  final String description;
  final bool isActive;
  final String popularityLabel;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get durationLabel => '$durationMinutes phút';

  String get priceLabel =>
      _currencyFormatter.format(price).replaceAll(',', '.');

  String get statusLabel => isActive ? 'Đang áp dụng' : 'Tạm ẩn';

  ServiceCatalogItem copyWith({
    String? id,
    String? name,
    String? category,
    int? durationMinutes,
    int? price,
    String? description,
    bool? isActive,
    String? popularityLabel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ServiceCatalogItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      price: price ?? this.price,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      popularityLabel: popularityLabel ?? this.popularityLabel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ServiceCatalogItem.fromUpsertInput({
    required String id,
    required ServiceUpsertInput input,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return ServiceCatalogItem(
      id: id,
      name: input.name,
      category: input.category,
      durationMinutes: input.durationMinutes,
      price: input.price,
      description: input.description,
      isActive: input.isActive,
      popularityLabel: input.popularityLabel,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
}
