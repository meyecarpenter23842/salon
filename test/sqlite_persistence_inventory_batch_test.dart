import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/inventory_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_inventory_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_service_formula_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('editing referenced entities uses update semantics and preserves relations', () async {
    const fakeData = FakeSalonDataSource();
    final customers = SqliteCustomersRepository(SalonDatabase.instance);
    final services = SqliteServicesRepository(SalonDatabase.instance, fakeData);
    final employees = SqliteEmployeesRepository(SalonDatabase.instance, fakeData);
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final formulas = SqliteServiceFormulaRepository(SalonDatabase.instance);

    final customer = await customers.saveCustomer(_customerInput());
    final service = await services.saveService(_serviceInput());
    final employee = await employees.saveEmployee(_employeeInput());
    final product = await products.saveProduct(_productInput());
    final employeeId = employee['id']!.toString();

    final formula = await formulas.saveFormula(
      serviceId: service.id,
      serviceName: service.name,
      formulaText: 'Màu 7.1 + oxy 6%',
      isHiddenFromStaff: true,
    );

    final database = await SalonDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await database.insert('appointments', {
      'id': 'appt-fk-edit',
      'customer_id': customer.id,
      'service_id': service.id,
      'employee_id': employeeId,
      'starts_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'status': 'Đã xác nhận',
      'note': '',
      'total_amount': service.price,
      'customer_name': customer.fullName,
      'customer_phone': customer.phone,
      'service_name': service.name,
      'staff_name': employee['name']!.toString(),
      'duration_minutes': service.durationMinutes,
      'slot_label': '10:00',
      'date_label': 'Ngày mai',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('appointment_services', {
      'id': 'apptsvc-fk-edit',
      'appointment_id': 'appt-fk-edit',
      'service_id': service.id,
      'title': service.name,
      'quantity': 1,
      'unit_price': service.price,
      'duration_minutes': service.durationMinutes,
    });
    await database.insert('invoices', {
      'id': 'invoice-fk-edit',
      'appointment_id': 'appt-fk-edit',
      'customer_id': customer.id,
      'subtotal': service.price + product.salePrice,
      'discount_amount': 0,
      'total_amount': service.price + product.salePrice,
      'payment_method': 'Tiền mặt',
      'paid_at': now,
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('invoice_items', {
      'id': 'invoice-service-fk-edit',
      'invoice_id': 'invoice-fk-edit',
      'item_type': 'service',
      'service_id': service.id,
      'product_id': null,
      'employee_id': employeeId,
      'title': service.name,
      'quantity': 1,
      'unit_price': service.price,
      'discount_amount': 0,
      'total_price': service.price,
    });
    await database.insert('invoice_items', {
      'id': 'invoice-product-fk-edit',
      'invoice_id': 'invoice-fk-edit',
      'item_type': 'product',
      'service_id': null,
      'product_id': product.id,
      'employee_id': null,
      'title': product.name,
      'quantity': 1,
      'unit_price': product.salePrice,
      'discount_amount': 0,
      'total_price': product.salePrice,
    });

    final customerCreatedAt = (await _row(database, 'customers', customer.id))['created_at'];
    final serviceCreatedAt = (await _row(database, 'services', service.id))['created_at'];
    final employeeCreatedAt = (await _row(database, 'employees', employeeId))['created_at'];
    final productCreatedAt = (await _row(database, 'retail_products', product.id))['created_at'];

    await customers.saveCustomer(
      _customerInput(name: 'Khách đã sửa', phone: '0901 222 333'),
      existingId: customer.id,
    );
    await services.saveService(
      _serviceInput(name: 'Dịch vụ đã sửa', price: 450000),
      existingId: service.id,
    );
    await employees.saveEmployee(
      _employeeInput(name: 'Nhân viên đã sửa'),
      existingId: employeeId,
    );
    await products.saveProduct(
      _productInput(name: 'Sản phẩm đã sửa', price: 310000),
      existingId: product.id,
    );

    final appointment = await _row(database, 'appointments', 'appt-fk-edit');
    expect(appointment['customer_id'], customer.id);
    expect(appointment['service_id'], service.id);
    expect(appointment['employee_id'], employeeId);

    final appointmentService = await _row(
      database,
      'appointment_services',
      'apptsvc-fk-edit',
    );
    expect(appointmentService['service_id'], service.id);

    final invoice = await _row(database, 'invoices', 'invoice-fk-edit');
    expect(invoice['customer_id'], customer.id);

    final serviceLine = await _row(
      database,
      'invoice_items',
      'invoice-service-fk-edit',
    );
    expect(serviceLine['service_id'], service.id);
    expect(serviceLine['employee_id'], employeeId);

    final productLine = await _row(
      database,
      'invoice_items',
      'invoice-product-fk-edit',
    );
    expect(productLine['product_id'], product.id);

    final formulaRows = await database.query(
      'service_formulas',
      where: 'id = ?',
      whereArgs: [formula.id],
    );
    expect(formulaRows, hasLength(1));
    expect(formulaRows.single['service_id'], service.id);
    expect(formulaRows.single['formula_text'], 'Màu 7.1 + oxy 6%');

    expect((await _row(database, 'customers', customer.id))['created_at'], customerCreatedAt);
    expect((await _row(database, 'services', service.id))['created_at'], serviceCreatedAt);
    expect((await _row(database, 'employees', employeeId))['created_at'], employeeCreatedAt);
    expect((await _row(database, 'retail_products', product.id))['created_at'], productCreatedAt);
  });

  test('editing a missing entity never silently creates a replacement', () async {
    const fakeData = FakeSalonDataSource();
    final customers = SqliteCustomersRepository(SalonDatabase.instance);
    final services = SqliteServicesRepository(SalonDatabase.instance, fakeData);
    final employees = SqliteEmployeesRepository(SalonDatabase.instance, fakeData);
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);

    await expectLater(
      customers.saveCustomer(_customerInput(), existingId: 'missing-customer'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      services.saveService(_serviceInput(), existingId: 'missing-service'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      employees.saveEmployee(_employeeInput(), existingId: 'missing-employee'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      products.saveProduct(_productInput(), existingId: 'missing-product'),
      throwsA(isA<StateError>()),
    );

    final database = await SalonDatabase.instance.database;
    expect(await _count(database, 'customers'), 0);
    expect(await _count(database, 'services'), 0);
    expect(await _count(database, 'employees'), 0);
    expect(await _count(database, 'retail_products'), 0);
  });

  test('inventory receive batch rolls back earlier rows when a later row fails', () async {
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final inventory = SqliteInventoryRepository(SalonDatabase.instance);
    final product = await products.saveProduct(_productInput(name: 'Batch A'));

    await inventory.receiveStock(productId: product.id, quantity: 5, note: 'seed');
    final movementsBefore = await inventory.fetchInventoryMovements();

    await expectLater(
      inventory.receiveStockBatch(
        lines: [
          InventoryStockBatchLine(productId: product.id, quantity: 3),
          const InventoryStockBatchLine(
            productId: 'missing-product',
            quantity: 2,
          ),
        ],
        note: 'must rollback',
      ),
      throwsA(isA<StateError>()),
    );

    final stock = await inventory.fetchInventoryProducts();
    expect(stock.singleWhere((item) => item.id == product.id).stockOnHand, 5);
    final movementsAfter = await inventory.fetchInventoryMovements();
    expect(movementsAfter, hasLength(movementsBefore.length));
    expect(movementsAfter.where((item) => item.note == 'must rollback'), isEmpty);
  });

  test('inventory adjust batch rolls back stock and movements on later validation error', () async {
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final inventory = SqliteInventoryRepository(SalonDatabase.instance);
    final first = await products.saveProduct(_productInput(name: 'Adjust A'));
    final second = await products.saveProduct(_productInput(name: 'Adjust B'));

    await inventory.receiveStockBatch(
      lines: [
        InventoryStockBatchLine(productId: first.id, quantity: 5),
        InventoryStockBatchLine(productId: second.id, quantity: 7),
      ],
      note: 'seed',
    );
    final movementsBefore = await inventory.fetchInventoryMovements();

    await expectLater(
      inventory.adjustStockBatch(
        lines: [
          InventoryStockBatchLine(productId: first.id, quantity: 2),
          InventoryStockBatchLine(productId: second.id, quantity: 7),
        ],
        note: 'must rollback adjust',
      ),
      throwsA(isA<StateError>()),
    );

    final stock = await inventory.fetchInventoryProducts();
    expect(stock.singleWhere((item) => item.id == first.id).stockOnHand, 5);
    expect(stock.singleWhere((item) => item.id == second.id).stockOnHand, 7);
    final movementsAfter = await inventory.fetchInventoryMovements();
    expect(movementsAfter, hasLength(movementsBefore.length));
    expect(
      movementsAfter.where((item) => item.note == 'must rollback adjust'),
      isEmpty,
    );
  });
}

CustomerUpsertInput _customerInput({
  String name = 'Khách test',
  String phone = '0901000001',
}) {
  return CustomerUpsertInput(
    fullName: name,
    phone: phone,
    email: 'khach@example.com',
    tier: 'Member',
    favoriteService: 'Cắt tóc',
    hairProfile: 'Tóc thường',
    note: 'test',
  );
}

ServiceUpsertInput _serviceInput({
  String name = 'Dịch vụ test',
  int price = 400000,
}) {
  return ServiceUpsertInput(
    name: name,
    category: 'Chăm sóc',
    durationMinutes: 60,
    price: price,
    description: 'test',
    isActive: true,
    popularityLabel: 'Ổn định',
  );
}

EmployeeUpsertInput _employeeInput({String name = 'Nhân viên test'}) {
  return EmployeeUpsertInput(
    fullName: name,
    role: 'Stylist',
    status: 'Đang làm việc',
    phone: '0902000001',
    shift: 'Ca sáng',
    specialty: 'Cắt tóc',
    commissionLabel: '10%',
    todaySchedule: '',
    servicesDone: 0,
    monthlyRevenue: '0 đ',
    rating: '5.0',
    note: 'test',
  );
}

RetailProductUpsertInput _productInput({
  String name = 'Sản phẩm test',
  int price = 300000,
}) {
  return RetailProductUpsertInput(
    name: name,
    brand: 'Test',
    volumeLabel: '500ml',
    productType: 'Gội',
    salePrice: price,
    commissionPercent: 5,
    isActive: true,
    isHiddenFromStaff: false,
  );
}

Future<Map<String, Object?>> _row(
  dynamic database,
  String table,
  String id,
) async {
  final rows = await database.query(
    table,
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  expect(rows, hasLength(1));
  return Map<String, Object?>.from(rows.single);
}

Future<int> _count(dynamic database, String table) async {
  final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM $table');
  final value = rows.single['count'];
  return value is int ? value : int.parse(value.toString());
}
