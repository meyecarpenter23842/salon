import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/retail_product_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_retail_products_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('service and product detail use paid invoice lines only', () async {
    final database = await SalonDatabase.instance.database;
    const fake = FakeSalonDataSource();
    final serviceRepository = SqliteServicesRepository(SalonDatabase.instance, fake);
    final productRepository = SqliteRetailProductsRepository(SalonDatabase.instance);
    final employeeRepository = SqliteEmployeesRepository(SalonDatabase.instance, fake);
    final now = DateTime.now();
    final suffix = now.microsecondsSinceEpoch;

    final service = await serviceRepository.saveService(
      ServiceUpsertInput.normalized(
        name: 'Dịch vụ V2-6 $suffix',
        category: 'Chăm sóc',
        durationMinutes: 60,
        price: 150000,
        description: 'Dịch vụ test chi tiết.',
        isActive: true,
        popularityLabel: 'Ổn định',
      ),
    );
    final product = await productRepository.saveProduct(
      RetailProductUpsertInput(
        name: 'Sản phẩm V2-6 $suffix',
        brand: 'Salon Test',
        volumeLabel: '250ml',
        productType: 'Gội',
        salePrice: 100000,
        commissionPercent: 10,
        isActive: true,
        isHiddenFromStaff: false,
      ),
    );
    final employee = await employeeRepository.saveEmployee(
      EmployeeUpsertInput(
        fullName: 'Stylist V2-6 $suffix',
        role: 'Stylist chính',
        status: 'Đang làm việc',
        phone: '090$suffix',
        shift: '09:00 - 18:00',
        specialty: 'Chăm sóc tóc',
        commissionLabel: '15%',
        todaySchedule: '',
        servicesDone: 0,
        monthlyRevenue: '',
        rating: '5.0',
        note: '',
      ),
    );
    final employeeId = employee['id']!.toString();
    final customerId = 'customer-v26-$suffix';
    final paidInvoiceId = 'invoice-v26-paid-$suffix';
    final unpaidInvoiceId = 'invoice-v26-unpaid-$suffix';

    await database.insert('customers', {
      'id': customerId,
      'full_name': 'Khách V2-6',
      'phone': '091$suffix',
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': service.name,
      'last_visit_at': now.toIso8601String(),
      'hair_profile': '',
      'visit_count': 1,
      'total_spent': 570000,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('invoices', {
      'id': paidInvoiceId,
      'appointment_id': null,
      'customer_id': customerId,
      'subtotal': 600000,
      'discount_amount': 30000,
      'total_amount': 570000,
      'payment_method': 'Tiền mặt',
      'paid_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.insert('invoice_items', {
      'id': 'service-line-paid-$suffix',
      'invoice_id': paidInvoiceId,
      'item_type': 'service',
      'service_id': service.id,
      'product_id': null,
      'employee_id': employeeId,
      'title': service.name,
      'quantity': 2,
      'unit_price': 150000,
      'discount_amount': 20000,
      'total_price': 280000,
    });
    await database.insert('invoice_items', {
      'id': 'product-line-paid-$suffix',
      'invoice_id': paidInvoiceId,
      'item_type': 'product',
      'service_id': null,
      'product_id': product.id,
      'employee_id': null,
      'title': product.name,
      'quantity': 3,
      'unit_price': 100000,
      'discount_amount': 10000,
      'total_price': 290000,
    });

    await database.insert('invoices', {
      'id': unpaidInvoiceId,
      'appointment_id': null,
      'customer_id': customerId,
      'subtotal': 900000,
      'discount_amount': 0,
      'total_amount': 900000,
      'payment_method': 'Tiền mặt',
      'paid_at': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await database.insert('invoice_items', {
      'id': 'service-line-unpaid-$suffix',
      'invoice_id': unpaidInvoiceId,
      'item_type': 'service',
      'service_id': service.id,
      'product_id': null,
      'employee_id': employeeId,
      'title': service.name,
      'quantity': 4,
      'unit_price': 150000,
      'discount_amount': 0,
      'total_price': 600000,
    });
    await database.insert('invoice_items', {
      'id': 'product-line-unpaid-$suffix',
      'invoice_id': unpaidInvoiceId,
      'item_type': 'product',
      'service_id': null,
      'product_id': product.id,
      'employee_id': null,
      'title': product.name,
      'quantity': 3,
      'unit_price': 100000,
      'discount_amount': 0,
      'total_price': 300000,
    });

    final serviceDetail = await serviceRepository.fetchServiceDetail(service.id);
    expect(serviceDetail['monthRevenueValue'], 280000);
    expect(serviceDetail['monthQuantity'], 2);
    expect(serviceDetail['monthCustomerCount'], 1);
    expect(serviceDetail['monthLineDiscountValue'], 20000);
    final topStaff = (serviceDetail['topStaff'] as List).cast<Map<String, Object?>>();
    expect(topStaff.single['employeeId'], employeeId);
    expect(topStaff.single['quantity'], 2);
    final serviceHistory =
        (serviceDetail['history'] as List).cast<Map<String, Object?>>();
    expect(serviceHistory.length, 1);
    expect(serviceHistory.single['invoiceId'], paidInvoiceId);
    expect(serviceHistory.single['customerName'], 'Khách V2-6');
    expect(serviceHistory.single['unitPriceValue'], 150000);
    expect(serviceHistory.single['discountValue'], 20000);

    final productDetail = await productRepository.fetchProductDetail(product.id);
    expect(productDetail['monthRevenueValue'], 290000);
    expect(productDetail['monthQuantity'], 3);
    expect(productDetail['monthCustomerCount'], 1);
    expect(productDetail['monthLineDiscountValue'], 10000);
    final productHistory =
        (productDetail['history'] as List).cast<Map<String, Object?>>();
    expect(productHistory.length, 1);
    expect(productHistory.single['invoiceId'], paidInvoiceId);
    expect(productHistory.single['customerName'], 'Khách V2-6');
    expect(productHistory.single['unitPriceValue'], 100000);
    expect(productHistory.single['discountValue'], 10000);
  });
}
