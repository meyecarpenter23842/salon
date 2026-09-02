import '../models/retail_product_item.dart';
import '../models/retail_product_upsert_input.dart';

class RetailProductMapper {
  const RetailProductMapper._();

  static RetailProductItem fromDatabase(Map<String, Object?> row) {
    return RetailProductItem(
      id: row['id'].toString(),
      name: row['name'].toString(),
      brand: row['brand'].toString(),
      volumeLabel: row['volume_label'].toString(),
      productType: row['product_type'].toString(),
      salePrice: _toInt(row['sale_price']),
      commissionPercent: _toDouble(row['commission_percent']),
      isActive: _toInt(row['is_active']) == 1,
      isHiddenFromStaff: _toInt(row['is_hidden_from_staff']) == 1,
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static Map<String, Object?> toDatabase(RetailProductItem item) {
    return {
      'id': item.id,
      'name': item.name,
      'brand': item.brand,
      'volume_label': item.volumeLabel,
      'product_type': item.productType,
      'sale_price': item.salePrice,
      'commission_percent': item.commissionPercent,
      'is_active': item.isActive ? 1 : 0,
      'is_hidden_from_staff': item.isHiddenFromStaff ? 1 : 0,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
    };
  }

  static RetailProductItem fromUpsertInput({
    required String id,
    required RetailProductUpsertInput input,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return RetailProductItem(
      id: id,
      name: input.name,
      brand: input.brand,
      volumeLabel: input.volumeLabel,
      productType: input.productType,
      salePrice: input.salePrice,
      commissionPercent: input.commissionPercent,
      isActive: input.isActive,
      isHiddenFromStaff: input.isHiddenFromStaff,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
