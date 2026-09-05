import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/reports_period.dart';
import 'package:salonmanager/core/repositories/guarded_salon_repositories.dart';
import 'package:salonmanager/core/repositories/reporting_overview_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_overview_repository.dart';
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
    } catch (_) {}
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('Issue #45 keeps reporting semantics on one net-revenue basis', () async {
    const fakeDataSource = FakeSalonDataSource();
    await _seedIssue45Dataset();

    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final today = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.today,
    );

    expect(today['completionRate'], '50%');
    expect(today['fillRate'], '50%');

    final servicePerformance = _mapList(today['servicePerformance']);
    expect(servicePerformance, hasLength(2));
    final serviceRevenue = servicePerformance.fold<int>(
      0,
      (sum, row) => sum + _moneyToInt(row['revenue']?.toString() ?? ''),
    );
    expect(serviceRevenue, 89999);
    expect(
      servicePerformance
          .map((row) => row['share']?.toString())
          .toSet(),
      {'60%', '40%'},
    );

    final employeePerformance = _mapList(today['employeePerformance']);
    final employeeA = employeePerformance.firstWhere(
      (row) => row['name'] == 'NV Net A',
    );
    expect(_moneyToInt(employeeA['revenue']?.toString() ?? ''), 53999);
    expect(employeeA['rating'], 'Chưa có đánh giá');

    final employeeRepository = SqliteEmployeesRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final profileA = await employeeRepository.fetchEmployeeProfile(
      'emp-net-a',
    );
    expect(profileA['monthRevenueValue'], 53999);
    expect(profileA['estimatedCommissionValue'], 5400);

    final overviewRepository = ReportingOverviewRepository(
      SalonDatabase.instance,
      GuardedOverviewRepository(
        SalonDatabase.instance,
        SqliteOverviewRepository(SalonDatabase.instance, fakeDataSource),
      ),
    );
    final overview = await overviewRepository.fetchOverviewSummary();
    expect(_kpiValue(overview, 'Lịch hôm nay'), '3');
    expect(_kpiValue(overview, 'Khách hôm nay'), '2');

    final nextAppointment = Map<String, Object?>.from(
      overview['nextAppointment'] as Map,
    );
    expect(nextAppointment['customer'], 'Khách Active B');

    final topSales = _mapList(overview['topSales']);
    expect(
      topSales.fold<int>(
        0,
        (sum, row) => sum + ((row['revenue'] as num?)?.toInt() ?? 0),
      ),
      89999,
    );
  });

  test('Issue #45 insights use the selected report period', () async {
    const fakeDataSource = FakeSalonDataSource();
    await _seedIssue45Dataset();
    final repository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );

    final today = await repository.fetchReportsSummary(
      period: ReportsPeriod.today,
    );
    final last30 = await repository.fetchReportsSummary(
      period: ReportsPeriod.last30Days,
    );

    final todayInsights = _stringList(today['insights']).join(' ');
    final last30Insights = _stringList(last30['insights']).join(' ');
    expect(todayInsights, contains('hôm nay'));
    expect(todayInsights, isNot(contains('tuần')));
    expect(last30Insights, contains('30 ngày qua'));
    expect(last30Insights, isNot(contains('tuần')));
  });
}

