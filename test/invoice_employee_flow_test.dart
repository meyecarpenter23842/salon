import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/reports_period.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_reports_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final databaseDirectory = Directory(
    path.join(Directory.current.path, '.salon_manager'),
  );

  setUp(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {
      // On Windows, DB file may still be locked — setUp will retry.
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('prefillDraftFromAppointment gán đúng employee_id vào lines và checkout '
      'lưu employee_id vào invoice_items đã thanh toán', () async {
    const fakeDataSource = FakeSalonDataSource();
    final invoicesRepository = SqliteInvoicesRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );

    final db = await SalonDatabase.instance.database;
    final now = DateTime.now();

    const customerId = 'cust-ef-01';
    const employeeId = 'emp-ef-01';
    const serviceId = 'svc-ef-01';
    const appointmentId = 'apt-ef-01';
    const servicePrice = 150000;

    await db.insert('customers', {
      'id': customerId,
      'full_name': 'Khách test',
      'phone': '0900000001',
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

    await db.insert('employees', {
      'id': employeeId,
      'full_name': 'NV Test',
      'initials': 'NT',
      'role': 'Stylist',
      'status': 'Đang làm việc',
      'phone': '0900000002',
      'email': null,
      'shift_label': '',
      'specialty': '',
      'commission_rate': 0,
      'commission_label': '',
      'today_schedule': '',
      'services_done': 0,
      'monthly_revenue_label': '',
      'rating_label': '5.0',
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert('services', {
      'id': serviceId,
      'name': 'Gội Test',
      'category': 'Chăm sóc',
      'duration_minutes': 60,
      'price': servicePrice,
      'description': '',
      'is_active': 1,
      'popularity_label': 'Ổn định',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert('appointments', {
      'id': appointmentId,
      'customer_id': customerId,
      'service_id': serviceId,
      'employee_id': employeeId,
      'starts_at': now.toIso8601String(),
      'status': 'Chờ xác nhận',
      'note': '',
      'total_amount': servicePrice,
      'customer_name': 'Khách test',
      'customer_phone': '0900000001',
      'service_name': 'Gội Test',
      'staff_name': 'NV Test',
      'duration_minutes': 60,
      'slot_label': 'Ghế 1',
      'date_label': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final appointment = AppointmentEntry(
      id: appointmentId,
      customerId: customerId,
      serviceId: serviceId,
      employeeId: employeeId,
      customerName: 'Khách test',
      customerPhone: '0900000001',
      serviceName: 'Gội Test',
      staffName: 'NV Test',
      status: 'Chờ xác nhận',
      durationMinutes: 60,
      slotLabel: 'Ghế 1',
      note: '',
      startsAt: now,
      dateLabel: '',
      createdAt: now,
      updatedAt: now,
    );

    // Prefill draft từ appointment — lines phải có đúng employeeId
    final draft = await invoicesRepository.prefillDraftFromAppointment(
      appointment,
    );
    expect(draft.lines, isNotEmpty);
    expect(draft.lines.first.employeeId, employeeId);

    // Checkout — tạo invoice đã thanh toán
    await invoicesRepository.checkoutInvoice();

    // Verify invoice đã thanh toán tồn tại và có paid_at
    final paidInvoices = await db.query(
      'invoices',
      where: "paid_at IS NOT NULL AND id != 'invoice-draft-001'",
      orderBy: 'paid_at DESC',
      limit: 1,
    );
    expect(paidInvoices, isNotEmpty);
    expect(paidInvoices.first['paid_at'], isNotNull);

    // Verify invoice_items có đúng employee_id
    final paidInvoiceId = paidInvoices.first['id'].toString();
    final items = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [paidInvoiceId],
    );
    expect(items, isNotEmpty);
    expect(items.first['employee_id'], employeeId);

    // Verify customer stats được cập nhật sau checkout
    final customers = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    expect(customers, isNotEmpty);
    expect(customers.first['total_spent'] as int, servicePrice);
    expect(customers.first['visit_count'] as int, 1);
    expect(customers.first['loyalty_points'] as int, servicePrice ~/ 10000);
  });

  test('fetchReportsSummary topEmployee trả về nhân viên có doanh thu cao nhất '
      'từ invoice_items đã thanh toán', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );

    final db = await SalonDatabase.instance.database;
    final now = DateTime.now();

    const customerId = 'cust-ef-02';
    const employeeAId = 'emp-ef-a';
    const employeeBId = 'emp-ef-b';
    const serviceId = 'svc-ef-02';

    await db.insert('customers', {
      'id': customerId,
      'full_name': 'Khách report',
      'phone': '0900000003',
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

    for (final entry in [
      (employeeAId, 'NV A Report'),
      (employeeBId, 'NV B Report'),
    ]) {
      await db.insert('employees', {
        'id': entry.$1,
        'full_name': entry.$2,
        'initials': entry.$1.substring(0, 2),
        'role': 'Stylist',
        'status': 'Đang làm việc',
        'phone': '',
        'email': null,
        'shift_label': '',
        'specialty': '',
        'commission_rate': 0,
        'commission_label': '',
        'today_schedule': '',
        'services_done': 0,
        'monthly_revenue_label': '',
        'rating_label': '5.0',
        'notes': '',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    await db.insert('services', {
      'id': serviceId,
      'name': 'Dịch vụ report',
      'category': 'Chăm sóc',
      'duration_minutes': 60,
      'price': 100000,
      'description': '',
      'is_active': 1,
      'popularity_label': 'Ổn định',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    // NV A: 2 invoice × 500k = 1.000k tổng
    // NV B: 1 invoice × 200k = 200k tổng → NV A phải thắng
    for (var i = 0; i < 2; i++) {
      final invId = 'inv-ef-top-$i';
      await db.insert('invoices', {
        'id': invId,
        'appointment_id': null,
        'customer_id': customerId,
        'subtotal': 500000,
        'discount_amount': 0,
        'total_amount': 500000,
        'payment_method': 'Tiền mặt',
        'paid_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('invoice_items', {
        'id': 'item-ef-top-$i',
        'invoice_id': invId,
        'item_type': 'service',
        'service_id': serviceId,
        'product_id': null,
        'employee_id': employeeAId,
        'title': 'Dịch vụ report',
        'quantity': 1,
        'unit_price': 500000,
        'discount_amount': 0,
        'total_price': 500000,
      });
    }

    await db.insert('invoices', {
      'id': 'inv-ef-top-2',
      'appointment_id': null,
      'customer_id': customerId,
      'subtotal': 200000,
      'discount_amount': 0,
      'total_amount': 200000,
      'payment_method': 'Tiền mặt',
      'paid_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('invoice_items', {
      'id': 'item-ef-top-2',
      'invoice_id': 'inv-ef-top-2',
      'item_type': 'service',
      'service_id': serviceId,
      'product_id': null,
      'employee_id': employeeBId,
      'title': 'Dịch vụ report',
      'quantity': 1,
      'unit_price': 200000,
      'discount_amount': 0,
      'total_price': 200000,
    });

    final summary = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.today,
    );
    expect(summary['topEmployee'], 'NV A Report');
  });
}
