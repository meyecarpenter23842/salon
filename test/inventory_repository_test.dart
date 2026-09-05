import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_inventory_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('inventory receive and adjust persist stock with movement history', () async {
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final inventory = SqliteInventoryRepository(SalonDatabase.instance);

    final product = await products.saveProduct(
      const RetailProductUpsertInput(
        name: 'Dầu gội test',
        brand: 'Test',
        volumeLabel: '500ml',
        productType: 'Gội',
        salePrice: 250000,
        commissionPercent: 5,
        isActive: true,
        isHiddenFromStaff: false,
      ),
    );

    var stock = await inventory.fetchInventoryProducts();
    expect(stock, hasLength(1));
    expect(stock.single.stockOnHand, 0);

    await inventory.receiveStock(
      productId: product.id,
      quantity: 8,
      note: 'Nhập đầu kỳ',
    );
    stock = await inventory.fetchInventoryProducts();
    expect(stock.single.stockOnHand, 8);

    await inventory.adjustStock(
      productId: product.id,
      newQuantity: 5,
      note: 'Kiểm kê',
    );
    stock = await inventory.fetchInventoryProducts();
    expect(stock.single.stockOnHand, 5);

    final movements = await inventory.fetchInventoryMovements(
      productId: product.id,
    );
    expect(movements, hasLength(2));
    expect(movements[0].movementType, 'adjustment');
    expect(movements[0].quantityDelta, -3);
    expect(movements[0].stockBefore, 8);
    expect(movements[0].stockAfter, 5);
    expect(movements[1].movementType, 'receive');
    expect(movements[1].quantityDelta, 8);
  });
}
