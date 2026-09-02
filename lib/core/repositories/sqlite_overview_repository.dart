import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import 'repository_contracts.dart';

class SqliteOverviewRepository implements OverviewRepository {
  SqliteOverviewRepository(this._database, FakeSalonDataSource dataSource)
    : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );

  @override
  Future<Map<String, Object?>> fetchOverviewSummary() async {
    final database = await _database.database;
    await _seed.seedCustomersIfNeeded(database);
    await _seed.seedServicesIfNeeded(database);
    await _seed.seedEmployeesIfNeeded(database);
    await _seed.seedAppointmentsIfNeeded(database);
    await _seed.seedInvoiceDraftIfNeeded(database);

    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final startYesterday = startToday.subtract(const Duration(days: 1));
    final startThisMonth = DateTime(now.year, now.month);

    final appointmentsToday = await _countAppointments(
      database,
      startToday,
      startTomorrow,
    );
    final appointmentsYesterday = await _countAppointments(
      database,
      startYesterday,
      startToday,
    );
    final completedToday = await _countAppointments(
      database,
      startToday,
      startTomorrow,
      status: 'Hoàn thành',
    );
    final completedYesterday = await _countAppointments(
      database,
      startYesterday,
      startToday,
      status: 'Hoàn thành',
    );
    final revenueToday = await _sumRevenue(database, startToday, startTomorrow);
    final revenueYesterday = await _sumRevenue(
      database,
      startYesterday,
      startToday,
    );
    final nextAppointment = await _findNextAppointment(database, now);
    final featuredCustomers = await _buildFeaturedCustomers(
      database,
      now,
      startThisMonth,
    );
    final quickCheckout = await _buildQuickCheckoutSummary(database);
    final revenueSeries = await _buildRevenueSeries(database, startToday);

    final nextSlotValue = nextAppointment == null
        ? 'Chưa có lịch tiếp theo'
        : '${_timeLabel(_parseDateTime(nextAppointment['starts_at']))} - ${nextAppointment['customer_name'] ?? 'Khách'}';
    final nextSlotNote = nextAppointment == null
        ? 'Ca hiện tại chưa có lịch cần ưu tiên.'
        : (nextAppointment['service_name']?.toString().trim().isNotEmpty ??
              false)
        ? nextAppointment['service_name'].toString()
        : 'Đang chờ xác nhận dịch vụ';

    return {
      'kpis': [
        {
          'title': 'Khách đặt lịch',
          'value': appointmentsToday.toString(),
          'note': _deltaLabel(
            appointmentsToday,
            appointmentsYesterday,
            unit: 'lịch',
          ),
        },
        {
          'title': 'Khách đã làm',
          'value': completedToday.toString(),
          'note': _deltaLabel(completedToday, completedYesterday, unit: 'lịch'),
        },
        {
          'title': 'Doanh thu hôm nay',
          'value': _currency(revenueToday),
          'note': _deltaLabel(
            revenueToday,
            revenueYesterday,
            unit: 'đ',
            currency: true,
          ),
        },
        {
          'title': 'Lịch tiếp theo',
          'value': nextSlotValue,
          'note': nextSlotNote,
        },
      ],
      'featuredCustomers': featuredCustomers,
      'quickCheckoutLines': quickCheckout['lines'],
      'quickCheckoutCustomer': quickCheckout['customerName'],
      'quickCheckoutDiscount': quickCheckout['discount'],
      'quickCheckoutPaymentNote': quickCheckout['paymentNote'],
      'quickCheckoutTotal': quickCheckout['total'],
      'revenueSeries': revenueSeries,
    };
  }

  Future<int> _countAppointments(
    Database database,
    DateTime start,
    DateTime end, {
    String? status,
  }) async {
    final whereClauses = <String>['starts_at >= ?', 'starts_at < ?'];
    final whereArgs = <Object?>[start.toIso8601String(), end.toIso8601String()];

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status);
    }

    final result = Sqflite.firstIntValue(
      await database.query(
        'appointments',
        columns: const ['COUNT(*)'],
        where: whereClauses.join(' AND '),
        whereArgs: whereArgs,
      ),
    );

    return result ?? 0;
  }

  Future<int> _sumRevenue(
    Database database,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await database.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total '
      'FROM invoices '
      'WHERE paid_at IS NOT NULL AND paid_at >= ? AND paid_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );

    return _toInt(rows.first['total']);
  }

  Future<Map<String, Object?>?> _findNextAppointment(
    Database database,
    DateTime now,
  ) async {
    final rows = await database.query(
      'appointments',
      columns: const ['starts_at', 'customer_name', 'service_name', 'status'],
      where: 'starts_at >= ? AND status != ?',
      whereArgs: [now.toIso8601String(), 'Hoàn thành'],
      orderBy: 'starts_at ASC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<List<Map<String, Object?>>> _buildFeaturedCustomers(
    Database database,
    DateTime now,
    DateTime startThisMonth,
  ) async {
    final rows = await database.query(
      'customers',
      columns: const [
        'id',
        'full_name',
        'tier',
        'favorite_service',
        'notes',
        'visit_count',
        'total_spent',
        'last_visit_at',
      ],
      orderBy: 'total_spent DESC, visit_count DESC, updated_at DESC',
      limit: 3,
    );

    final items = <Map<String, Object?>>[];
    for (final row in rows) {
      final fullName = row['full_name']?.toString() ?? 'Khách hàng';
      final customerId = row['id']?.toString() ?? '';
      final nextAppointment = await _findCustomerNextAppointment(
        database,
        customerId,
        now,
      );
      final monthlySpent = await _sumCustomerRevenue(
        database,
        customerId,
        startThisMonth,
      );
      final note = row['notes']?.toString().trim() ?? '';
      items.add({
        'initials': _initials(fullName),
        'name': fullName,
        'tier': row['tier']?.toString() ?? 'Member',
        'service': _fallbackText(
          row['favorite_service'],
          'Chưa có dịch vụ ưu tiên',
        ),
        'note': note.isNotEmpty ? note : _customerInsight(row),
        'appointmentTime': _appointmentTimeLabel(nextAppointment),
        'spendLabel': '${_currency(monthlySpent)} tháng này',
      });
    }

    return items;
  }

  Future<Map<String, Object?>?> _findCustomerNextAppointment(
    Database database,
    String customerId,
    DateTime now,
  ) async {
    final rows = await database.query(
      'appointments',
      columns: const ['starts_at'],
      where: 'customer_id = ? AND starts_at >= ?',
      whereArgs: [customerId, now.toIso8601String()],
      orderBy: 'starts_at ASC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<int> _sumCustomerRevenue(
    Database database,
    String customerId,
    DateTime startThisMonth,
  ) async {
    final rows = await database.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total '
      'FROM invoices '
      'WHERE customer_id = ? AND paid_at IS NOT NULL AND paid_at >= ?',
      [customerId, startThisMonth.toIso8601String()],
    );

    return _toInt(rows.first['total']);
  }

  Future<Map<String, Object?>> _buildQuickCheckoutSummary(
    Database database,
  ) async {
    const draftInvoiceId = 'invoice-draft-001';
    final invoiceRows = await database.query(
      'invoices',
      columns: const [
        'customer_id',
        'discount_amount',
        'payment_method',
        'total_amount',
        'appointment_id',
      ],
      where: 'id = ?',
      whereArgs: const [draftInvoiceId],
      limit: 1,
    );

    if (invoiceRows.isEmpty) {
      return {
        'customerName': 'Chưa chọn khách',
        'discount': _currency(0),
        'paymentNote': 'Chưa có draft checkout để hiển thị.',
        'total': _currency(0),
        'lines': const <Map<String, Object?>>[],
      };
    }

    final invoice = invoiceRows.first;
    final customerName = await _findCustomerName(
      database,
      invoice['customer_id']?.toString() ?? '',
    );
    final appointmentStaff = await _findAppointmentStaff(
      database,
      invoice['appointment_id']?.toString(),
    );
    final lineRows = await database.query(
      'invoice_items',
      columns: const ['title', 'quantity', 'total_price'],
      where: 'invoice_id = ?',
      whereArgs: const [draftInvoiceId],
      orderBy: 'id ASC',
      limit: 3,
    );

    return {
      'customerName': customerName,
      'discount': _currency(_toInt(invoice['discount_amount'])),
      'paymentNote': _buildPaymentNote(
        customerName: customerName,
        paymentMethod: invoice['payment_method']?.toString() ?? 'Tiền mặt',
        appointmentStaff: appointmentStaff,
      ),
      'total': _currency(_toInt(invoice['total_amount'])),
      'lines': lineRows
          .map(
            (row) => {
              'label': row['title']?.toString() ?? 'Dịch vụ',
              'qty': _toInt(row['quantity']),
              'stylist': appointmentStaff ?? 'Quầy tiếp nhận',
              'amount': _currency(_toInt(row['total_price'])),
            },
          )
          .toList(growable: false),
    };
  }

  Future<String> _findCustomerName(Database database, String customerId) async {
    final rows = await database.query(
      'customers',
      columns: const ['full_name'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 'Chưa chọn khách';
    }

    return rows.first['full_name']?.toString() ?? 'Chưa chọn khách';
  }

  Future<String?> _findAppointmentStaff(
    Database database,
    String? appointmentId,
  ) async {
    if (appointmentId == null || appointmentId.isEmpty) {
      return null;
    }

    final rows = await database.query(
      'appointments',
      columns: const ['staff_name'],
      where: 'id = ?',
      whereArgs: [appointmentId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final name = rows.first['staff_name']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  }

  Future<List<Map<String, Object?>>> _buildRevenueSeries(
    Database database,
    DateTime startToday,
  ) async {
    final start = startToday.subtract(const Duration(days: 6));
    final rows = await database.rawQuery(
      'SELECT substr(paid_at, 1, 10) AS day_key, COALESCE(SUM(total_amount), 0) AS total '
      'FROM invoices '
      'WHERE paid_at IS NOT NULL AND paid_at >= ? AND paid_at < ? '
      'GROUP BY day_key '
      'ORDER BY day_key ASC',
      [
        start.toIso8601String(),
        startToday.add(const Duration(days: 1)).toIso8601String(),
      ],
    );

    final totalsByDay = <String, int>{
      for (final row in rows) row['day_key'].toString(): _toInt(row['total']),
    };

    return List.generate(7, (index) {
      final day = start.add(Duration(days: index));
      final dayKey = day.toIso8601String().substring(0, 10);
      return {
        'label': _weekdayLabel(day.weekday),
        'value': totalsByDay[dayKey] ?? 0,
      };
    });
  }

  String _deltaLabel(
    int current,
    int previous, {
    required String unit,
    bool currency = false,
  }) {
    if (previous <= 0) {
      if (current <= 0) {
        return 'Chưa phát sinh so với hôm qua';
      }
      return currency
          ? 'Tăng mới ${_currency(current)} so với hôm qua'
          : 'Tăng mới $current $unit so với hôm qua';
    }

    final delta = current - previous;
    if (delta == 0) {
      return 'Giữ nguyên so với hôm qua';
    }

    final ratio = (delta.abs() / previous) * 100;
    final prefix = delta > 0 ? 'Tăng' : 'Giảm';
    return '$prefix ${ratio.round()}% so với hôm qua';
  }

  String _buildPaymentNote({
    required String customerName,
    required String paymentMethod,
    String? appointmentStaff,
  }) {
    final staff = appointmentStaff == null
        ? 'đội lễ tân'
        : 'stylist $appointmentStaff';
    return '$customerName đang ở draft checkout, thanh toán bằng $paymentMethod và được theo dõi bởi $staff.';
  }

  String _customerInsight(Map<String, Object?> row) {
    final visitCount = _toInt(row['visit_count']);
    final totalSpent = _toInt(row['total_spent']);
    if (visitCount >= 10) {
      return 'Khách quay lại đều, đã có $visitCount lượt ghé salon.';
    }
    if (totalSpent > 0) {
      return 'Tổng chi tiêu hiện tại ${_currency(totalSpent)}.';
    }
    return 'Khách mới, cần tiếp tục làm giàu dữ liệu hành vi.';
  }

  String _appointmentTimeLabel(Map<String, Object?>? row) {
    if (row == null) {
      return 'Chưa có lịch tiếp theo';
    }

    final startsAt = _parseDateTime(row['starts_at']);
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final time = _timeLabel(startsAt);

    if (!startsAt.isBefore(startToday) && startsAt.isBefore(startTomorrow)) {
      return '$time hôm nay';
    }

    if (!startsAt.isBefore(startTomorrow) &&
        startsAt.isBefore(startTomorrow.add(const Duration(days: 1)))) {
      return '$time ngày mai';
    }

    return '$time ${DateFormat('dd/MM').format(startsAt)}';
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Th 2';
      case DateTime.tuesday:
        return 'Th 3';
      case DateTime.wednesday:
        return 'Th 4';
      case DateTime.thursday:
        return 'Th 5';
      case DateTime.friday:
        return 'Th 6';
      case DateTime.saturday:
        return 'Th 7';
      default:
        return 'CN';
    }
  }

  String _currency(int value) {
    return _currencyFormatter.format(value).replaceAll(',', '.');
  }

  String _initials(String fullName) {
    final parts = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return _firstRune(parts.first).toUpperCase();
    }
    return '${_firstRune(parts.first)}${_firstRune(parts.last)}'.toUpperCase();
  }

  String _firstRune(String value) {
    if (value.isEmpty) {
      return '?';
    }
    return String.fromCharCodes(value.runes.take(1));
  }

  String _fallbackText(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _timeLabel(DateTime value) {
    return DateFormat('HH:mm').format(value);
  }

  DateTime _parseDateTime(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
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
}
