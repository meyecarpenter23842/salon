import 'package:sqflite/sqflite.dart';

import '../database/retail_product_mapper.dart';
import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/retail_product_item.dart';
import '../models/retail_product_upsert_input.dart';
import 'repository_contracts.dart';

class SqliteRetailProductsRepository implements RetailProductsRepository {
  SqliteRetailProductsRepository(this._database);

  final SalonDatabase _database;

  @override
  Future<List<RetailProductItem>> fetchProducts({
    String? query,
    String? type,
  }) async {
    final database = await _database.database;
    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedType = type?.trim();

    final clauses = <String>[];
    final args = <Object?>[];

    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add(
        '(LOWER(name) LIKE ? OR LOWER(brand) LIKE ? OR LOWER(product_type) LIKE ? OR LOWER(volume_label) LIKE ?)',
      );
      args.addAll(List.filled(4, '%$normalizedQuery%'));
    }

    if (normalizedType != null &&
        normalizedType.isNotEmpty &&
        normalizedType != 'Tất cả') {
      clauses.add('product_type = ?');
      args.add(normalizedType);
    }

    final rows = await database.query(
      'retail_products',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: clauses.isEmpty ? null : args,
      orderBy:
          'is_active DESC, product_type COLLATE NOCASE ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(RetailProductMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<RetailProductItem> saveProduct(
    RetailProductUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    final now = DateTime.now();
    final item = RetailProductMapper.fromUpsertInput(
      id: existing?.id ?? EntityId.create('product'),
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await database.insert(
      'retail_products',
      RetailProductMapper.toDatabase(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return item;
  }

  @override
  Future<RetailProductItem> updateProductActive(
    String productId,
    bool isActive,
  ) async {
    final database = await _database.database;
    final existing = await _findById(database, productId);
    if (existing == null) {
      throw StateError('Product $productId not found');
    }

    final updated = existing.copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    await database.update(
      'retail_products',
      RetailProductMapper.toDatabase(updated),
      where: 'id = ?',
      whereArgs: [productId],
    );

    return updated;
  }

  Future<RetailProductItem?> _findById(Database database, String id) async {
    final rows = await database.query(
      'retail_products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return RetailProductMapper.fromDatabase(rows.first);
  }
}
