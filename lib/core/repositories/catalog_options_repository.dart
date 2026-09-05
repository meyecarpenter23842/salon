import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/catalog_option.dart';
import '../models/entity_id.dart';

abstract interface class CatalogOptionsRepository {
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind);

  Future<String> createOption(CatalogOptionKind kind, String name);
}

class SqliteCatalogOptionsRepository implements CatalogOptionsRepository {
  SqliteCatalogOptionsRepository(this._database);

  final SalonDatabase _database;

  @override
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind) async {
    final database = await _database.database;
    final rows = await database.query(
      'catalog_options',
      columns: const ['name'],
      where: 'kind = ?',
      whereArgs: [kind.databaseValue],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return _mergeNames(
      kind.defaultNames,
      rows.map((row) => row['name']?.toString() ?? ''),
    );
  }

  @override
  Future<String> createOption(CatalogOptionKind kind, String name) async {
    final normalized = normalizeCatalogOptionName(name);
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tên không được để trống');
    }

    final normalizedKey = normalized.toLowerCase();
    final database = await _database.database;
    final existingRows = await database.query(
      'catalog_options',
      columns: const ['name'],
      where: 'kind = ?',
      whereArgs: [kind.databaseValue],
    );
    for (final row in existingRows) {
      final existingName = normalizeCatalogOptionName(
        row['name']?.toString() ?? '',
      );
      if (existingName.toLowerCase() == normalizedKey) {
        return existingName;
      }
    }

    for (final defaultName in kind.defaultNames) {
      if (defaultName.toLowerCase() == normalizedKey) {
        return defaultName;
      }
    }

    final now = DateTime.now().toIso8601String();
    await database.insert(
      'catalog_options',
      {
        'id': EntityId.create('catalog'),
        'kind': kind.databaseValue,
        'name': normalized,
        'normalized_name': normalizedKey,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return normalized;
  }
}

class FakeCatalogOptionsRepository implements CatalogOptionsRepository {
  FakeCatalogOptionsRepository()
      : _names = {
          for (final kind in CatalogOptionKind.values)
            kind: [...kind.defaultNames],
        };

  final Map<CatalogOptionKind, List<String>> _names;

  @override
  Future<List<String>> fetchOptionNames(CatalogOptionKind kind) async {
    return List.unmodifiable(_names[kind] ?? const <String>[]);
  }

  @override
  Future<String> createOption(CatalogOptionKind kind, String name) async {
    final normalized = normalizeCatalogOptionName(name);
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tên không được để trống');
    }
    final names = _names[kind] ??= <String>[];
    for (final existing in names) {
      if (existing.toLowerCase() == normalized.toLowerCase()) {
        return existing;
      }
    }
    names.add(normalized);
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return normalized;
  }
}

List<String> _mergeNames(Iterable<String> primary, Iterable<String> secondary) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in [...primary, ...secondary]) {
    final normalized = normalizeCatalogOptionName(raw);
    if (normalized.isEmpty) continue;
    if (seen.add(normalized.toLowerCase())) {
      result.add(normalized);
    }
  }
  return result;
}
