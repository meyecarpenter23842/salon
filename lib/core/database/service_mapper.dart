import '../models/service_catalog_item.dart';

class ServiceMapper {
  const ServiceMapper._();

  static ServiceCatalogItem fromDatabase(Map<String, Object?> row) {
    return ServiceCatalogItem(
      id: row['id'].toString(),
      name: row['name'].toString(),
      category: row['category'].toString(),
      durationMinutes: _toInt(row['duration_minutes']),
      price: _toInt(row['price']),
      description: row['description']?.toString() ?? '',
      isActive: _toInt(row['is_active']) == 1,
      popularityLabel: row['popularity_label']?.toString() ?? 'Ổn định',
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static ServiceCatalogItem fromLegacyView(Map<String, Object?> data) {
    final now = DateTime.now();
    return ServiceCatalogItem(
      id: data['id'].toString(),
      name: data['name'].toString(),
      category: data['category'].toString(),
      durationMinutes: _parseDurationMinutes(data['duration'].toString()),
      price: _toInt(data['priceValue']),
      description: data['description'].toString(),
      isActive: data['status'] == 'Đang áp dụng',
      popularityLabel: data['popularity'].toString(),
      createdAt: now,
      updatedAt: now,
    );
  }

  static Map<String, Object?> toDatabase(ServiceCatalogItem service) {
    return {
      'id': service.id,
      'name': service.name,
      'category': service.category,
      'duration_minutes': service.durationMinutes,
      'price': service.price,
      'description': service.description,
      'is_active': service.isActive ? 1 : 0,
      'popularity_label': service.popularityLabel,
      'created_at': service.createdAt.toIso8601String(),
      'updated_at': service.updatedAt.toIso8601String(),
    };
  }

  static int _parseDurationMinutes(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
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
}
