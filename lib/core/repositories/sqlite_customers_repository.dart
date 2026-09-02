import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/customer_mapper.dart';
import '../database/salon_database.dart';
import '../models/customer_profile.dart';
import '../models/customer_upsert_input.dart';
import 'repository_contracts.dart';

class SqliteCustomersRepository implements CustomersRepository {
  SqliteCustomersRepository(this._database, this._seedDataSource);

  final SalonDatabase _database;
  final FakeSalonDataSource _seedDataSource;

  @override
  Future<List<CustomerProfile>> fetchCustomersView({
    String? query,
    String? tier,
    int? recentDays,
  }) async {
    final database = await _database.database;
    await _seedIfNeeded(database);

    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedTier = tier?.trim();
    final days = (recentDays ?? 30).clamp(1, 3650);
    final threshold = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();

    final clauses = <String>[];
    final args = <Object?>[];

    clauses.add('COALESCE(last_visit_at, updated_at) >= ?');
    args.add(threshold);

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
      where: clauses.join(' AND '),
      whereArgs: args,
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
    await _seedIfNeeded(database);

    final existingCustomer = existingId == null
        ? null
        : await _findById(database, existingId);
    final now = DateTime.now();
    var id =
        existingCustomer?.id ??
        CustomerMapper.buildIdFromIdentity(
          fullName: input.fullName,
          phone: input.phone,
        );

    if (existingCustomer == null) {
      final duplicate = await _findById(database, id);
      if (duplicate != null) {
        id = '$id-${now.millisecondsSinceEpoch}';
      }
    }

    final customer = CustomerProfile.fromUpsertInput(
      id: id,
      input: input,
      createdAt: existingCustomer?.createdAt ?? now,
      updatedAt: now,
      loyaltyPoints: existingCustomer?.loyaltyPoints ?? 0,
      visitCount: existingCustomer?.visitCount ?? 0,
      totalSpent: existingCustomer?.totalSpent ?? 0,
      lastVisitAt: existingCustomer?.lastVisitAt,
    );

    await database.insert(
      'customers',
      CustomerMapper.toDatabase(customer),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return customer;
  }

  Future<void> _seedIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM customers'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    final seedCustomers = await _seedDataSource.fetchCustomersView();
    final batch = database.batch();

    for (final item in seedCustomers) {
      final customer = CustomerMapper.fromLegacyView(item);
      batch.insert(
        'customers',
        CustomerMapper.toDatabase(customer),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
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
