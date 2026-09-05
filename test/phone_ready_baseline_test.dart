import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/entity_id.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_service_formula_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testDataRoot = Directory(
    path.join(Directory.systemTemp.path, 'hair_spa_manager_test_data'),
  );

  setUp(() async {
    await SalonDatabase.instance.close();
    if (await testDataRoot.exists()) {
      await testDataRoot.delete(recursive: true);
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('EntityId tạo UUID v4 có prefix và không dựa vào timestamp', () {
    final first = EntityId.create('customer');
    final second = EntityId.create('customer');

    _expectPrefixedUuid(first, 'customer');
    _expectPrefixedUuid(second, 'customer');
    expect(second, isNot(first));
  });

  test('top-level business tables giữ TEXT id + created_at/updated_at', () async {
    expect(
      DatabaseSchema.version,
      11,
      reason: 'Schema 11 bổ sung kho hàng nội bộ mà không đổi identity bảng nghiệp vụ.',
    );

    final database = await SalonDatabase.instance.initialize();
    const tables = <String>[
      'customers',
      'employees',
      'services',
      'service_formulas',
      'retail_products',
      'appointments',
      'invoices',
    ];

    for (final table in tables) {
      final columns = await database.rawQuery('PRAGMA table_info($table)');
      final byName = <String, Map<String, Object?>>{
        for (final column in columns) column['name'].toString(): column,
      };

      expect(byName, contains('id'), reason: '$table phải có primary identity.');
      expect(
        byName['id']?['type']?.toString().toUpperCase(),
        'TEXT',
        reason: '$table.id phải tiếp tục dùng TEXT để tương thích ID cũ/UUID.',
      );
      expect(
        byName,
        contains('created_at'),
        reason: '$table thiếu created_at.',
      );
      expect(
        byName,
        contains('updated_at'),
        reason: '$table thiếu updated_at.',
      );
    }
  });

  test('management repositories tạo UUID mới và giữ ID cũ khi update', () async {
    const fakeData = FakeSalonDataSource();
    final customers = SqliteCustomersRepository(SalonDatabase.instance);
    final services = SqliteServicesRepository(SalonDatabase.instance, fakeData);
    final employees = SqliteEmployeesRepository(SalonDatabase.instance, fakeData);
    final products = SqliteRetailProductsRepository(SalonDatabase.instance);
    final formulas = SqliteServiceFormulaRepository(SalonDatabase.instance);

    final customer = await customers.saveCustomer(
      const CustomerUpsertInput(
        fullName: 'Khách DB7',
        phone: '0900000701',
        email: '',
        tier: 'Member',
        favoriteService: '',
        hairProfile: '',
        note: '',
      ),
    );
    _expectPrefixedUuid(customer.id, 'customer');

    final independentCustomer = await customers.saveCustomer(
      const CustomerUpsertInput(
        fullName: 'Khách DB7 khác',
        phone: '0900000799',
        email: '',
        tier: 'Member',
        favoriteService: '',
        hairProfile: '',
        note: 'record độc lập',
      ),
    );
    _expectPrefixedUuid(independentCustomer.id, 'customer');
    expect(independentCustomer.id, isNot(customer.id));

    final updatedCustomer = await customers.saveCustomer(
      const CustomerUpsertInput(
        fullName: 'Khách DB7 Updated',
        phone: '0900000701',
        email: '',
        tier: 'Member',
        favoriteService: '',
        hairProfile: '',
        note: '',
      ),
      existingId: customer.id,
    );
    expect(updatedCustomer.id, customer.id);

    final service = await services.saveService(
      const ServiceUpsertInput(
        name: 'Dịch vụ DB7',
        category: 'Chăm sóc',
        durationMinutes: 45,
        price: 250000,
        description: '',
        isActive: true,
        popularityLabel: 'Ổn định',
      ),
    );
    _expectPrefixedUuid(service.id, 'service');

    final employee = await employees.saveEmployee(
      const EmployeeUpsertInput(
        fullName: 'Nhân viên DB7',
        role: 'Stylist',
        status: 'Đang làm việc',
        phone: '0900000702',
        shift: '09:00 - 18:00',
        specialty: 'Chăm sóc',
        commissionLabel: '10%',
        todaySchedule: '',
        servicesDone: 0,
        monthlyRevenue: '0đ',
        rating: '5.0',
        note: '',
      ),
    );
    final employeeId = employee['id']?.toString() ?? '';
    _expectPrefixedUuid(employeeId, 'emp');

    final product = await products.saveProduct(
      const RetailProductUpsertInput(
        name: 'Sản phẩm DB7',
        brand: 'Salon',
        volumeLabel: '100ml',
        productType: 'Serum',
        salePrice: 180000,
        commissionPercent: 5.0,
        isActive: true,
        isHiddenFromStaff: false,
      ),
    );
    _expectPrefixedUuid(product.id, 'product');

    final formula = await formulas.saveFormula(
      serviceId: service.id,
      serviceName: service.name,
      formulaText: 'DB7 formula',
      isHiddenFromStaff: true,
    );
    _expectPrefixedUuid(formula.id, 'formula');
  });
}

void _expectPrefixedUuid(String value, String prefix) {
  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  expect(value, startsWith('$prefix-'));
  final uuid = value.substring(prefix.length + 1);
  expect(
    uuidPattern.hasMatch(uuid),
    isTrue,
    reason: '$value không phải UUID v4 hợp lệ.',
  );
}
