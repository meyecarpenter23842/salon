import 'support/stock_schema_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/inventory_item.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/inventory_providers.dart';
import 'package:salonmanager/core/repositories/fake_inventory_repository.dart';
import 'package:salonmanager/core/repositories/fake_repositories.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_colors.dart';
import 'package:salonmanager/features/inventory/presentation/pages/inventory_page.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:sqflite/sqflite.dart';
import 'support/mobile_workflow_fixture.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';

RetailProductUpsertInput productInput({int threshold = 5}) => RetailProductUpsertInput(
  name: 'Dầu test', brand: '', volumeLabel: '', unitName: 'Chai',
  productType: 'Gội', salePrice: 100000, commissionPercent: 0,
  isActive: true, isHiddenFromStaff: false, lowStockThreshold: threshold);

InventoryProductItem stockItem(String id, int quantity, {int threshold = 5}) =>
  InventoryProductItem(id: id, name: id, brand: '', volumeLabel: '', unitName: 'Chai',
    productType: 'Gội', stockOnHand: quantity, isActive: true, lowStockThreshold: threshold);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => SalonDatabase.instance.close());
  tearDown(() async => SalonDatabase.instance.close());

  test('threshold persists, schema 18 upgrade preserves negative stock and movements', () async {
    final repo = SqliteRetailProductsRepository(SalonDatabase.instance);
    final saved = await repo.saveProduct(productInput(threshold: 12));
    expect((await repo.fetchProducts()).single.lowStockThreshold, 12);
    await expectLater(repo.saveProduct(productInput(threshold: -1)), throwsArgumentError);
    final db = await SalonDatabase.instance.database;
    await db.insert('inventory_stock', {'product_id': saved.id, 'stock_on_hand': -5, 'updated_at': '2026-10-05'});
    await db.insert('inventory_movements', {'id': 'original', 'product_id': saved.id,
      'movement_type': 'sale', 'quantity_delta': -5, 'stock_before': 0, 'stock_after': -5,
      'note': 'Original', 'created_at': '2026-10-05'});
    final movements = await db.query('inventory_movements');
    await db.execute('ALTER TABLE retail_products DROP COLUMN low_stock_threshold');
    await removeStockDocumentSchema(db);
    await db.setVersion(18);
    await SalonDatabase.instance.close();
    final upgraded = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect(await upgraded.getVersion(), 24);
    expect((await upgraded.query('retail_products')).single['low_stock_threshold'], 5);
    expect((await upgraded.query('inventory_stock')).single['stock_on_hand'], -5);
    expect(await upgraded.query('inventory_movements'), movements);
  });

  test('negative zero low and healthy statuses are distinct with individual thresholds', () {
    expect(stockItem('negative', -1).stockLabel, 'Âm kho');
    expect(stockItem('zero', 0).stockLabel, 'Hết hàng');
    expect(stockItem('low', 8, threshold: 10).stockLabel, 'Sắp hết');
    expect(stockItem('healthy', 8).stockLabel, 'Còn hàng');
    expect(stockItem('disabled', 1, threshold: 0).isLowStock, isFalse);
  });

  test('fake inventory uses same negative and partial receipt policy without replay deduction', () async {
    final product = await FakeRetailProductsRepository.shared().saveProduct(productInput(threshold: 8));
    final stock = FakeInventoryRepository();
    await stock.recordSale('fake-negative-invoice', {product.id: 5});
    await stock.recordSale('fake-negative-invoice', {product.id: 5});
    final received = await stock.receiveStock(productId: product.id, quantity: 3);
    expect(received.stockOnHand, -2);
    expect(received.lowStockThreshold, 8);
    await expectLater(stock.adjustStock(productId: product.id, newQuantity: -1), throwsArgumentError);
  });

  test('two phones checkout different bills from zero atomically and replay after restart', () async {
    final f = await mobileFixture();
    await f.db.delete('inventory_stock');
    final a = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    final b = (await f.run(LanWriteOperation.sessionCreate, {})).id;
    for (final id in [a, b]) {
      await f.run(LanWriteOperation.sessionSelectCustomer, {'customerId': 'customer-1'}, id: id);
      await f.run(LanWriteOperation.sessionAddProduct, {'productId': 'product-1'}, id: id);
      final lines = (await f.service.editor('session', id)).values['lines'] as List;
      await f.run(LanWriteOperation.sessionQuantity, {'lineId': (lines.single as Map)['id'], 'quantity': 3}, id: id);
    }
    final one = await f.command(LanWriteOperation.sessionCheckout, {}, id: a);
    final two = await f.command(LanWriteOperation.sessionCheckout, {}, id: b);
    final second = workflowPhone(PhoneWriteRole.cashier, 'b' * 64);
    final paid = await Future.wait([
      f.service.execute(workflowPhone(PhoneWriteRole.cashier), one),
      f.service.execute(second, two),
    ]);
    expect((await f.db.query('inventory_stock')).single['stock_on_hand'], -6);
    expect(await f.db.query('inventory_movements'), hasLength(2));
    expect(await f.db.query('invoices', where: 'paid_at IS NOT NULL'), hasLength(2));
    expect((await f.db.query('customers')).single['visit_count'], 2);
    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect((await f.service.execute(second, two)).id, paid[1].id);
    final db = await SalonDatabase.instance.database;
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -6);
    expect(await db.query('inventory_movements'), hasLength(2));
    final catalog = await f.service.catalog('products', '', 0);
    expect(catalog.items.single.stockOnHand, -6);
    expect(catalog.items.single.isNegativeStock, isTrue);
  });

  testWidgets('phone catalog displays red negative warning and accepts older responses', (tester) async {
    const item = LanCatalogItem('p', 'Product', '100000 đ / Chai', stockOnHand: -5);
    expect(LanCatalogItem.fromJson(item.toJson()).stockOnHand, -5);
    expect(LanCatalogItem.fromJson({'id': 'p', 'title': 'Old', 'subtitle': '100 đ'}).stockOnHand, isNull);
    expect(() => LanCatalogItem.fromJson({'id': 'p', 'title': 'Bad', 'subtitle': '', 'stockOnHand': '-5'}), throwsFormatException);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: CompanionCatalogSubtitle(item: item))));
    final text = find.text('Tồn -5 • Âm kho • Vẫn được bán');
    expect(text, findsOneWidget);
    expect(tester.widget<Text>(text).style!.color, Colors.redAccent);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative inventory is red with icon count and filter at narrow desktop size', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();
    await tester.pumpWidget(ProviderScope(overrides: [
      appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
      inventoryProductsViewProvider.overrideWith((ref) async => [
        stockItem('Negative product', -5), stockItem('Healthy product', 20)]),
      inventoryMovementsViewProvider.overrideWith((ref) async => []),
    ], child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(18), child: InventoryPage())))));
    await tester.pumpAndSettle();
    expect(find.text('1 âm kho'), findsOneWidget);
    expect(find.text('Âm kho'), findsOneWidget);
    expect(tester.widget<Text>(find.text('-5')).style!.color, AppColors.danger);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-stock-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Âm kho (1)').last);
    await tester.pumpAndSettle();
    expect(find.text('Healthy product'), findsNothing);
    expect(find.text('Negative product'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
