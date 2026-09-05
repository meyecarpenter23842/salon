import 'package:sqflite/sqflite.dart';

import '../database/customer_mapper.dart';
import '../database/salon_database.dart';
import '../models/customer_profile.dart';
import '../models/customer_upsert_input.dart';
import '../models/entity_id.dart';
import 'repository_contracts.dart';

class SqliteCustomersRepository implements CustomersRepository {
  SqliteCustomersRepository(this._database, [Object? _]);

  final SalonDatabase _database;

  @override
  Future<List<CustomerProfile>> fetchCustomersView({
    String? query,
    String? tier,
    int? recentDays,
    int? inactiveDays,
  }) async {
    if (recentDays != null && inactiveDays != null) {
      throw ArgumentError(
        'recentDays and inactiveDays are mutually exclusive activity filters.',
      );
    }

    final database = await _database.database;
    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedTier = tier?.trim();
    final clauses = <String>[];
    final args = <Object?>[];

    if (recentDays != null) {
      final days = recentDays.clamp(1, 3650);
      final threshold = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      clauses.add('last_visit_at IS NOT NULL AND last_visit_at >= ?');
      args.add(threshold);
    } else if (inactiveDays != null) {
      final days = inactiveDays.clamp(1, 3650);
      final threshold = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      clauses.add('(last_visit_at IS NULL OR last_visit_at < ?)');
      args.add(threshold);
    }

    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add(
        '(LOWER(full_name) LIKE ? OR LOWER(phone) LIKE ? OR LOWER(tier) LIKE ? OR LOWER(favorite_service) LIKE ?)',
      );
      args.addAll(List.filled(4, '%$normalizedQuery%'));
    }

    if (normalizedTier != null &&
        normalizedTier.isNotEmpty &&
        normalizedTier != 'Tất cả') {
      clauses.add('tier = ?');
      args.add(normalizedTier);
    }

    final rows = await database.query(
      'customers',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: clauses.isEmpty ? null : args,
      orderBy:
          'total_spent DESC, visit_count DESC, full_name COLLATE NOCASE ASC',
    );

    return rows.map(CustomerMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<CustomerProfile> saveCustomer(
    CustomerUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    final existingCustomer = existingId == null
        ? null
        : await _findById(database, existingId);
    if (existingId != null && existingCustomer == null) {
      throw StateError('Customer $existingId not found');
    }

    final normalizedPhone = _normalizePhone(input.phone);
    if (normalizedPhone.isEmpty) {
      throw StateError('Số điện thoại cần có ít nhất một chữ số hợp lệ.');
    }

    final phoneOwner = await _findPhoneOwner(
      database,
      normalizedPhone,
      excludeId: existingId,
    );
    if (phoneOwner != null) {
      throw StateError(
        'Số điện thoại này đã thuộc về khách ${phoneOwner.fullName}.',
      );
    }

    final now = DateTime.now();
    final customer = CustomerProfile.fromUpsertInput(
      id: existingCustomer?.id ?? EntityId.create('customer'),
      input: input,
      createdAt: existingCustomer?.createdAt ?? now,
      updatedAt: now,
      loyaltyPoints: existingCustomer?.loyaltyPoints ?? 0,
      visitCount: existingCustomer?.visitCount ?? 0,
      totalSpent: existingCustomer?.totalSpent ?? 0,
      lastVisitAt: existingCustomer?.lastVisitAt,
    );
    final row = CustomerMapper.toDatabase(customer);

    if (existingCustomer == null) {
      await database.insert(
        'customers',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final updatedCount = await database.update(
        'customers',
        row,
        where: 'id = ?',
        whereArgs: [existingCustomer.id],
      );
      if (updatedCount != 1) {
        throw StateError('Customer ${existingCustomer.id} disappeared during edit');
      }
    }

    return customer;
  }

  Future<CustomerProfile?> _findPhoneOwner(
    Database database,
    String normalizedPhone, {
    String? excludeId,
  }) async {
    final rows = await database.query('customers');
    for (final row in rows) {
      final customer = CustomerMapper.fromDatabase(row);
      if (customer.id == excludeId) continue;
      if (_normalizePhone(customer.phone) == normalizedPhone) {
        return customer;
      }
    }
    return null;
  }

  Future<CustomerProfile?> _findById(Database database, String id) async {
    final rows = await database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return CustomerMapper.fromDatabase(rows.first);
  }
}

String _normalizePhone(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}
