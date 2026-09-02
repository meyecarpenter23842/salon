import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import 'appointment_mapper.dart';
import 'appointment_service_mapper.dart';
import 'customer_mapper.dart';
import 'invoice_draft_mapper.dart';
import 'service_mapper.dart';
import '../models/appointment_service_line.dart';

class SalonDatabaseSeed {
  SalonDatabaseSeed(this._dataSource);

  final FakeSalonDataSource _dataSource;

  Future<void> seedCustomersIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM customers'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    final seedCustomers = await _dataSource.fetchCustomersView();
    final batch = database.batch();

    for (final item in seedCustomers) {
      final customer = CustomerMapper.fromLegacyView(item);
      batch.insert(
        'customers',
        CustomerMapper.toDatabase(customer),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> seedEmployeesIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM employees'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    final items = await _dataSource.fetchEmployeesView();
    final batch = database.batch();

    for (final item in items) {
      batch.insert(
        'employees',
        _buildEmployeeSeed(item),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> seedAppointmentsIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM appointments'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    await seedCustomersIfNeeded(database);
    await seedServicesIfNeeded(database);
    await seedEmployeesIfNeeded(database);

    final items = await _dataSource.fetchAppointmentsView();
    final batch = database.batch();

    for (final item in items) {
      final customerId = CustomerMapper.buildIdFromIdentity(
        fullName: item['customer']?.toString() ?? '',
        phone: item['phone']?.toString() ?? '',
      );
      final existingCustomer = await database.query(
        'customers',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (existingCustomer.isEmpty) {
        batch.insert(
          'customers',
          _buildCustomerSeedFromAppointment(item),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    for (final item in items) {
      final appointment = AppointmentMapper.fromLegacyView(item).copyWith(
        serviceId: await _findServiceIdByTitle(
          database,
          item['service'].toString(),
        ),
        employeeId: await _findEmployeeIdByName(
          database,
          item['staff'].toString(),
        ),
      );
      batch.insert(
        'appointments',
        AppointmentMapper.toDatabase(appointment),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final primaryService = await _findServiceByTitle(
        database,
        item['service'].toString(),
      );
      if (primaryService != null) {
        batch.insert(
          'appointment_services',
          AppointmentServiceMapper.toDatabase(
            _buildAppointmentServiceSeed(
              appointmentId: appointment.id,
              service: primaryService,
              lineId: 'aptsvc-${appointment.id}-0',
            ),
          ),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    await batch.commit(noResult: true);
  }

  Map<String, Object?> _buildCustomerSeedFromAppointment(
    Map<String, Object?> item,
  ) {
    final now = DateTime.now().toIso8601String();
    return {
      'id': CustomerMapper.buildIdFromIdentity(
        fullName: item['customer']?.toString() ?? '',
        phone: item['phone']?.toString() ?? '',
      ),
      'full_name': item['customer']?.toString() ?? 'Khách mới',
      'phone': item['phone']?.toString() ?? '',
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': item['service']?.toString() ?? '',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': item['note']?.toString() ?? '',
      'created_at': now,
      'updated_at': now,
    };
  }

  Future<void> seedServicesIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM services'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    final items = await _dataSource.fetchServicesView();
    final batch = database.batch();

    for (final item in items) {
      final service = ServiceMapper.fromLegacyView(item);
      batch.insert(
        'services',
        ServiceMapper.toDatabase(service),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> seedInvoiceDraftIfNeeded(Database database) async {
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM invoice_items'),
        ) ??
        0;

    if (count > 0) {
      return;
    }

    await seedCustomersIfNeeded(database);
    await seedServicesIfNeeded(database);

    const invoiceId = 'invoice-draft-001';
    final items = await _dataSource.fetchInvoiceDraftView();
    final subtotal = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          ((item['unitPrice'] as int?) ?? 0) *
              ((item['quantity'] as int?) ?? 1),
    );
    final firstItem = items.first;
    final customerId = CustomerMapper.buildIdFromIdentity(
      fullName: firstItem['customerName'].toString(),
      phone: firstItem['customerPhone'].toString(),
    );
    final now = DateTime.now().toIso8601String();
    final existingCustomer = await database.query(
      'customers',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    final batch = database.batch();
    if (existingCustomer.isEmpty) {
      batch.insert('customers', {
        'id': customerId,
        'full_name': firstItem['customerName']?.toString() ?? 'Khách vãng lai',
        'phone': firstItem['customerPhone']?.toString() ?? '',
        'email': null,
        'tier': 'Member',
        'loyalty_points': 0,
        'favorite_service': firstItem['label']?.toString() ?? '',
        'last_visit_at': null,
        'hair_profile': '',
        'visit_count': 0,
        'total_spent': 0,
        'notes': 'Tự tạo từ draft hóa đơn seed.',
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    batch.insert('invoices', {
      'id': invoiceId,
      'appointment_id': null,
      'customer_id': customerId,
      'subtotal': subtotal,
      'discount_amount': 0,
      'total_amount': subtotal,
      'payment_method': 'Tiền mặt',
      'paid_at': null,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final item in items) {
      final line = InvoiceDraftMapper.fromLegacyView(item, invoiceId: invoiceId)
          .copyWith(
            serviceId: await _findServiceIdByTitle(
              database,
              item['label'].toString(),
            ),
          );
      batch.insert(
        'invoice_items',
        InvoiceDraftMapper.toDatabase(line),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<String?> _findServiceIdByTitle(Database database, String title) async {
    final service = await _findServiceByTitle(database, title);
    return service?['id']?.toString();
  }

  Future<Map<String, Object?>?> _findServiceByTitle(
    Database database,
    String title,
  ) async {
    final rows = await database.query(
      'services',
      columns: const ['id', 'name', 'price', 'duration_minutes'],
      where: 'LOWER(name) = ?',
      whereArgs: [title.toLowerCase()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<String?> _findEmployeeIdByName(Database database, String name) async {
    final rows = await database.query(
      'employees',
      columns: const ['id'],
      where: 'LOWER(full_name) = ?',
      whereArgs: [name.toLowerCase()],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['id']?.toString();
  }

  Map<String, Object?> _buildEmployeeSeed(Map<String, Object?> item) {
    final now = DateTime.now().toIso8601String();
    final commissionRaw =
        item['commission']?.toString().replaceAll('%', '').trim() ?? '0';
    final commissionRate = (double.tryParse(commissionRaw) ?? 0) / 100;

    return {
      'id': item['id']?.toString() ?? '',
      'full_name': item['name']?.toString() ?? 'Nhân sự',
      'initials':
          item['initials']?.toString() ??
          _buildInitials(item['name']?.toString() ?? 'Nhân sự'),
      'role': item['role']?.toString() ?? '',
      'status': item['status']?.toString() ?? 'Đang làm việc',
      'phone': item['phone']?.toString(),
      'email': null,
      'shift_label': item['shift']?.toString() ?? '',
      'specialty': item['specialty']?.toString() ?? '',
      'commission_rate': commissionRate,
      'commission_label': item['commission']?.toString() ?? 'KPI cố định',
      'today_schedule': item['todaySchedule']?.toString() ?? '',
      'services_done': _toInt(item['servicesDone']),
      'monthly_revenue_label': item['monthlyRevenue']?.toString() ?? '',
      'rating_label': item['rating']?.toString() ?? '',
      'notes': item['note']?.toString() ?? '',
      'created_at': now,
      'updated_at': now,
    };
  }

  String _buildInitials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'NS';
    }

    if (parts.length == 1) {
      final name = parts.first;
      return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  AppointmentServiceLine _buildAppointmentServiceSeed({
    required String appointmentId,
    required Map<String, Object?> service,
    required String lineId,
  }) {
    return AppointmentServiceLine(
      id: lineId,
      appointmentId: appointmentId,
      serviceId: service['id']!.toString(),
      title: service['name']!.toString(),
      quantity: 1,
      unitPrice: _toInt(service['price']),
      durationMinutes: _toInt(service['duration_minutes']),
    );
  }
}
