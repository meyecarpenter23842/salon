import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../database/service_mapper.dart';
import '../models/entity_id.dart';
import '../models/service_catalog_item.dart';
import '../models/service_upsert_input.dart';
import 'repository_contracts.dart';

class SqliteServicesRepository implements ServicesRepository {
  SqliteServicesRepository(this._database, FakeSalonDataSource dataSource)
    : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  @override
  Future<List<ServiceCatalogItem>> fetchServicesView() async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final rows = await database.query(
      'services',
      orderBy: 'category COLLATE NOCASE ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(ServiceMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<ServiceCatalogItem> saveService(
    ServiceUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    final now = DateTime.now();
    final service = ServiceCatalogItem.fromUpsertInput(
      id: existing?.id ?? EntityId.create('service'),
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await database.insert(
      'services',
      ServiceMapper.toDatabase(service),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return service;
  }

  @override
  Future<ServiceCatalogItem> updateServiceActive(
    String serviceId,
    bool isActive,
  ) async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final existing = await _findById(database, serviceId);
    if (existing == null) {
      throw StateError('Service $serviceId not found');
    }

    final updated = existing.copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );

    await database.update(
      'services',
      ServiceMapper.toDatabase(updated),
      where: 'id = ?',
      whereArgs: [serviceId],
    );

    return updated;
  }

  Future<ServiceCatalogItem?> _findById(Database database, String id) async {
    final rows = await database.query(
      'services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ServiceMapper.fromDatabase(rows.first);
  }
}
