import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/commission_schema.dart';
import 'package:salonmanager/core/database/expense_schema.dart';
import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/database/stock_document_schema.dart';
import 'package:salonmanager/core/database/supplier_payable_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test(
    'partially applied schema 18-26 resumes without duplicate DDL',
    () async {
      final current = await SalonDatabase.instance.initialize();
      final location = current.path;
      await SalonDatabase.instance.close();
      await deleteDatabase(location);

      final legacy = await openDatabase(
        location,
        version: 17,
        onCreate: (database, version) async {
          for (final statement in DatabaseSchema.createStatements) {
            await database.execute(statement);
          }
          for (final statement in DatabaseSchema.indexes) {
            await database.execute(statement);
          }
        },
      );

      final stamp = DateTime(2026, 10, 6).toIso8601String();
      await legacy.insert('catalog_options', {
        'id': 'old-group',
        'kind': 'product_group',
        'name': 'Hàng cũ',
        'normalized_name': 'hàng cũ',
        'created_at': stamp,
        'updated_at': stamp,
      });
      await legacy.insert('retail_products', {
        'id': 'legacy-product',
        'name': 'Dầu cũ',
        'brand': 'Legacy Brand',
        'volume_label': '500 ml',
        'product_type': 'Hàng cũ',
        'sale_price': 100000,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await legacy.insert('inventory_stock', {
        'product_id': 'legacy-product',
        'stock_on_hand': 7,
        'updated_at': stamp,
      });
      await legacy.insert('inventory_movements', {
        'id': 'old-movement',
        'product_id': 'legacy-product',
        'movement_type': 'receive',
        'quantity_delta': 7,
        'stock_before': 0,
        'stock_after': 7,
        'note': 'Lịch sử nguyên bản',
        'created_at': stamp,
      });

      // Reproduce a real-world interrupted/restored schema: SQLite still
      // reports v17 while several newer DDL steps already exist.
      await legacy.execute(
        'ALTER TABLE catalog_options '
        'ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
      );
      await legacy.update(
        'catalog_options',
        {'is_active': 0},
        where: 'id = ?',
        whereArgs: ['old-group'],
      );
      await legacy.execute(
        'ALTER TABLE retail_products '
        'ADD COLUMN group_option_id TEXT REFERENCES catalog_options(id)',
      );
      await legacy.update(
        'retail_products',
        {'group_option_id': 'old-group'},
        where: 'id = ?',
        whereArgs: ['legacy-product'],
      );
      await legacy.execute(
        'ALTER TABLE retail_products '
        'ADD COLUMN low_stock_threshold INTEGER NOT NULL DEFAULT 5 '
        'CHECK(low_stock_threshold >= 0)',
      );
      await legacy.update(
        'retail_products',
        {'low_stock_threshold': 2},
        where: 'id = ?',
        whereArgs: ['legacy-product'],
      );

      for (final statement in StockDocumentSchema.statements.take(4)) {
        await legacy.execute(statement);
      }
      for (final statement in CommissionSchema.statements.take(2)) {
        await legacy.execute(statement);
      }
      for (final statement in ExpenseSchema.statements.take(2)) {
        await legacy.execute(statement);
      }
      for (final statement in SupplierPayableSchema.statements.take(2)) {
        await legacy.execute(statement);
      }
      await legacy.close();

      final upgraded = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );

      expect(await upgraded.getVersion(), DatabaseSchema.version);

      final product = (await upgraded.query(
        'retail_products',
        where: 'id = ?',
        whereArgs: ['legacy-product'],
      )).single;
      expect(product['group_option_id'], 'old-group');
      expect(product['low_stock_threshold'], 2);
      expect(product['unit_name'], '');

      final oldGroup = (await upgraded.query(
        'catalog_options',
        where: 'id = ?',
        whereArgs: ['old-group'],
      )).single;
      expect(oldGroup['is_active'], 0);

      final movement = (await upgraded.query(
        'inventory_movements',
        where: 'id = ?',
        whereArgs: ['old-movement'],
      )).single;
      expect(movement['document_id'], isNull);
      expect(movement['document_line_id'], isNull);
      expect(movement['source'], 'legacy');
      expect((await upgraded.query('inventory_stock')).single['stock_on_hand'], 7);

      expect(
        await _hasColumn(upgraded, 'retail_products', 'brand_option_id'),
        isTrue,
      );
      expect(
        await _hasColumn(upgraded, 'retail_products', 'unit_option_id'),
        isTrue,
      );
      expect(
        await _hasColumn(upgraded, 'services', 'group_option_id'),
        isTrue,
      );
      expect(await upgraded.query('stock_documents'), isEmpty);
      expect(await upgraded.query('commission_payouts'), isEmpty);
      expect(await upgraded.query('expense_entries'), isEmpty);
      expect(await upgraded.query('expense_payments'), isEmpty);
      expect(await upgraded.query('expense_events'), isEmpty);
      expect(await upgraded.query('supplier_payable_obligations'), isEmpty);
      expect(await upgraded.query('supplier_payments'), isEmpty);
      expect(await upgraded.query('supplier_payment_allocations'), isEmpty);
      expect(await upgraded.query('supplier_payable_events'), isEmpty);
      expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}

Future<bool> _hasColumn(
  Database database,
  String tableName,
  String columnName,
) async {
  final columns = await database.rawQuery('PRAGMA table_info($tableName)');
  return columns.any((column) => column['name']?.toString() == columnName);
}
