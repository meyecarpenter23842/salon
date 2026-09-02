import 'package:intl/intl.dart';

import 'customer_upsert_input.dart';

class CustomerProfile {
  CustomerProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.email,
    required this.tier,
    required this.favoriteService,
    this.lastVisitAt,
    required this.hairProfile,
    required this.note,
    required this.loyaltyPoints,
    required this.visitCount,
    required this.totalSpent,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? email;
  final String tier;
  final String favoriteService;
  final DateTime? lastVisitAt;
  final String hairProfile;
  final String note;
  final int loyaltyPoints;
  final int visitCount;
  final int totalSpent;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get initials {
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return _firstSymbol(parts.first).toUpperCase();
    }

    return '${_firstSymbol(parts.first)}${_firstSymbol(parts.last)}'
        .toUpperCase();
  }

  String get spentLabel =>
      _currencyFormatter.format(totalSpent).replaceAll(',', '.');

  String get lastVisitLabel {
    if (lastVisitAt == null) {
      return 'Chưa có lịch sử';
    }

    return _dateFormatter.format(lastVisitAt!);
  }

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );

  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');

  CustomerProfile copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? email,
    String? tier,
    String? favoriteService,
    DateTime? lastVisitAt,
    String? hairProfile,
    String? note,
    int? loyaltyPoints,
    int? visitCount,
    int? totalSpent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomerProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      tier: tier ?? this.tier,
      favoriteService: favoriteService ?? this.favoriteService,
      lastVisitAt: lastVisitAt ?? this.lastVisitAt,
      hairProfile: hairProfile ?? this.hairProfile,
      note: note ?? this.note,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      visitCount: visitCount ?? this.visitCount,
      totalSpent: totalSpent ?? this.totalSpent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CustomerProfile.fromUpsertInput({
    required String id,
    required CustomerUpsertInput input,
    required DateTime createdAt,
    required DateTime updatedAt,
    int loyaltyPoints = 0,
    int visitCount = 0,
    int totalSpent = 0,
    DateTime? lastVisitAt,
  }) {
    return CustomerProfile(
      id: id,
      fullName: input.fullName,
      phone: input.phone,
      email: input.email.isEmpty ? null : input.email,
      tier: input.tier,
      favoriteService: input.favoriteService,
      lastVisitAt: lastVisitAt,
      hairProfile: input.hairProfile,
      note: input.note,
      loyaltyPoints: loyaltyPoints,
      visitCount: visitCount,
      totalSpent: totalSpent,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _firstSymbol(String value) {
    if (value.isEmpty) {
      return '?';
    }

    return String.fromCharCodes(value.runes.take(1));
  }
}
