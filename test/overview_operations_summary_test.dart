import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_overview_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('overview summarizes today revenue, team, sales and alerts', () async {
    final database = await SalonDatabase.instance.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final createdAt = now.toIso8601String();

    await database.delete('invoice_items');
    await database.delete('invoices');
    await database.delete('appointments');
    await database.delete('employees');
    await database.delete('customers');

    await database.insert('customers', _customerRow('customer-a', 'Khách A', createdAt));
    await database.insert('customers', _customerRow('customer-b', 'Khách B', createdAt));

    await database.insert(
      'employees',
      _employeeRow('employee-a', 'Hương', 'HU', createdAt),
    );
    await database.insert(
      'employees',
      _employeeRow('employee-b', 'Nam', 'NA', createdAt),
    );

    await database.insert(
      'appointments',
      _appointmentRow(
        id: 'appointment-active',
        customerId: 'customer-a',
        employeeId: 'employee-a',
        startsAt: now.subtract(const Duration(minutes: 20)),
        status: 'Đang làm',
        customerName: 'Khách A',
        serviceName: 'Nhuộm tóc',
        staffName: 'Hương',
        createdAt: createdAt,
      ),
    );
    await database.insert(
      'appointments',
      _appointmentRow(
        id: 'appointment-overdue',
        customerId: 'customer-b',
        employeeId: 'employee-b',
        startsAt: now.subtract(const Duration(hours: 1)),
        status: 'Đã đặt',
        customerName: 'Khách B',
        serviceName: 'Cắt tóc',
        staffName: 'Nam',
        createdAt: createdAt,
      ),
    );
    await database.insert(
      'appointments',
      _appointmentRow(
        id: 'appointment-unpaid',
        customerId: 'customer-a',
        employeeId: 'employee-b',
        startsAt: now.subtract(const Duration(hours: 2)),
        status: 'Hoàn thành',
        customerName: 'Khách A',
        serviceName: 'Gội đầu',
        staffName: 'Nam',
        createdAt: createdAt,
      ),
    );

    await database.insert(
      'invoices',
      _invoiceRow(
        id: 'invoice-paid-a',
        customerId: 'customer-a',
        paidAt: today.add(const Duration(hours: 10)),
        subtotal: 800000,
        total: 800000,
        createdAt: createdAt,
      ),
    );
    await database.insert(
      'invoices',
      _invoiceRow(
        id: 'invoice-paid-b',
        customerId: 'customer-b',
        paidAt: today.add(const Duration(hours: 11)),
        subtotal: 400000,
        total: 400000,
        createdAt: createdAt,
      ),
    );
    await database.insert('invoice_items', {
      'id': 'item-service',
      'invoice_id': 'invoice-paid-a',
      'item_type': 'service',
      'service_id': null,
      'product_id': null,
      'employee_id': 'employee-a',
      'title': 'Nhuộm tóc',
      'quantity': 1,
      'unit_price': 800000,
      'discount_amount': 0,
      'total_price': 800000,
    });
    await database.insert('invoice_items', {
      'id': 'item-product',
      'invoice_id': 'invoice-paid-b',
      'item_type': 'product',
      'service_id': null,
      'product_id': null,
      'employee_id': 'employee-b',
      'title': 'Dầu gội',
      'quantity': 2,
      'unit_price': 200000,
      'discount_amount': 0,
      'total_price': 400000,
    });

    final repository = SqliteOverviewRepository(
      SalonDatabase.instance,
      const FakeSalonDataSource(),
    );
    final summary = await repository.fetchOverviewSummary();

    final kpis = _mapList(summary['kpis']);
    expect(kpis.map((item) => item['title']), containsAll([
      'Khách hôm nay',
      'Lịch hôm nay',
      'Doanh thu hôm nay',
      'Bill đã thu',
    ]));
    expect(kpis.firstWhere((item) => item['title'] == 'Khách hôm nay')['value'], '2');
    expect(kpis.firstWhere((item) => item['title'] == 'Lịch hôm nay')['value'], '3');
    expect(kpis.firstWhere((item) => item['title'] == 'Bill đã thu')['value'], '2');
    expect(
      kpis.firstWhere((item) => item['title'] == 'Doanh thu hôm nay')['value']
          .toString(),
      contains('1.200.000'),
    );

    final team = _mapList(summary['teamStatus']);
    expect(team.firstWhere((item) => item['name'] == 'Hương')['state'], 'Đang bận');
    expect(team.firstWhere((item) => item['name'] == 'Nam')['state'], 'Sẵn sàng');

    final topSales = _mapList(summary['topSales']);
    expect(topSales, isNotEmpty);
    expect(topSales.first['title'], 'Nhuộm tóc');
    expect(topSales.first['revenue'], 800000);

    final alerts = _mapList(summary['operationalAlerts']);
    expect(alerts.any((item) => item['title'] == 'Lịch đã quá giờ'), isTrue);
    expect(alerts.any((item) => item['title'] == 'Hoàn thành chưa có bill'), isTrue);
  });
}

Map<String, Object?> _customerRow(String id, String name, String createdAt) {
  return {
    'id': id,
    'full_name': name,
    'phone': '0900000000',
    'email': null,
    'tier': 'Member',
    'loyalty_points': 0,
    'favorite_service': '',
    'last_visit_at': null,
    'hair_profile': '',
    'visit_count': 0,
    'total_spent': 0,
    'notes': '',
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

Map<String, Object?> _employeeRow(
  String id,
  String name,
  String initials,
  String createdAt,
) {
  return {
    'id': id,
    'full_name': name,
    'initials': initials,
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '',
    'email': null,
    'shift_label': 'Ca ngày',
    'specialty': 'Tóc',
    'commission_rate': 0,
    'commission_label': 'KPI cố định',
    'today_schedule': '',
    'services_done': 0,
    'monthly_revenue_label': '',
    'rating_label': '',
    'notes': '',
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

Map<String, Object?> _appointmentRow({
  required String id,
  required String customerId,
  required String employeeId,
  required DateTime startsAt,
  required String status,
  required String customerName,
  required String serviceName,
  required String staffName,
  required String createdAt,
}) {
  return {
    'id': id,
    'customer_id': customerId,
    'service_id': null,
    'employee_id': employeeId,
    'starts_at': startsAt.toIso8601String(),
    'status': status,
    'note': '',
    'total_amount': 0,
    'customer_name': customerName,
    'customer_phone': '0900000000',
    'service_name': serviceName,
    'staff_name': staffName,
    'duration_minutes': 60,
    'slot_label': '',
    'date_label': 'Hôm nay',
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

Map<String, Object?> _invoiceRow({
  required String id,
  required String customerId,
  required DateTime paidAt,
  required int subtotal,
  required int total,
  required String createdAt,
}) {
  return {
    'id': id,
    'appointment_id': null,
    'customer_id': customerId,
    'subtotal': subtotal,
    'discount_amount': 0,
    'total_amount': total,
    'payment_method': 'Tiền mặt',
    'paid_at': paidAt.toIso8601String(),
    'created_at': createdAt,
    'updated_at': createdAt,
  };
}

List<Map<String, Object?>> _mapList(Object? value) {
  return (value as List)
      .cast<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}
