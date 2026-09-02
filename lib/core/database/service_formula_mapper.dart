import '../models/service_formula_item.dart';

class ServiceFormulaMapper {
  const ServiceFormulaMapper._();

  static ServiceFormulaItem fromDatabase(Map<String, Object?> row) {
    return ServiceFormulaItem(
      id: row['id'].toString(),
      serviceId: row['service_id'].toString(),
      serviceName: row['service_name'].toString(),
      formulaText: row['formula_text'].toString(),
      isHiddenFromStaff: _toInt(row['is_hidden_from_staff']) == 1,
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static Map<String, Object?> toDatabase(ServiceFormulaItem item) {
    return {
      'id': item.id,
      'service_id': item.serviceId,
      'service_name': item.serviceName,
      'formula_text': item.formulaText,
      'is_hidden_from_staff': item.isHiddenFromStaff ? 1 : 0,
      'created_at': item.createdAt.toIso8601String(),
      'updated_at': item.updatedAt.toIso8601String(),
    };
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

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
