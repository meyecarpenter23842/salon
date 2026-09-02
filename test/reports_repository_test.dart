import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/reports_period.dart';
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
      // On Windows, if the app is running it holds the DB lock — skip deletion.
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
    try {
      if (await databaseDirectory.exists()) {
        await databaseDirectory.delete(recursive: true);
      }
    } catch (_) {
      // On Windows, the SQLite file may still be locked by another test isolate.
      // setUp will retry deletion before the next test.
    }
  });

  test('Hôm nay chỉ lấy invoice hôm nay', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final seed = await _seedReportsDataset();
    final summary = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.today,
    );
    final expected = _expected(seed, ReportsPeriod.today);

    expect(_moneyToInt(summary['revenue'].toString()), expected.revenue);
    expect(summary['invoiceCount'], expected.invoiceCount);
    expect(summary['topService'], expected.topService ?? 'Chưa có dữ liệu');
    expect(summary['topEmployee'], expected.topEmployee ?? 'Chưa có dữ liệu');
    final trend = List<Map<String, Object?>>.from(
      summary['revenueTrend'] as List<Object?>,
    );
    expect(trend.length, 1);
  });

  test('7 ngày chỉ lấy dữ liệu 7 ngày gần nhất', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final seed = await _seedReportsDataset();
    final summary = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.last7Days,
    );
    final expected = _expected(seed, ReportsPeriod.last7Days);

    expect(_moneyToInt(summary['revenue'].toString()), expected.revenue);
    expect(summary['invoiceCount'], expected.invoiceCount);
    expect(summary['topService'], expected.topService ?? 'Chưa có dữ liệu');
    expect(summary['topEmployee'], expected.topEmployee ?? 'Chưa có dữ liệu');
    final trend = List<Map<String, Object?>>.from(
      summary['revenueTrend'] as List<Object?>,
    );
    expect(trend.length, 7);
  });

  test('30 ngày chỉ lấy dữ liệu 30 ngày gần nhất', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final seed = await _seedReportsDataset();
    final summary = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.last30Days,
    );
    final expected = _expected(seed, ReportsPeriod.last30Days);

    expect(_moneyToInt(summary['revenue'].toString()), expected.revenue);
    expect(summary['invoiceCount'], expected.invoiceCount);
    expect(summary['topService'], expected.topService ?? 'Chưa có dữ liệu');
    expect(summary['topEmployee'], expected.topEmployee ?? 'Chưa có dữ liệu');
    final trend = List<Map<String, Object?>>.from(
      summary['revenueTrend'] as List<Object?>,
    );
    expect(trend.length, 30);
  });

  test('Tháng này chỉ lấy dữ liệu từ đầu tháng tới hiện tại', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final seed = await _seedReportsDataset();
    final summary = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.thisMonth,
    );
    final expected = _expected(seed, ReportsPeriod.thisMonth);

    expect(_moneyToInt(summary['revenue'].toString()), expected.revenue);
    expect(summary['invoiceCount'], expected.invoiceCount);
    expect(summary['topService'], expected.topService ?? 'Chưa có dữ liệu');
    expect(summary['topEmployee'], expected.topEmployee ?? 'Chưa có dữ liệu');

    final startMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final totalDays = DateTime.now().difference(startMonth).inDays + 1;
    final trend = List<Map<String, Object?>>.from(
      summary['revenueTrend'] as List<Object?>,
    );
    expect(trend.length, totalDays);
  });

  test('Top service và top employee thay đổi đúng theo period', () async {
    const fakeDataSource = FakeSalonDataSource();
    final reportsRepository = SqliteReportsRepository(
      SalonDatabase.instance,
      fakeDataSource,
    );
    final seed = await _seedReportsDataset();

    final today = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.today,
    );
    final last30 = await reportsRepository.fetchReportsSummary(
      period: ReportsPeriod.last30Days,
    );

    final expectedToday = _expected(seed, ReportsPeriod.today);
    final expectedLast30 = _expected(seed, ReportsPeriod.last30Days);

    expect(today['topService'], expectedToday.topService ?? 'Chưa có dữ liệu');
    expect(
      today['topEmployee'],
      expectedToday.topEmployee ?? 'Chưa có dữ liệu',
    );
    expect(
      last30['topService'],
      expectedLast30.topService ?? 'Chưa có dữ liệu',
    );
    expect(
      last30['topEmployee'],
      expectedLast30.topEmployee ?? 'Chưa có dữ liệu',
    );

    expect(today['topService'], isNot(last30['topService']));
    expect(today['topEmployee'], isNot(last30['topEmployee']));
  });
}