Future<void> _seedIssue45Dataset() async {
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();
  final startToday = DateTime(now.year, now.month, now.day);

  Future<void> insertCustomer(String id, String name, String phone) async {
    await database.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': phone,
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

  await insertCustomer('cust-net-a', 'Khách Active A', '0900100001');
  await insertCustomer('cust-net-b', 'Khách Active B', '0900100002');
  await insertCustomer('cust-net-c', 'Khách Cancelled', '0900100003');

  Future<void> insertEmployee({
    required String id,
    required String name,
    required String phone,
    required double commissionRate,
    required String commissionLabel,
    required String rating,
  }) async {
    await database.insert('employees', {
      'id': id,
      'full_name': name,
      'initials': name == 'NV Net A' ? 'NA' : 'NB',
      'role': 'Stylist',
      'status': 'Đang làm việc',
      'phone': phone,
      'email': null,
      'shift_label': '',
      'specialty': '',
      'commission_rate': commissionRate,
      'commission_label': commissionLabel,
      'today_schedule': '',
      'services_done': 0,
      'monthly_revenue_label': '',
      'rating_label': rating,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await insertEmployee(
    id: 'emp-net-a',
    name: 'NV Net A',
    phone: '0900200001',
    commissionRate: 0.10,
    commissionLabel: '10%',
    rating: '',
  );
  await insertEmployee(
    id: 'emp-net-b',
    name: 'NV Net B',
    phone: '0900200002',
    commissionRate: 0.05,
    commissionLabel: '5%',
    rating: '4.8',
  );

  Future<void> insertService(String id, String name, int price) async {
    await database.insert('services', {
      'id': id,
      'name': name,
      'category': 'Chăm sóc',
      'duration_minutes': 60,
      'price': price,
      'description': '',
      'is_active': 1,
      'popularity_label': 'Ổn định',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await insertService('svc-net-a', 'Dịch vụ Net A', 60000);
  await insertService('svc-net-b', 'Dịch vụ Net B', 40000);

  await database.insert('invoices', {
    'id': 'inv-net-1',
    'appointment_id': null,
    'customer_id': 'cust-net-a',
    'subtotal': 100000,
    'discount_amount': 10001,
    'total_amount': 89999,
    'payment_method': 'Tiền mặt',
    'paid_at': startToday.toIso8601String(),
    'created_at': startToday.toIso8601String(),
    'updated_at': startToday.toIso8601String(),
  });
  await database.insert('invoice_items', {
    'id': 'line-net-a',
    'invoice_id': 'inv-net-1',
    'item_type': 'service',
    'service_id': 'svc-net-a',
    'product_id': null,
    'employee_id': 'emp-net-a',
    'title': 'Dịch vụ Net A',
    'quantity': 1,
    'unit_price': 60000,
    'discount_amount': 0,
    'total_price': 60000,
  });
  await database.insert('invoice_items', {
    'id': 'line-net-b',
    'invoice_id': 'inv-net-1',
    'item_type': 'service',
    'service_id': 'svc-net-b',
    'product_id': null,
    'employee_id': 'emp-net-b',
    'title': 'Dịch vụ Net B',
    'quantity': 1,
    'unit_price': 40000,
    'discount_amount': 0,
    'total_price': 40000,
  });

  Future<void> insertAppointment({
    required String id,
    required String customerId,
    required String customerName,
    required String serviceId,
    required String serviceName,
    required String employeeId,
    required String employeeName,
    required DateTime startsAt,
    required String status,
  }) async {
    await database.insert('appointments', {
      'id': id,
      'customer_id': customerId,
      'service_id': serviceId,
      'employee_id': employeeId,
      'starts_at': startsAt.toIso8601String(),
      'status': status,
      'note': '',
      'total_amount': 60000,
      'customer_name': customerName,
      'customer_phone': '0900000000',
      'service_name': serviceName,
      'staff_name': employeeName,
      'duration_minutes': 60,
      'slot_label': 'Ghế 1',
      'date_label': '',
      'created_at': startsAt.toIso8601String(),
      'updated_at': startsAt.toIso8601String(),
    });
  }

  await insertAppointment(
    id: 'apt-net-completed',
    customerId: 'cust-net-a',
    customerName: 'Khách Active A',
    serviceId: 'svc-net-a',
    serviceName: 'Dịch vụ Net A',
    employeeId: 'emp-net-a',
    employeeName: 'NV Net A',
    startsAt: startToday,
    status: 'Hoàn thành',
  );
  await insertAppointment(
    id: 'apt-net-pending',
    customerId: 'cust-net-b',
    customerName: 'Khách Active B',
    serviceId: 'svc-net-b',
    serviceName: 'Dịch vụ Net B',
    employeeId: 'emp-net-b',
    employeeName: 'NV Net B',
    startsAt: startToday,
    status: 'Đã đặt',
  );
  await insertAppointment(
    id: 'apt-net-cancelled-future',
    customerId: 'cust-net-c',
    customerName: 'Khách Cancelled',
    serviceId: 'svc-net-a',
    serviceName: 'Dịch vụ Net A',
    employeeId: 'emp-net-a',
    employeeName: 'NV Net A',
    startsAt: now.add(const Duration(minutes: 10)),
    status: 'Đã hủy',
  );
  await insertAppointment(
    id: 'apt-net-active-future',
    customerId: 'cust-net-b',
    customerName: 'Khách Active B',
    serviceId: 'svc-net-a',
    serviceName: 'Dịch vụ Net A',
    employeeId: 'emp-net-a',
    employeeName: 'NV Net A',
    startsAt: now.add(const Duration(minutes: 20)),
    status: 'Đã đặt',
  );
}

List<Map<String, Object?>> _mapList(Object? source) {
  if (source is! List) return const [];
  return source
      .whereType<Map>()
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
}

List<String> _stringList(Object? source) {
  if (source is! List) return const [];
  return source.map((item) => item.toString()).toList(growable: false);
}

String? _kpiValue(Map<String, Object?> overview, String title) {
  final kpis = _mapList(overview['kpis']);
  return kpis.firstWhere((row) => row['title'] == title)['value']?.toString();
}

int _moneyToInt(String label) {
  final digits = label.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}
