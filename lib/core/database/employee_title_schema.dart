import 'package:sqflite/sqflite.dart';
import '../models/catalog_option.dart';
import 'catalog_schema.dart';

/// Schema 24: preserve legacy text and link titles without assigning permissions.
class EmployeeTitleSchema {
  static Future<void> install(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(employees)');
    if (!columns.any((c) => c['name'] == 'title_option_id')) {
      await db.execute(
        'ALTER TABLE employees ADD COLUMN title_option_id TEXT REFERENCES catalog_options(id)',
      );
    }
    final rows = await db.query(
      'employees',
      columns: ['id', 'role', 'title_option_id'],
    );
    for (final row in rows) {
      if (row['title_option_id'] != null) {
        continue;
      }
      final name = normalizeCatalogOptionName(row['role']?.toString() ?? '');
      if (name.isEmpty) {
        continue;
      }
      final option = await CatalogSchema.ensure(
        db,
        CatalogOptionKind.employeeTitle,
        name,
      );
      await db.update(
        'employees',
        {'title_option_id': option['id']},
        where: 'id=?',
        whereArgs: [row['id']],
      );
    }
    for (final name in CatalogOptionKind.employeeTitle.defaultNames) {
      await CatalogSchema.ensure(db, CatalogOptionKind.employeeTitle, name);
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employee_title ON employees(title_option_id)',
    );
  }
}