class _InvoiceSeed {
  const _InvoiceSeed({
    required this.paidAt,
    required this.total,
    required this.serviceTitle,
    this.employeeId,
  });

  final DateTime paidAt;
  final int total;
  final String serviceTitle;
  final String? employeeId;
}

class _AppointmentSeed {
  const _AppointmentSeed({
    required this.startsAt,
    required this.total,
    required this.staffName,
  });

  final DateTime startsAt;
  final int total;
  final String staffName;
}

class _SeededReportsData {
  const _SeededReportsData({
    required this.invoices,
    required this.appointments,
  });

  final List<_InvoiceSeed> invoices;
  final List<_AppointmentSeed> appointments;
}

class _ExpectedSummary {
  const _ExpectedSummary({
    required this.revenue,
    required this.invoiceCount,
    required this.topService,
    required this.topEmployee,
  });

  final int revenue;
  final int invoiceCount;
  final String? topService;
  final String? topEmployee;
}

Future<_SeededReportsData> _seedReportsDataset() async {
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();
  final startToday = DateTime(now.year, now.month, now.day);
  final startMonth = DateTime(now.year, now.month, 1);
  final todayAt10 = startToday.add(const Duration(hours: 10));
  final threeDaysAgo = startToday
      .subtract(const Duration(days: 3))
      .add(const Duration(hours: 11));
  final twentyDaysAgo = startToday
      .subtract(const Duration(days: 20))
      .add(const Duration(hours: 9));
  final fortyDaysAgo = startToday
      .subtract(const Duration(days: 40))
      .add(const Duration(hours: 14));
  final thisMonthEarly = startMonth.add(const Duration(hours: 9));
  final lastMonthEnd = startMonth
      .subtract(const Duration(days: 1))
      .add(const Duration(hours: 16));

  await database.insert('customers', {
    'id': 'cust-rpt-01',
    'full_name': 'Khach report',
    'phone': '0900999999',
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

  await database.insert('employees', {
    'id': 'emp-rpt-a',
    'full_name': 'NV A',
    'initials': 'NA',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0900111111',
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

  await database.insert('employees', {
    'id': 'emp-rpt-b',
    'full_name': 'NV B',
    'initials': 'NB',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0900222222',
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

  Future<void> insertService(String id, String name) async {
    await database.insert('services', {
      'id': id,
      'name': name,
      'category': 'Chăm sóc',
      'duration_minutes': 60,
      'price': 100000,
      'description': '',
      'is_active': 1,
      'popularity_label': 'Ổn định',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await insertService('svc-rpt-today', 'Gội hôm nay');
  await insertService('svc-rpt-7d', 'Combo 7 ngày');
  await insertService('svc-rpt-30d', 'Combo 30 ngày');
  await insertService('svc-rpt-month', 'Combo tháng này');
  await insertService('svc-rpt-old', 'Combo ngoài kỳ');
  const invoiceServiceIds = [
    'svc-rpt-today',
    'svc-rpt-7d',
    'svc-rpt-30d',
    'svc-rpt-month',
    'svc-rpt-old',
    'svc-rpt-old',
  ];

  final invoices = <_InvoiceSeed>[
    _InvoiceSeed(
      paidAt: todayAt10,
      total: 100000,
      serviceTitle: 'Gội hôm nay',
      employeeId: 'emp-rpt-b',
    ),
    _InvoiceSeed(
      paidAt: threeDaysAgo,
      total: 250000,
      serviceTitle: 'Combo 7 ngày',
      employeeId: 'emp-rpt-a',
    ),
    _InvoiceSeed(
      paidAt: twentyDaysAgo,
      total: 400000,
      serviceTitle: 'Combo 30 ngày',
      employeeId: 'emp-rpt-a',
    ),
    _InvoiceSeed(
      paidAt: thisMonthEarly,
      total: 180000,
      serviceTitle: 'Combo tháng này',
      employeeId: 'emp-rpt-a',
    ),
    _InvoiceSeed(
      paidAt: fortyDaysAgo,
      total: 900000,
      serviceTitle: 'Combo ngoài kỳ',
    ),
    _InvoiceSeed(
      paidAt: lastMonthEnd,
      total: 700000,
      serviceTitle: 'Combo ngoài kỳ',
    ),
  ];

  for (var index = 0; index < invoices.length; index++) {
    final item = invoices[index];
    final invoiceId = 'inv-rpt-$index';
    await database.insert('invoices', {
      'id': invoiceId,
      'appointment_id': null,
      'customer_id': 'cust-rpt-01',
      'subtotal': item.total,
      'discount_amount': 0,
      'total_amount': item.total,
      'payment_method': 'Tiền mặt',
      'paid_at': item.paidAt.toIso8601String(),
      'created_at': item.paidAt.toIso8601String(),
      'updated_at': item.paidAt.toIso8601String(),
    });
    await database.insert('invoice_items', {
      'id': 'inv-item-rpt-$index',
      'invoice_id': invoiceId,
      'item_type': 'service',
      'service_id': invoiceServiceIds[index],
      'product_id': null,
      'employee_id': item.employeeId,
      'title': item.serviceTitle,
      'quantity': 1,
      'unit_price': item.total,
      'discount_amount': 0,
      'total_price': item.total,
    });
  }

  final appointments = <_AppointmentSeed>[
    _AppointmentSeed(startsAt: todayAt10, total: 150000, staffName: 'NV A'),
    _AppointmentSeed(startsAt: threeDaysAgo, total: 500000, staffName: 'NV B'),
    _AppointmentSeed(startsAt: twentyDaysAgo, total: 200000, staffName: 'NV A'),
    _AppointmentSeed(
      startsAt: thisMonthEarly,
      total: 300000,
      staffName: 'NV B',
    ),
    _AppointmentSeed(startsAt: fortyDaysAgo, total: 950000, staffName: 'NV A'),
    _AppointmentSeed(startsAt: lastMonthEnd, total: 800000, staffName: 'NV B'),
  ];

  for (var index = 0; index < appointments.length; index++) {
    final item = appointments[index];
    final employeeId = item.staffName == 'NV A' ? 'emp-rpt-a' : 'emp-rpt-b';
    await database.insert('appointments', {
      'id': 'apt-rpt-$index',
      'customer_id': 'cust-rpt-01',
      'service_id': 'svc-rpt-today',
      'employee_id': employeeId,
      'starts_at': item.startsAt.toIso8601String(),
      'status': 'Hoàn thành',
      'note': '',
      'total_amount': item.total,
      'customer_name': 'Khach report',
      'customer_phone': '0900999999',
      'service_name': 'Report service',
      'staff_name': item.staffName,
      'duration_minutes': 60,
      'slot_label': 'Ghe',
      'date_label': '',
      'created_at': item.startsAt.toIso8601String(),
      'updated_at': item.startsAt.toIso8601String(),
    });
  }

  return _SeededReportsData(invoices: invoices, appointments: appointments);
}

_ExpectedSummary _expected(_SeededReportsData data, ReportsPeriod period) {
  final range = _range(period);
  final invoicesInRange = data.invoices
      .where(
        (item) =>
            !item.paidAt.isBefore(range.start) &&
            item.paidAt.isBefore(range.end),
      )
      .toList(growable: false);

  final revenue = invoicesInRange.fold<int>(0, (sum, item) => sum + item.total);
  final invoiceCount = invoicesInRange.length;

  final serviceTotals = <String, int>{};
  for (final item in invoicesInRange) {
    serviceTotals[item.serviceTitle] =
        (serviceTotals[item.serviceTitle] ?? 0) + item.total;
  }
  String? topService;
  if (serviceTotals.isNotEmpty) {
    final sorted = serviceTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    topService = sorted.first.key;
  }

  String? employeeName(String? id) => switch (id) {
    'emp-rpt-a' => 'NV A',
    'emp-rpt-b' => 'NV B',
    _ => null,
  };
  final employeeTotals = <String, int>{};
  for (final item in invoicesInRange) {
    final name = employeeName(item.employeeId);
    if (name == null) continue;
    employeeTotals[name] = (employeeTotals[name] ?? 0) + item.total;
  }
  String? topEmployee;
  if (employeeTotals.isNotEmpty) {
    final sorted = employeeTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    topEmployee = sorted.first.key;
  }

  return _ExpectedSummary(
    revenue: revenue,
    invoiceCount: invoiceCount,
    topService: topService,
    topEmployee: topEmployee,
  );
}

({DateTime start, DateTime end}) _range(ReportsPeriod period) {
  final now = DateTime.now();
  final startToday = DateTime(now.year, now.month, now.day);
  switch (period) {
    case ReportsPeriod.today:
      return (start: startToday, end: startToday.add(const Duration(days: 1)));
    case ReportsPeriod.last7Days:
      return (
        start: startToday.subtract(const Duration(days: 6)),
        end: startToday.add(const Duration(days: 1)),
      );
    case ReportsPeriod.last30Days:
      return (
        start: startToday.subtract(const Duration(days: 29)),
        end: startToday.add(const Duration(days: 1)),
      );
    case ReportsPeriod.thisMonth:
      return (
        start: DateTime(now.year, now.month, 1),
        end: startToday.add(const Duration(days: 1)),
      );
  }
}

int _moneyToInt(String label) {
  final digits = label.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}
