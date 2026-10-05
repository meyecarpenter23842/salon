
import 'package:sqflite/sqflite.dart';
import '../models/catalog_option.dart';
import '../models/entity_id.dart';

/// Only called inside database creation/upgrade transactions. Existing stock,
/// invoice snapshots and volume labels are never changed by this migration.
class CatalogSchema {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE catalog_options ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
    await db.execute('ALTER TABLE retail_products ADD COLUMN group_option_id TEXT REFERENCES catalog_options(id)');
    await db.execute('ALTER TABLE retail_products ADD COLUMN brand_option_id TEXT REFERENCES catalog_options(id)');
    await db.execute('ALTER TABLE retail_products ADD COLUMN unit_option_id TEXT REFERENCES catalog_options(id)');
    await db.execute("ALTER TABLE retail_products ADD COLUMN unit_name TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE services ADD COLUMN group_option_id TEXT REFERENCES catalog_options(id)');
    // Import values which predate configurable catalogs before adding defaults.
    for (final source in [
      ('retail_products', 'product_type', 'group_option_id', CatalogOptionKind.productGroup),
      ('retail_products', 'brand', 'brand_option_id', CatalogOptionKind.productBrand),
      ('services', 'category', 'group_option_id', CatalogOptionKind.serviceGroup),
    ]) {
      final rows = await db.query(source.$1, columns: ['id', source.$2]);
      for (final row in rows) {
        final name = normalizeCatalogOptionName(row[source.$2]?.toString() ?? '');
        if (name.isEmpty) continue;
        final option = await ensure(db, source.$4, name);
        await db.update(source.$1, {source.$3: option['id']},
          where: 'id = ?', whereArgs: [row['id']]);
      }
    }
    for (final kind in CatalogOptionKind.values) {
      for (final name in kind.defaultNames) { await ensure(db, kind, name); }
    }
    // No inference from volume_label: old products remain "Chưa thiết lập".
  }

  static Future<Map<String, Object?>> ensure(DatabaseExecutor db,
      CatalogOptionKind kind, String name) async {
    final normalized = normalizeCatalogOptionName(name);
    final key = catalogNameKey(normalized);
    final rows = await db.query('catalog_options', where: 'kind = ?',
      whereArgs: [kind.databaseValue]);
    for (final row in rows) {
      if (catalogNameKey(row['name'].toString()) == key) return row;
    }
    final now = DateTime.now().toIso8601String();
    final row = <String, Object?>{'id': EntityId.create('catalog'),
      'kind': kind.databaseValue, 'name': normalized, 'normalized_name': key,
      'is_active': 1, 'created_at': now, 'updated_at': now};
    await db.insert('catalog_options', row);
    return row;
  }

  /// Existing associations may retain archived options. A new assignment may not.
  static Future<Map<String, Object?>?> resolve(DatabaseExecutor db,
      CatalogOptionKind kind, String name, {Object? previousId, String? requestedId}) async {
    if (name.trim().isEmpty) return null;
    Map<String, Object?> option;
    if (requestedId != null) {
      final rows = await db.query('catalog_options', where: 'id = ? AND kind = ?', whereArgs: [requestedId, kind.databaseValue]);
      if (rows.isEmpty || catalogNameKey(rows.single['name'] as String) != catalogNameKey(name)) {
        throw StateError('Danh mục đã thay đổi. Mở lại biểu mẫu để cập nhật.');
      }
      option = rows.single;
    } else {
      option = await ensure(db, kind, name);
    }
    if (option['is_active'] != 1 && option['id'] != previousId) {
      throw StateError('Danh mục “${option['name']}” đã ngừng sử dụng. Chọn mục khác.');
    }
    return option;
  }
}
