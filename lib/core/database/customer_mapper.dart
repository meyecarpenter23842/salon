import 'package:intl/intl.dart';

import '../models/customer_profile.dart';

class CustomerMapper {
  const CustomerMapper._();

  static CustomerProfile fromDatabase(Map<String, Object?> row) {
    return CustomerProfile(
      id: row['id'].toString(),
      fullName: row['full_name'].toString(),
      phone: row['phone'].toString(),
      email: row['email']?.toString(),
      tier: row['tier'].toString(),
      favoriteService: row['favorite_service']?.toString() ?? '',
      lastVisitAt: _parseDateTime(row['last_visit_at']),
      hairProfile: row['hair_profile']?.toString() ?? '',
      note: row['notes']?.toString() ?? '',
      loyaltyPoints: _toInt(row['loyalty_points']),
      visitCount: _toInt(row['visit_count']),
      totalSpent: _toInt(row['total_spent']),
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static CustomerProfile fromLegacyView(Map<String, Object?> data) {
    final lastVisitAt = _parseLegacyDate(data['lastVisit']?.toString());
    final timestamp = DateTime.now();

    return CustomerProfile(
      id: _buildId(data),
      fullName: data['name'].toString(),
      phone: data['phone'].toString(),
      email: data['email']?.toString(),
      tier: data['tier'].toString(),
      favoriteService: data['favoriteService'].toString(),
      lastVisitAt: lastVisitAt,
      hairProfile: data['hairProfile'].toString(),
      note: data['note'].toString(),
      loyaltyPoints: _toInt(data['loyaltyPoints']),
      visitCount: _toInt(data['visits']),
      totalSpent: _parseCurrency(data['spent']?.toString() ?? '0đ'),
      createdAt: lastVisitAt ?? timestamp,
      updatedAt: timestamp,
    );
  }

  static Map<String, Object?> toDatabase(CustomerProfile customer) {
    return {
      'id': customer.id,
      'full_name': customer.fullName,
      'phone': customer.phone,
      'email': customer.email,
      'tier': customer.tier,
      'loyalty_points': customer.loyaltyPoints,
      'favorite_service': customer.favoriteService,
      'last_visit_at': customer.lastVisitAt?.toIso8601String(),
      'hair_profile': customer.hairProfile,
      'visit_count': customer.visitCount,
      'total_spent': customer.totalSpent,
      'notes': customer.note,
      'created_at': customer.createdAt.toIso8601String(),
      'updated_at': customer.updatedAt.toIso8601String(),
    };
  }

  static String buildIdFromIdentity({
    required String fullName,
    required String phone,
  }) {
    return _buildId({'name': fullName, 'phone': phone});
  }

  static String _buildId(Map<String, Object?> data) {
    final rawPhone =
        data['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
    if (rawPhone.isNotEmpty) {
      return 'customer-$rawPhone';
    }

    final normalizedName =
        data['name']
            ?.toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-|-$'), '') ??
        'unknown';
    return 'customer-$normalizedName';
  }

  static int _parseCurrency(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static DateTime? _parseLegacyDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    return DateFormat('dd/MM/yyyy').parseStrict(value);
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
