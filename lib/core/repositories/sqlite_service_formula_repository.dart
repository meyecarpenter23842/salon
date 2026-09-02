import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../database/service_formula_mapper.dart';
import '../models/service_formula_item.dart';
import 'repository_contracts.dart';

class SqliteServiceFormulaRepository implements ServiceFormulaRepository {
  SqliteServiceFormulaRepository(this._database);

  final SalonDatabase _database;

  @override
  Future<List<ServiceFormulaItem>> fetchFormulas() async {
    final database = await _database.database;
    final rows = await database.query(
      'service_formulas',
      orderBy: 'service_name COLLATE NOCASE ASC',
    );

    return rows.map(ServiceFormulaMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<ServiceFormulaItem> saveFormula({
    required String serviceId,
    required String serviceName,
    required String formulaText,
    required bool isHiddenFromStaff,
    String? existingFormulaId,
  }) async {
    final database = await _database.database;
    final existing = existingFormulaId == null
        ? null
        : await _findById(database, existingFormulaId);
    final now = DateTime.now();

    final item = ServiceFormulaItem(
      id: existing?.id ?? 'formula-${now.microsecondsSinceEpoch}',
      serviceId: serviceId,
      serviceName: serviceName,
      formulaText: formulaText,
      isHiddenFromStaff: isHiddenFromStaff,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await database.insert(
      'service_formulas',
      ServiceFormulaMapper.toDatabase(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return item;
  }

  Future<ServiceFormulaItem?> _findById(Database database, String id) async {
    final rows = await database.query(
      'service_formulas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ServiceFormulaMapper.fromDatabase(rows.first);
  }
}
