import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_upsert_input.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseDirectory = Directory(
    path.join(Directory.current.path, '.salon_manager'),
  );

  setUp(() async {
    await SalonDatabase.instance.close();
    if (await databaseDirectory.exists()) {
      try {
        await databaseDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    if (await databaseDirectory.exists()) {
      try {
        await databaseDirectory.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('walk-in service keeps selected employee attribution through checkout',
      () async {
    const fake = FakeSalonDataSource();
    final invoices = GuardedInvoicesRepository(
      SalonDatabase.instance,
      SqliteInvoicesRepository(SalonDatabase.instance, fake),
    );
    final employees = SqliteEmployeesRepository(SalonDatabase.instance, fake);
    final db = await SalonDatabase.instance.database;
    final now = DateTime.now();

    await _insertCustomer(db, now, id: 'cust-walkin');
    await _insertEmployee(
      db,
      now,
      id: 'emp-walkin',
      name: 'NV Walk-in',
      status: 'Đang làm việc',
      commissionRate: 0.1,
    );
    await _insertService(
      db,
      now,
      id: 'svc-walkin',
      name: 'Gội Walk-in',
      price: 240000,
      duration: 45,
    );

    await invoices.selectInvoiceCustomer('cust-walkin');
    final draft = await invoices.addInvoiceService(
      'svc-walkin',
      employeeId: 'emp-walkin',
    );
    expect(draft.lines.single.employeeId, 'emp-walkin');

    await invoices.checkoutInvoice();

    final paidItems = await db.query(
      'invoice_items',
      where: "invoice_id != 'invoice-draft-001' AND item_type = 'service'",
    );
    expect(paidItems, hasLength(1));
    expect(paidItems.single['employee_id'], 'emp-walkin');

    final profile = await employees.fetchEmployeeProfile('emp-walkin');
    expect(profile['monthRevenueValue'], 240000);
    expect(profile['monthServiceCount'], 1);
    expect(profile['estimatedCommissionValue'], 24000);
  });

  test('inactive employee cannot receive active appointment and duration follows services',
      () async {
    const fake = FakeSalonDataSource();
    final appointments = GuardedAppointmentsRepository(
      SalonDatabase.instance,
      SqliteAppointmentsRepository(SalonDatabase.instance, fake),
    );
    final db = await SalonDatabase.instance.database;
    final now = DateTime.now();

    await _insertCustomer(db, now, id: 'cust-apt');
    await _insertEmployee(
      db,
      now,
      id: 'emp-rest',
      name: 'NV Tạm nghỉ',
      status: 'Tạm nghỉ',
    );
    await _insertService(
      db,
      now,
      id: 'svc-apt',
      name: 'Dịch vụ 75 phút',
      price: 300000,
      duration: 75,
    );

    final input = AppointmentUpsertInput(
      customerId: 'cust-apt',
      serviceIds: const ['svc-apt'],
      employeeId: 'emp-rest',
      customerName: 'Khách test',
      customerPhone: '0900000099',
      serviceName: 'Dịch vụ 75 phút',
      staffName: 'NV Tạm nghỉ',
      status: 'Đã đặt',
      durationMinutes: 5,
      slotLabel: 'Ghế 1',
      note: '',
      dayLabel: 'Ngày mai',
      timeLabel: '09:00',
    );

    await expectLater(
      appointments.saveAppointment(input),
      throwsA(isA<StateError>()),
    );

    await db.update(
      'employees',
      {'status': 'Đang làm việc', 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: const ['emp-rest'],
    );

    final saved = await appointments.saveAppointment(input);
    expect(saved.durationMinutes, 75);
  });

  test('cancelled appointments are absent from employee upcoming list', () async {
    const fake = FakeSalonDataSource();
    final employees = SqliteEmployeesRepository(SalonDatabase.instance, fake);
    final db = await SalonDatabase.instance.database;
    final now = DateTime.now();
    final future = now.add(const Duration(hours: 4));

    await _insertCustomer(db, now, id: 'cust-cancel');
    await _insertEmployee(
      db,
      now,
      id: 'emp-cancel',
      name: 'NV Cancel',
      status: 'Đang làm việc',
    );
    await _insertService(
      db,
      now,
      id: 'svc-cancel',
      name: 'Dịch vụ cancel',
      price: 100000,
      duration: 30,
    );
    await db.insert('appointments', {
      'id': 'apt-cancel',
      'customer_id': 'cust-cancel',
      'service_id': 'svc-cancel',
      'employee_id': 'emp-cancel',
      'starts_at': future.toIso8601String(),
      'status': 'Đã hủy',
      'note': '',
      'total_amount': 100000,
      'customer_name': 'Khách test',
      'customer_phone': '0900000099',
      'service_name': 'Dịch vụ cancel',
      'staff_name': 'NV Cancel',
      'duration_minutes': 30,
      'slot_label': 'Ghế 1',
      'date_label': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final profile = await employees.fetchEmployeeProfile('emp-cancel');
    expect(profile['upcomingAppointments'], isEmpty);
    expect(profile['nextAppointmentLabel'], 'Chưa có lịch sắp tới');
  });
}

Future<void> _insertCustomer(
  dynamic db,
  DateTime now, {
  required String id,
}) {
  return db.insert('customers', {
    'id': id,
    'full_name': 'Khách test',
    'phone': '0900000099',
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

Future<void> _insertEmployee(
  dynamic db,
  DateTime now, {
  required String id,
  required String name,
  required String status,
  double commissionRate = 0,
}) {
  return db.insert('employees', {
    'id': id,
    'full_name': name,
    'initials': 'NV',
    'role': 'Stylist',
    'status': status,
    'phone': '',
    'email': null,
    'shift_label': '',
    'specialty': '',
    'commission_rate': commissionRate,
    'commission_label': '${(commissionRate * 100).round()}%',
    'today_schedule': '',
    'services_done': 0,
    'monthly_revenue_label': '',
    'rating_label': '5.0',
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}

Future<void> _insertService(
  dynamic db,
  DateTime now, {
  required String id,
  required String name,
  required int price,
  required int duration,
}) {
  return db.insert('services', {
    'id': id,
    'name': name,
    'category': 'Chăm sóc',
    'duration_minutes': duration,
    'price': price,
    'description': '',
    'is_active': 1,
    'popularity_label': 'Ổn định',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
