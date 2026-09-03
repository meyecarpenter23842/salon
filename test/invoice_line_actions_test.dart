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

  test('split line keeps one SKU in two rows and works before customer selection', () async {
    final database = await SalonDatabase.instance.database;
    final repository = SqliteInvoicesRepository(SalonDatabase.instance);
    final now = DateTime.now();

    const customerId = 'customer-line-split-test';
    const productId = 'product-line-split-test';
    const unitPrice = 120000;
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
    await database.delete(
      'retail_products',
      where: 'id = ?',
      whereArgs: [productId],
    );
    await database.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
    );

    await database.insert('customers', {
      'id': customerId,
      'full_name': 'Khách tách dòng',
      'phone': '0900000201',
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
      'name': 'Dầu gội quà tặng',
      'brand': 'Salon',
      'volume_label': '250ml',
      'product_type': 'Chăm sóc tóc',
      'sale_price': unitPrice,
      'commission_percent': 0,
      'is_active': 1,
      'is_hidden_from_staff': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await repository.addInvoiceProduct(productId);
    final doubledDraft = await repository.addInvoiceProduct(productId);
    expect(doubledDraft.customerId, isEmpty);
    expect(doubledDraft.lines, hasLength(1));
    expect(doubledDraft.lines.single.quantity, 2);

    final discountedDraft = await repository.updateInvoiceLineDiscount(
      doubledDraft.lines.single.id,
      lineDiscount,
    );
    await repository.updateInvoiceDiscount(billDiscount);

    final splitDraft = await repository.splitInvoiceLine(
      discountedDraft.lines.single.id,
    );

    final productLines = splitDraft.lines
        .where((line) => line.productId == productId)
        .toList(growable: false);
    expect(productLines, hasLength(2));
    expect(productLines.every((line) => line.quantity == 1), isTrue);
    expect(
      productLines.fold<int>(0, (sum, line) => sum + line.discountAmount),
      lineDiscount,
    );
    expect(splitDraft.subtotal, unitPrice * 2 - lineDiscount);
    expect(splitDraft.discountAmount, billDiscount);
    expect(
      splitDraft.totalAmount,
      unitPrice * 2 - lineDiscount - billDiscount,
    );

    await repository.selectInvoiceCustomer(customerId);
    final persistedItems = await database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: const ['invoice-draft-001'],
    );
    expect(persistedItems, hasLength(2));
    expect(persistedItems.every((item) => item['product_id'] == productId), isTrue);
  });
}
