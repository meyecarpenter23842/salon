import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('employee profile derives schedule, revenue and history from real data', () async {
    final database = await SalonDatabase.instance.database;
    final repository = SqliteEmployeesRepository(
      SalonDatabase.instance,
      const FakeSalonDataSource(),
    );
    final now = DateTime.now();
    final suffix = now.microsecondsSinceEpoch;
    final employeeId = 'employee-profile-$suffix';
    final customerId = 'customer-profile-$suffix';
    final serviceId = 'service-profile-$suffix';
    final appointmentId = 'appointment-profile-$suffix';
    final invoiceId = 'invoice-profile-$suffix';
    final itemId = 'item-profile-$suffix';
    final todayAtNoon = DateTime(now.year, now.month, now.day, 12);

    await database.insert('employees', {
      'id': employeeId,
      'full_name': 'Minh Stylist',
      'initials': 'MS',
      'role': 'Stylist chính',
      'status': 'Đang làm việc',
      'phone': '0900000001',
      'email': null,
      'shift_label': '09:00 - 18:00',
      'specialty': 'Nhuộm phục hồi',
      'commission_rate': 0.15,
      'commission_label': '15%',
      'today_schedule': '99 lịch nhập tay',
      'services_done': 99,
      'monthly_revenue_label': '99.000.000đ',
      'rating_label': '4.9',
      'notes': 'Ưu tiên khách màu.',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('customers', {
      'id': customerId,
      'full_name': 'Khách Hồ Sơ NV',
      'phone': '0900000002',
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': 'Nhuộm tóc',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('services', {
      'id': serviceId,
      'name': 'Nhuộm tóc hồ sơ',
      'category': 'Nhuộm',
      'duration_minutes': 120,
      'price': 150000,
      'description': '',
      'is_active': 1,
      'popularity_label': 'Ổn định',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('appointments', {
      'id': appointmentId,
      'customer_id': customerId,
      'service_id': serviceId,
      'employee_id': employeeId,
      'starts_at': todayAtNoon.toIso8601String(),
      'status': 'Đã đặt',
      'note': 'Lịch test hồ sơ nhân viên',
      'total_amount': 150000,
      'customer_name': 'Khách Hồ Sơ NV',
      'customer_phone': '0900000002',
      'service_name': 'Nhuộm tóc hồ sơ',
      'staff_name': 'Minh Stylist',
      'duration_minutes': 120,
      'slot_label': 'Ghế 01',
      'date_label': 'Hôm nay',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('invoices', {
      'id': invoiceId,
      'appointment_id': appointmentId,
      'customer_id': customerId,
      'subtotal': 300000,
      'discount_amount': 0,
      'total_amount': 300000,
      'payment_method': 'Tiền mặt',
      'paid_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('invoice_items', {
      'id': itemId,
      'invoice_id': invoiceId,
      'item_type': 'service',
      'service_id': serviceId,
      'product_id': null,
      'employee_id': employeeId,
      'title': 'Nhuộm tóc hồ sơ',
      'quantity': 2,
      'unit_price': 150000,
      'discount_amount': 0,
      'total_price': 300000,
    });

    final profile = await repository.fetchEmployeeProfile(employeeId);

    expect(profile['todayAppointmentCount'], 1);
    expect(profile['monthRevenueValue'], 300000);
    expect(profile['monthServiceCount'], 2);
    expect(profile['monthCustomerCount'], 1);
    expect(profile['estimatedCommissionValue'], 45000);

    final todayAppointments =
        (profile['todayAppointments'] as List).cast<Map<String, Object?>>();
    expect(todayAppointments.single['customerName'], 'Khách Hồ Sơ NV');
    expect(todayAppointments.single['serviceName'], 'Nhuộm tóc hồ sơ');

    final history = (profile['serviceHistory'] as List)
        .cast<Map<String, Object?>>();
    expect(history.single['customerName'], 'Khách Hồ Sơ NV');
    expect(history.single['totalPrice'], 300000);

    final topServices =
        (profile['topServices'] as List).cast<Map<String, Object?>>();
    expect(topServices.single['title'], 'Nhuộm tóc hồ sơ');
    expect(topServices.single['quantity'], 2);

    // Legacy manually entered metrics must not drive the V2 profile.
    expect(profile['monthServiceCount'], isNot(99));
    expect(profile['monthRevenue'], isNot('99.000.000đ'));
  });
}
