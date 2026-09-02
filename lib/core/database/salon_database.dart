import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_bootstrap.dart';
import 'database_schema.dart';

class SalonDatabase {
  SalonDatabase._();

  static final SalonDatabase instance = SalonDatabase._();

  Database? _database;

  Future<Database> initialize() async {
    if (_database != null) {
      return _database!;
    }

    await DatabaseBootstrap.ensureInitialized();

    final databasePath = await _resolveDatabasePath();
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final dbFile = File(databasePath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    }

    _database = await openDatabase(
      databasePath,
      version: DatabaseSchema.version,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        final batch = database.batch();

        for (final statement in DatabaseSchema.createStatements) {
          batch.execute(statement);
        }

        for (final statement in DatabaseSchema.indexes) {
          batch.execute(statement);
        }

        final now = DateTime.now().toIso8601String();
        batch.insert('app_settings', {
          'key': 'schema_version',
          'value': version.toString(),
          'updated_at': now,
        });

        await batch.commit(noResult: true);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        final batch = database.batch();

        if (oldVersion < 2) {
          batch.execute(
            "ALTER TABLE customers ADD COLUMN favorite_service TEXT NOT NULL DEFAULT ''",
          );
          batch.execute('ALTER TABLE customers ADD COLUMN last_visit_at TEXT');
          batch.execute(
            "ALTER TABLE customers ADD COLUMN hair_profile TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            'ALTER TABLE customers ADD COLUMN visit_count INTEGER NOT NULL DEFAULT 0',
          );
          batch.execute(
            'ALTER TABLE customers ADD COLUMN total_spent INTEGER NOT NULL DEFAULT 0',
          );
        }

        if (oldVersion < 3) {
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN customer_name TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN customer_phone TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN service_name TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN staff_name TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            'ALTER TABLE appointments ADD COLUMN duration_minutes INTEGER NOT NULL DEFAULT 0',
          );
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN slot_label TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE appointments ADD COLUMN date_label TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 4) {
          batch.execute(
            "ALTER TABLE services ADD COLUMN popularity_label TEXT NOT NULL DEFAULT 'Ổn định'",
          );
        }

        if (oldVersion < 5) {
          batch.execute('ALTER TABLE appointments ADD COLUMN service_id TEXT');
          batch.execute(
            'UPDATE appointments SET service_id = ('
            'SELECT id FROM services WHERE LOWER(services.name) = LOWER(appointments.service_name) LIMIT 1'
            ') WHERE service_id IS NULL',
          );
          batch.execute(
            'CREATE INDEX idx_appointments_service_id ON appointments(service_id)',
          );
        }

        if (oldVersion < 6) {
          batch.execute(
            'CREATE TABLE IF NOT EXISTS appointment_services ('
            'id TEXT PRIMARY KEY, '
            'appointment_id TEXT NOT NULL, '
            'service_id TEXT NOT NULL, '
            "title TEXT NOT NULL DEFAULT '', "
            'quantity INTEGER NOT NULL DEFAULT 1, '
            'unit_price INTEGER NOT NULL, '
            'duration_minutes INTEGER NOT NULL DEFAULT 0, '
            'FOREIGN KEY (appointment_id) REFERENCES appointments(id) ON DELETE CASCADE, '
            'FOREIGN KEY (service_id) REFERENCES services(id)'
            ')',
          );
          batch.execute(
            'CREATE INDEX IF NOT EXISTS idx_appointment_services_appointment_id '
            'ON appointment_services(appointment_id)',
          );
          batch.execute(
            'INSERT INTO appointment_services (id, appointment_id, service_id, title, quantity, unit_price, duration_minutes) '
            'SELECT '
            "'aptsvc-' || appointments.id, "
            'appointments.id, '
            'appointments.service_id, '
            'appointments.service_name, '
            '1, '
            'COALESCE((SELECT price FROM services WHERE services.id = appointments.service_id LIMIT 1), 0), '
            'COALESCE((SELECT duration_minutes FROM services WHERE services.id = appointments.service_id LIMIT 1), appointments.duration_minutes) '
            'FROM appointments '
            'WHERE appointments.service_id IS NOT NULL '
            'AND NOT EXISTS ('
            'SELECT 1 FROM appointment_services WHERE appointment_services.appointment_id = appointments.id'
            ')',
          );
        }

        if (oldVersion < 7) {
          batch.execute(
            "ALTER TABLE employees ADD COLUMN initials TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN status TEXT NOT NULL DEFAULT 'Đang làm việc'",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN shift_label TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN specialty TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN commission_label TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN today_schedule TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN services_done INTEGER NOT NULL DEFAULT 0",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN monthly_revenue_label TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "ALTER TABLE employees ADD COLUMN rating_label TEXT NOT NULL DEFAULT ''",
          );
          batch.execute(
            "UPDATE employees SET initials = UPPER(SUBSTR(full_name, 1, 1)) WHERE initials = ''",
          );
          batch.execute(
            "UPDATE employees SET commission_label = CASE WHEN commission_rate > 0 THEN CAST(ROUND(commission_rate * 100) AS INT) || '%' ELSE 'KPI cố định' END WHERE commission_label = ''",
          );
        }

        if (oldVersion < 8) {
          batch.execute(
            'CREATE TABLE IF NOT EXISTS service_formulas ('
            'id TEXT PRIMARY KEY, '
            'service_id TEXT NOT NULL, '
            'service_name TEXT NOT NULL, '
            'formula_text TEXT NOT NULL, '
            'is_hidden_from_staff INTEGER NOT NULL DEFAULT 1, '
            'created_at TEXT NOT NULL, '
            'updated_at TEXT NOT NULL, '
            'FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE'
            ')',
          );
          batch.execute(
            'CREATE TABLE IF NOT EXISTS retail_products ('
            'id TEXT PRIMARY KEY, '
            'name TEXT NOT NULL, '
            'brand TEXT NOT NULL, '
            'volume_label TEXT NOT NULL, '
            'product_type TEXT NOT NULL, '
            'sale_price INTEGER NOT NULL, '
            'is_active INTEGER NOT NULL DEFAULT 1, '
            'created_at TEXT NOT NULL, '
            'updated_at TEXT NOT NULL'
            ')',
          );
          if (!await _tableHasColumn(database, 'invoice_items', 'item_type')) {
            batch.execute(
              "ALTER TABLE invoice_items ADD COLUMN item_type TEXT NOT NULL DEFAULT 'service'",
            );
          }
          if (!await _tableHasColumn(database, 'invoice_items', 'product_id')) {
            batch.execute(
              'ALTER TABLE invoice_items ADD COLUMN product_id TEXT',
            );
          }
          if (!await _tableHasColumn(
            database,
            'invoice_items',
            'discount_amount',
          )) {
            batch.execute(
              'ALTER TABLE invoice_items ADD COLUMN discount_amount INTEGER NOT NULL DEFAULT 0',
            );
          }
          batch.execute(
            'CREATE INDEX IF NOT EXISTS idx_invoice_items_item_type ON invoice_items(item_type)',
          );
          batch.execute(
            'CREATE INDEX IF NOT EXISTS idx_service_formulas_service_id ON service_formulas(service_id)',
          );
          batch.execute(
            'CREATE INDEX IF NOT EXISTS idx_retail_products_type ON retail_products(product_type)',
          );
        }

        if (oldVersion < 9) {
          if (!await _tableHasColumn(
            database,
            'retail_products',
            'commission_percent',
          )) {
            batch.execute(
              'ALTER TABLE retail_products ADD COLUMN commission_percent REAL NOT NULL DEFAULT 0',
            );
          }
          if (!await _tableHasColumn(
            database,
            'retail_products',
            'is_hidden_from_staff',
          )) {
            batch.execute(
              'ALTER TABLE retail_products ADD COLUMN is_hidden_from_staff INTEGER NOT NULL DEFAULT 0',
            );
          }
        }

        if (oldVersion < 10) {
          if (!await _tableHasColumn(
            database,
            'invoice_items',
            'employee_id',
          )) {
            batch.execute(
              'ALTER TABLE invoice_items ADD COLUMN employee_id TEXT',
            );
          }
          batch.execute(
            'CREATE INDEX IF NOT EXISTS idx_invoice_items_employee_id '
            'ON invoice_items(employee_id)',
          );
        }

        await batch.commit(noResult: true);
      },
      onOpen: (database) async {
        await database.insert('app_settings', {
          'key': 'schema_version',
          'value': DatabaseSchema.version.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      },
    );

    return _database!;
  }

  Future<Database> get database async => initialize();

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<String> _resolveDatabasePath() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final rootDirectory = _resolveDesktopDataRoot();
      final databaseDirectory = Directory(
        path.join(rootDirectory, '.salon_manager'),
      );

      if (!await databaseDirectory.exists()) {
        await databaseDirectory.create(recursive: true);
      }

      return path.join(databaseDirectory.path, 'salon_manager.db');
    }

    final databaseDirectory = await getDatabasesPath();
    return path.join(databaseDirectory, 'salon_manager.db');
  }

  String _resolveDesktopDataRoot() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return path.join(Directory.systemTemp.path, 'hair_spa_manager_test_data');
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, 'HairSpaManager', 'data');
      }
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return path.join(home, '.local', 'share', 'hair_spa_manager');
      }
    }

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return path.join(
          home,
          'Library',
          'Application Support',
          'HairSpaManager',
        );
      }
    }

    return path.join(Directory.current.path, '.salon_manager_data');
  }

  Future<bool> _tableHasColumn(
    Database database,
    String tableName,
    String columnName,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($tableName)');
    for (final column in columns) {
      if (column['name']?.toString() == columnName) {
        return true;
      }
    }
    return false;
  }
}
