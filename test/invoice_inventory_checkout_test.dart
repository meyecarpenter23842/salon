import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/invoice_adjustment.dart';
import 'package:salonmanager/core/repositories/invoice_adjustment_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_inventory_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test(
    'product quantity exceeds stock and checkout writes one negative sale movement',
    () async {
      final database = await SalonDatabase.instance.database;
      final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
      final inventory = SqliteInventoryRepository(SalonDatabase.instance);
      final now = DateTime.now();

      const customerId = 'cust-inventory-checkout';
      const productId = 'product-inventory-checkout';
      await _insertCustomer(database, customerId, now);
      await _insertProduct(database, productId, now);
      await inventory.receiveStock(
        productId: productId,
        quantity: 2,
        note: 'Nhập test',
      );

      await invoices.selectInvoiceCustomer(customerId);
      await invoices.addInvoiceProduct(productId);
      final doubled = await invoices.addInvoiceProduct(productId);
      expect(doubled.lines.single.quantity, 2);

      final tripled = await invoices.addInvoiceProduct(productId);
      expect(tripled.lines.single.quantity, 3);
      await invoices.updateInvoiceLineQuantity(doubled.lines.single.id, 5);

      await invoices.checkoutInvoice();

      final stock = await inventory.fetchInventoryProducts();
      final product = stock.singleWhere((item) => item.id == productId);
      expect(product.stockOnHand, -3);
      expect(product.isNegativeStock, isTrue);

      final history = await invoices.fetchRecentInvoices(customerId: customerId);
      expect(history, hasLength(1));

      final movements = await inventory.fetchInventoryMovements(
        productId: productId,
      );
      final sale = movements.singleWhere((item) => item.movementType == 'sale');
      expect(sale.quantityDelta, -5);
      expect(sale.stockBefore, 2);
      expect(sale.stockAfter, -3);
      expect(sale.note, contains(history.single.id));
    },
  );

  test(
    'checkout uses latest stock atomically when inventory changed',
    () async {
      final database = await SalonDatabase.instance.database;
      final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
      final inventory = SqliteInventoryRepository(SalonDatabase.instance);
      final now = DateTime.now();

      const customerId = 'cust-inventory-race';
      const productId = 'product-inventory-race';
      await _insertCustomer(database, customerId, now);
      await _insertProduct(database, productId, now);
      await inventory.receiveStock(productId: productId, quantity: 2);

      await invoices.selectInvoiceCustomer(customerId);
      await invoices.addInvoiceProduct(productId);
      final draft = await invoices.addInvoiceProduct(productId);
      expect(draft.lines.single.quantity, 2);

      await inventory.adjustStock(
        productId: productId,
        newQuantity: 1,
        note: 'Tồn thay đổi trước checkout',
      );

      await invoices.checkoutInvoice();
      final stock = await inventory.fetchInventoryProducts();
      expect(stock.singleWhere((item) => item.id == productId).stockOnHand, -1);
      final movements = await inventory.fetchInventoryMovements(productId: productId);
      final sale = movements.singleWhere((item) => item.movementType == 'sale');
      expect(sale.stockBefore, 1);
      expect(sale.stockAfter, -1);
      expect(await database.query('invoices', where: 'paid_at IS NOT NULL'), hasLength(1));
    },
  );

  test('never received product sells negative, partial receipts and void keep exact stock', () async {
    final db = await SalonDatabase.instance.database;
    final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
    final inventory = SqliteInventoryRepository(SalonDatabase.instance);
    final now = DateTime.now();
    await _insertCustomer(db, 'negative-customer', now);
    await _insertProduct(db, 'negative-product', now);
    await invoices.selectInvoiceCustomer('negative-customer');
    final draft = await invoices.addInvoiceProduct('negative-product');
    await invoices.updateInvoiceLineQuantity(draft.lines.single.id, 5);
    await invoices.checkoutInvoice();
    expect((await db.query('inventory_stock')).single['stock_on_hand'], -5);
    await expectLater(invoices.checkoutInvoice(), throwsA(isA<StateError>()));
    expect(await db.query('inventory_movements'), hasLength(1));
    final replenished = await inventory.receiveStock(productId: 'negative-product', quantity: 3);
    expect(replenished.stockOnHand, -2);
    expect(replenished.isNegativeStock, isTrue);
    await expectLater(inventory.receiveStock(productId: 'negative-product', quantity: 0), throwsArgumentError);
    await expectLater(inventory.adjustStock(productId: 'negative-product', newQuantity: -1), throwsArgumentError);
    final paid = (await invoices.fetchRecentInvoices(customerId: 'negative-customer')).single;
    await invoices.voidInvoice(paid.id, reason: 'Hủy test');
    expect((await db.query('inventory_stock')).single['stock_on_hand'], 3);
    await expectLater(invoices.voidInvoice(paid.id, reason: 'Thử lại'), throwsA(isA<StateError>()));
    expect(await db.query('inventory_movements', where: "movement_type = 'void'"), hasLength(1));
  });

  test(
    'refund keeps sold stock while void restores only stock deducted by checkout',
    () async {
      final database = await SalonDatabase.instance.database;
      final invoices = SqliteInvoicesRepository(SalonDatabase.instance);
      final adjustments = invoices as InvoiceAdjustmentRepository;
      final inventory = SqliteInventoryRepository(SalonDatabase.instance);
      final now = DateTime.now();

      const customerId = 'cust-inventory-adjustment';
      const productId = 'product-inventory-adjustment';
      await _insertCustomer(database, customerId, now);
      await _insertProduct(database, productId, now);
      await inventory.receiveStock(productId: productId, quantity: 3);

      await invoices.selectInvoiceCustomer(customerId);
      await invoices.addInvoiceProduct(productId);
      await invoices.checkoutInvoice();
      var history = await invoices.fetchRecentInvoices(customerId: customerId);
      final refundedInvoice = history.first;
      await adjustments.refundInvoice(
        refundedInvoice.id,
        reason: 'Khách hoàn tiền',
      );

      var stock = await inventory.fetchInventoryProducts();
      expect(
        stock.singleWhere((item) => item.id == productId).stockOnHand,
        2,
      );

      await invoices.selectInvoiceCustomer(customerId);
      await invoices.addInvoiceProduct(productId);
      await invoices.checkoutInvoice();
      history = await invoices.fetchRecentInvoices(customerId: customerId);
      final voidedInvoice = history.firstWhere(
        (invoice) => invoice.id != refundedInvoice.id,
      );

      stock = await inventory.fetchInventoryProducts();
      expect(
        stock.singleWhere((item) => item.id == productId).stockOnHand,
        1,
      );

      final voidAdjustment = await adjustments.voidInvoice(
        voidedInvoice.id,
        reason: 'Chốt nhầm bill',
      );
      expect(voidAdjustment.type, InvoiceAdjustmentType.voided);

      stock = await inventory.fetchInventoryProducts();
      expect(
        stock.singleWhere((item) => item.id == productId).stockOnHand,
        2,
      );

      final movements = await inventory.fetchInventoryMovements(
        productId: productId,
      );
      expect(
        movements.where((item) => item.movementType == 'sale'),
        hasLength(2),
      );
      final voidMovement = movements.singleWhere(
        (item) => item.movementType == 'void',
      );
      expect(voidMovement.quantityDelta, 1);
      expect(voidMovement.note, contains(voidedInvoice.id));

      const legacyInvoiceId = 'invoice-legacy-before-stock-link';
      await database.insert('invoices', {
        'id': legacyInvoiceId,
        'appointment_id': null,
        'customer_id': customerId,
        'subtotal': 100000,
        'discount_amount': 0,
        'total_amount': 100000,
        'payment_method': 'Tiền mặt',
        'paid_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await database.insert('invoice_items', {
        'id': 'line-$legacyInvoiceId',
        'invoice_id': legacyInvoiceId,
        'item_type': 'product',
        'service_id': null,
        'product_id': productId,
        'employee_id': null,
        'title': 'Sản phẩm legacy',
        'quantity': 1,
        'unit_price': 100000,
        'discount_amount': 0,
        'total_price': 100000,
      });

      await adjustments.voidInvoice(
        legacyInvoiceId,
        reason: 'Hủy hóa đơn legacy',
      );
      stock = await inventory.fetchInventoryProducts();
      expect(
        stock.singleWhere((item) => item.id == productId).stockOnHand,
        2,
        reason: 'Hóa đơn cũ không có sale movement nên không được cộng tồn giả.',
      );
    },
  );
}

Future<void> _insertCustomer(
  Database database,
  String id,
  DateTime now,
) async {
  await database.insert('customers', {
    'id': id,
    'full_name': 'Khách tồn kho',
    'phone': '0900780000',
    'email': null,
    'tier': 'Member',
    'loyalty_points': 0,
    'favorite_service': '',
    'last_visit_at': null,
    'hair_profile': '',
    'visit_count': 0,
    'total_spent': 0,
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}

Future<void> _insertProduct(
  Database database,
  String id,
  DateTime now,
) async {
  await database.insert('retail_products', {
    'id': id,
    'name': 'Sản phẩm tồn kho',
    'brand': 'Salon',
    'volume_label': '250ml',
    'product_type': 'Chăm sóc tóc',
    'sale_price': 180000,
    'commission_percent': 0,
    'is_active': 1,
    'is_hidden_from_staff': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
