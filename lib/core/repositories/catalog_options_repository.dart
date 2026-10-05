
import '../database/catalog_schema.dart';
import '../database/salon_database.dart';
import '../models/catalog_option.dart';
import '../models/entity_id.dart';

abstract interface class CatalogOptionsRepository {
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind);
  Future<List<CatalogOption>> fetchOptions(CatalogOptionKind kind);
  Future<String> createOption(CatalogOptionKind kind, String name);
  Future<void> renameOption(String id, String name);
  Future<void> setOptionActive(String id, bool active);
}

class SqliteCatalogOptionsRepository implements CatalogOptionsRepository {
  SqliteCatalogOptionsRepository(this._database);
  final SalonDatabase _database;

  static (String, String, String) source(CatalogOptionKind kind) => switch (kind) {
    CatalogOptionKind.productGroup => ('retail_products', 'product_type', 'group_option_id'),
    CatalogOptionKind.productBrand => ('retail_products', 'brand', 'brand_option_id'),
    CatalogOptionKind.productUnit => ('retail_products', 'unit_name', 'unit_option_id'),
    CatalogOptionKind.serviceGroup => ('services', 'category', 'group_option_id'),
  };

  @override
  Future<List<CatalogOption>> fetchOptions(CatalogOptionKind kind) async {
    final db = await _database.database;
    final s = source(kind);
    final rows = await db.rawQuery(
      'SELECT o.*, (SELECT COUNT(*) FROM ${s.$1} p WHERE p.${s.$3} = o.id) AS uses '
      'FROM catalog_options o WHERE kind = ? ORDER BY is_active DESC, name COLLATE NOCASE',
      [kind.databaseValue]);
    return rows.map((r) => CatalogOption(id: r['id'] as String, kind: kind,
      name: r['name'] as String, isActive: r['is_active'] == 1,
      usageCount: (r['uses'] as num).toInt())).toList();
  }

  @override
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind) async =>
    (await fetchOptions(kind)).where((o) => o.isActive).map((o) => o.name).toList();

  @override
  Future<String> createOption(CatalogOptionKind kind, String name) async {
    final normalized = _validateName(name);
    return _database.inTransaction((scope) async {
      final db = await scope.database;
      final row = await CatalogSchema.ensure(db, kind, normalized);
      if (row['is_active'] != 1) throw StateError('Tên đã có trong mục ngừng sử dụng. Hãy bật lại mục đó.');
      return row['name'] as String;
    });
  }

  @override
  Future<void> renameOption(String id, String name) async {
    final normalized = _validateName(name);
    await _database.inTransaction((scope) async {
      final db = await scope.database;
      final rows = await db.query('catalog_options', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('Danh mục không còn tồn tại.');
      final old = rows.single;
      final kind = CatalogOptionKind.values.firstWhere((k) => k.databaseValue == old['kind']);
      final others = await db.query('catalog_options', where: 'kind = ? AND id <> ?',
        whereArgs: [kind.databaseValue, id]);
      if (others.any((r) => catalogNameKey(r['name'] as String) == catalogNameKey(normalized))) {
        throw StateError('Tên danh mục đã tồn tại.');
      }
      final now = DateTime.now().toIso8601String();
      await db.update('catalog_options', {'name': normalized, 'normalized_name': catalogNameKey(normalized),
        'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      final s = source(kind);
      // Only live catalog records change. Invoice/appointment snapshots stay intact.
      await db.update(s.$1, {s.$2: normalized, 'updated_at': now},
        where: '${s.$3} = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> setOptionActive(String id, bool active) async {
    final db = await _database.database;
    final count = await db.update('catalog_options', {'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
    if (count != 1) throw StateError('Danh mục không còn tồn tại.');
  }
}

class FakeCatalogOptionsRepository implements CatalogOptionsRepository {
  final Map<String, CatalogOption> _options = {
    for (final kind in CatalogOptionKind.values)
      for (final name in kind.defaultNames)
        '${kind.name}:$name': CatalogOption(id: '${kind.name}:$name', kind: kind, name: name, isActive: true),
  };
  @override
  Future<List<CatalogOption>> fetchOptions(CatalogOptionKind kind) async =>
    _options.values.where((o) => o.kind == kind).toList();
  @override
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind) async =>
    (await fetchOptions(kind)).where((o) => o.isActive).map((o) => o.name).toList();
  @override
  Future<String> createOption(CatalogOptionKind kind, String name) async {
    final normalized = _validateName(name);
    for (final o in _options.values) {
      if (o.kind == kind && catalogNameKey(o.name) == catalogNameKey(normalized)) {
        if (!o.isActive) throw StateError('Tên đã có trong mục ngừng sử dụng.');
        return o.name;
      }
    }
    final id = EntityId.create('catalog');
    _options[id] = CatalogOption(id: id, kind: kind, name: normalized, isActive: true);
    return normalized;
  }
  @override
  Future<void> renameOption(String id, String name) async {
    final old = _options[id];
    if (old == null) throw StateError('Danh mục không còn tồn tại.');
    final normalized = _validateName(name);
    if (_options.values.any((o) => o.id != id && o.kind == old.kind &&
        catalogNameKey(o.name) == catalogNameKey(normalized))) {
      throw StateError('Tên danh mục đã tồn tại.');
    }
    _options[id] = CatalogOption(id: id, kind: old.kind, name: normalized, isActive: old.isActive);
  }
  @override
  Future<void> setOptionActive(String id, bool active) async {
    final old = _options[id];
    if (old == null) throw StateError('Danh mục không còn tồn tại.');
    _options[id] = CatalogOption(id: id, kind: old.kind, name: old.name, isActive: active);
  }
}

String _validateName(String name) {
  final normalized = normalizeCatalogOptionName(name);
  if (normalized.isEmpty || normalized.length > 100) throw ArgumentError('Tên cần từ 1 đến 100 ký tự.');
  return normalized;
}
