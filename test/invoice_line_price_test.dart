import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('manual line price persists without changing catalog price', () async {
    final database = await SalonDatabase.instance.database;
    final repository = SqliteInvoicesRepository(SalonDatabase.instance);
    final now = DateTime.now();
    final suffix = now.microsecondsSinceEpoch;

    final customerId = 'customer-line-price-$suffix';
    final productId = 'product-line-price-$suffix';
    const catalogPrice = 300000;
    const manualPrice = 250000;
    const lineDiscount = 20000;
    const billDiscount = 10000;

    await database.delete(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    await database.delete(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
    );

    await database.insert('customers', {
      'id': customerId,
      'full_name': 'Khách sửa giá',
      'phone': '09${suffix.toString().substring(0, 8)}',
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

    await database.insert('retail_products', {
      'id': productId,
      'name': 'Dầu gội giá tay',
      'brand': 'Salon',
      'volume_label': '250ml',
      'product_type': 'Chăm sóc tóc',
      'sale_price': catalogPrice,
      'commission_percent': 0,
      'is_active': 1,
      'is_hidden_from_staff': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await repository.addInvoiceProduct(productId);
    final doubledDraft = await repository.addInvoiceProduct(productId);
    final lineId = doubledDraft.lines.single.id;

    await repository.updateInvoiceLineDiscount(lineId, lineDiscount);
    await repository.updateInvoiceDiscount(billDiscount);
    final repricedDraft = await repository.updateInvoiceLineUnitPrice(
      lineId,
      manualPrice,
    );

    expect(repricedDraft.customerId, isEmpty);
    expect(repricedDraft.lines.single.quantity, 2);
    expect(repricedDraft.lines.single.unitPrice, manualPrice);
    expect(repricedDraft.lines.single.discountAmount, lineDiscount);
    expect(repricedDraft.lines.single.totalPrice, manualPrice * 2 - lineDiscount);
    expect(repricedDraft.discountAmount, billDiscount);
    expect(
      repricedDraft.totalAmount,
      manualPrice * 2 - lineDiscount - billDiscount,
    );

    final productRows = await database.query(
      'retail_products',
      columns: const ['sale_price'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    expect(productRows.single['sale_price'], catalogPrice);

    await repository.selectInvoiceCustomer(customerId);
    final draftItems = await database.query(
      'invoice_items',
      columns: const ['unit_price'],
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    expect(draftItems.single['unit_price'], manualPrice);

    await repository.checkoutInvoice();
    final history = await repository.fetchRecentInvoices(customerId: customerId);
    expect(history, isNotEmpty);
    expect(history.first.lines.single.unitPrice, manualPrice);
    expect(history.first.lines.single.discountAmount, lineDiscount);
    expect(history.first.totalAmount, manualPrice * 2 - lineDiscount - billDiscount);

    final productAfterCheckout = await database.query(
      'retail_products',
      columns: const ['sale_price'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    expect(productAfterCheckout.single['sale_price'], catalogPrice);
  });

  test('lower manual price clamps discounts to valid totals', () async {
    final database = await SalonDatabase.instance.database;
    final repository = SqliteInvoicesRepository(SalonDatabase.instance);
    final now = DateTime.now();
    final productId = 'product-line-price-clamp-${now.microsecondsSinceEpoch}';

    await database.delete(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    await database.delete(
      'invoices',
      where: 'id = ?',
      whereArgs: const ['invoice-draft-001'],
    );

    await database.insert('retail_products', {
      'id': productId,
      'name': 'Sản phẩm clamp giá',
      'brand': 'Salon',
      'volume_label': '100ml',
      'product_type': 'Chăm sóc tóc',
      'sale_price': 200000,
      'commission_percent': 0,
      'is_active': 1,
      'is_hidden_from_staff': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final draft = await repository.addInvoiceProduct(productId);
    await repository.updateInvoiceLineDiscount(draft.lines.single.id, 150000);
    await repository.updateInvoiceDiscount(50000);

    final repriced = await repository.updateInvoiceLineUnitPrice(
      draft.lines.single.id,
      100000,
    );

    expect(repriced.lines.single.discountAmount, 100000);
    expect(repriced.lines.single.totalPrice, 0);
    expect(repriced.discountAmount, 0);
    expect(repriced.totalAmount, 0);
  });
}
