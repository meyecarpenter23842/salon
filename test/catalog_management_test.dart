import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/models/catalog_option.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/catalog_options_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_inventory_repository.dart';

RetailProductUpsertInput product({String unit = 'Chai', String group = 'Gội',
    String? unitId}) => RetailProductUpsertInput(name: 'Dầu gội', brand: 'Salon',
  volumeLabel: '500 ml', productType: group, unitName: unit, unitOptionId: unitId,
  salePrice: 120000, commissionPercent: 0, isActive: true, isHiddenFromStaff: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => SalonDatabase.instance.close());
  tearDown(() async => SalonDatabase.instance.close());

  test('schema 17 migration preserves identities, quantities, labels and movements across restart', () async {
    final current = await SalonDatabase.instance.initialize();
    final location = current.path;
    await SalonDatabase.instance.close();
    await deleteDatabase(location);
    final legacy = await openDatabase(location, version: 17, onCreate: (db, version) async {
      for (final sql in DatabaseSchema.createStatements) { await db.execute(sql); }
      for (final sql in DatabaseSchema.indexes) { await db.execute(sql); }
    });
    final stamp = DateTime(2026, 1, 1).toIso8601String();
    await legacy.insert('catalog_options', {'id': 'old-group', 'kind': 'product_group',
      'name': 'Hàng cũ', 'normalized_name': 'hàng cũ', 'created_at': stamp, 'updated_at': stamp});
    await legacy.insert('retail_products', {'id': 'legacy-product', 'name': 'Dầu cũ',
      'brand': 'Legacy Brand', 'volume_label': '500 ml', 'product_type': 'Hàng cũ',
      'sale_price': 100000, 'created_at': stamp, 'updated_at': stamp});
    await legacy.insert('inventory_stock', {'product_id': 'legacy-product', 'stock_on_hand': 7, 'updated_at': stamp});
    await legacy.insert('inventory_movements', {'id': 'old-movement', 'product_id': 'legacy-product',
      'movement_type': 'receive', 'quantity_delta': 7, 'stock_before': 0, 'stock_after': 7,
      'note': 'Lịch sử nguyên bản', 'created_at': stamp});
    final oldMovement = await legacy.query('inventory_movements');
    await legacy.close();
    final upgraded = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect(await upgraded.getVersion(), 24);
    final row = (await upgraded.query('retail_products')).single;
    expect(row['id'], 'legacy-product');
    expect(row['group_option_id'], 'old-group');
    expect(row['volume_label'], '500 ml');
    expect(row['unit_name'], '');
    expect(row['unit_option_id'], isNull);
    expect((await upgraded.query('inventory_stock')).single['stock_on_hand'], 7);
    expect(await upgraded.query('inventory_movements', columns: oldMovement.single.keys.toList()), oldMovement);
    expect((await upgraded.query('inventory_movements')).single['source'], 'legacy');
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await SalonDatabase.instance.close();
    final reopened = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect((await reopened.query('retail_products')).single['group_option_id'], 'old-group');
  });

  test('rename keeps stable IDs; archived options retained only on existing associations', () async {
    final catalogs = SqliteCatalogOptionsRepository(SalonDatabase.instance);
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final inventory = SqliteInventoryRepository(SalonDatabase.instance);
    final saved = await products.saveProduct(product());
    await inventory.receiveStock(productId: saved.id, quantity: 4, note: 'Đợt cũ');
    final units = await catalogs.fetchOptions(CatalogOptionKind.productUnit);
    final unit = units.singleWhere((o) => o.name == 'Chai');
    expect(unit.usageCount, 1);
    await expectLater(products.saveProduct(product(unit: 'Hộp'), existingId: saved.id),
      throwsA(isA<StateError>()));
    expect((await products.fetchProducts()).single.unitName, 'Chai');
    final history = await (await SalonDatabase.instance.database).query('inventory_movements');
    await catalogs.renameOption(unit.id, 'Chai bán lẻ');
    final renamed = (await products.fetchProducts()).single;
    expect(renamed.unitOptionId, unit.id);
    expect(renamed.unitName, 'Chai bán lẻ');
    expect(renamed.volumeLabel, '500 ml');
    expect((await inventory.fetchInventoryProducts()).single.unitName, 'Chai bán lẻ');
    expect(await (await SalonDatabase.instance.database).query('inventory_movements'), history);
    await expectLater(products.saveProduct(product(unitId: unit.id), existingId: saved.id),
      throwsA(isA<StateError>())); // stale editor cannot resurrect an old name
    await catalogs.setOptionActive(unit.id, false);
    expect(await catalogs.fetchOptionNames(CatalogOptionKind.productUnit), isNot(contains('Chai bán lẻ')));
    await products.saveProduct(product(unit: 'Chai bán lẻ', unitId: unit.id), existingId: saved.id);
    await expectLater(products.saveProduct(product(unit: 'Chai bán lẻ')), throwsA(isA<StateError>()));
    await expectLater(catalogs.createOption(CatalogOptionKind.productUnit, ' chai bán lẻ '), throwsA(isA<StateError>()));
    await expectLater(catalogs.renameOption(unit.id, 'Hộp'), throwsA(isA<StateError>()));
    expect((await products.fetchProducts()), hasLength(1));
    await catalogs.setOptionActive(unit.id, true);
    expect(await catalogs.fetchOptionNames(CatalogOptionKind.productUnit), contains('Chai bán lẻ'));
    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect((await products.fetchProducts()).single.unitOptionId, unit.id);
  });

  test('service group rename and archive preserve association and reject new selection', () async {
    final repo = SqliteServicesRepository(SalonDatabase.instance, const FakeSalonDataSource());
    final catalogs = SqliteCatalogOptionsRepository(SalonDatabase.instance);
    ServiceUpsertInput input(String group) => ServiceUpsertInput(name: 'Dịch vụ thật', category: group,
      durationMinutes: 30, price: 100000, description: '', isActive: true, popularityLabel: 'Ổn định');
    final service = await repo.saveService(input('Nhóm riêng'));
    final group = (await catalogs.fetchOptions(CatalogOptionKind.serviceGroup)).singleWhere((o) => o.name == 'Nhóm riêng');
    await catalogs.renameOption(group.id, 'Chăm sóc riêng');
    final found = (await repo.fetchServicesView()).singleWhere((s) => s.id == service.id);
    expect(found.groupOptionId, group.id);
    expect(found.category, 'Chăm sóc riêng');
    await catalogs.setOptionActive(group.id, false);
    await repo.saveService(input('Chăm sóc riêng'), existingId: service.id);
    await expectLater(repo.saveService(input('Chăm sóc riêng')), throwsA(isA<StateError>()));
    expect((await catalogs.fetchOptions(CatalogOptionKind.serviceGroup)).singleWhere((o) => o.id == group.id).usageCount, 1);
  });
}
