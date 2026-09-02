import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../models/reports_period.dart';
import 'repository_contracts.dart';

class SqliteReportsRepository implements ReportsRepository {
  SqliteReportsRepository(this._database, FakeSalonDataSource dataSource)
    : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );

  @override
  Future<Map<String, Object?>> fetchReportsSummary({
    required ReportsPeriod period,
  }) async {
    final database = await _database.database;
    await _seed.seedCustomersIfNeeded(database);
    await _seed.seedServicesIfNeeded(database);
    await _seed.seedEmployeesIfNeeded(database);
    await _seed.seedAppointmentsIfNeeded(database);

    final range = _buildRange(period, DateTime.now());

    final revenue = await _sumRevenue(database, range.start, range.end);
    final invoiceCount = await _countInvoices(database, range.start, range.end);
    final topService = await _findTopService(database, range.start, range.end);
    final topEmployee = await _findTopEmployee(
      database,
      range.start,
      range.end,
    );
    final fillRate = await _calcFillRate(database, range.start, range.end);
    final revenueTrend = await _buildRevenueTrend(
      database,
      range.start,
      range.end,
    );
    final servicePerformance = await _buildServicePerformance(
      database,
      range.start,
      range.end,
      revenue,
    );
    final employeePerformance = await _buildEmployeePerformance(
      database,
      range.start,
      range.end,
    );
    final insights = _buildInsights(revenue, fillRate, employeePerformance);

    return {
      'revenue': _currency(revenue),
      'invoiceCount': invoiceCount,
      'topService': topService ?? 'Chưa có dữ liệu',
      'topEmployee': topEmployee ?? 'Chưa có dữ liệu',
      'fillRate': '${fillRate.round()}%',
      'periods': const ['Hôm nay', '7 ngày', '30 ngày', 'Tháng này'],
      'defaultPeriod': '7 ngày',
      'selectedPeriod': period.label,
      'revenueTrend': revenueTrend,
      'servicePerformance': servicePerformance,
      'employeePerformance': employeePerformance,
      'insights': insights,
    };
  }

  ({DateTime start, DateTime end}) _buildRange(
    ReportsPeriod period,
    DateTime now,
  ) {
    final startToday = DateTime(now.year, now.month, now.day);
    switch (period) {
      case ReportsPeriod.today:
        return (
          start: startToday,
          end: startToday.add(const Duration(days: 1)),
        );
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

  Future<int> _sumRevenue(Database db, DateTime start, DateTime end) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount), 0) AS total '
      'FROM invoices '
      'WHERE paid_at IS NOT NULL AND paid_at >= ? AND paid_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return _toInt(rows.first['total']);
  }

  Future<int> _countInvoices(Database db, DateTime start, DateTime end) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt '
      'FROM invoices '
      'WHERE paid_at IS NOT NULL AND paid_at >= ? AND paid_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return _toInt(rows.first['cnt']);
  }

  Future<String?> _findTopService(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      'SELECT ii.title, COALESCE(SUM(ii.total_price), 0) AS total '
      'FROM invoice_items ii '
      'JOIN invoices i ON ii.invoice_id = i.id '
      "WHERE ii.item_type = 'service' AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ? "
      'GROUP BY ii.title '
      'ORDER BY total DESC '
      'LIMIT 1',
      [start.toIso8601String(), end.toIso8601String()],
    );
    if (rows.isEmpty) return null;
    return rows.first['title']?.toString();
  }

  Future<String?> _findTopEmployee(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      'SELECT e.full_name, COALESCE(SUM(ii.total_price), 0) AS total '
      'FROM invoice_items ii '
      'JOIN invoices i ON ii.invoice_id = i.id '
      'JOIN employees e ON ii.employee_id = e.id '
      "WHERE ii.item_type = 'service' AND i.paid_at IS NOT NULL "
      'AND i.paid_at >= ? AND i.paid_at < ? '
      'GROUP BY ii.employee_id '
      'ORDER BY total DESC '
      'LIMIT 1',
      [start.toIso8601String(), end.toIso8601String()],
    );
    if (rows.isEmpty) return null;
    return rows.first['full_name']?.toString();
  }

  Future<double> _calcFillRate(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final totalRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM appointments WHERE starts_at >= ? AND starts_at < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    final completedRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM appointments "
      "WHERE status = 'Hoàn thành' AND starts_at >= ? AND starts_at < ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final total = _toInt(totalRows.first['cnt']);
    final completed = _toInt(completedRows.first['cnt']);
    if (total == 0) return 0;
    return (completed / total) * 100.0;
  }

  Future<List<Map<String, Object?>>> _buildRevenueTrend(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      'SELECT substr(paid_at, 1, 10) AS day_key, COALESCE(SUM(total_amount), 0) AS total '
      'FROM invoices '
      'WHERE paid_at IS NOT NULL AND paid_at >= ? AND paid_at < ? '
      'GROUP BY day_key '
      'ORDER BY day_key ASC',
      [start.toIso8601String(), end.toIso8601String()],
    );

    final totalsByDay = <String, int>{
      for (final row in rows) row['day_key'].toString(): _toInt(row['total']),
    };

    final totalDays = end.difference(start).inDays;
    return List.generate(totalDays, (index) {
      final day = start.add(Duration(days: index));
      final dayKey = day.toIso8601String().substring(0, 10);
      return {'label': _dayLabel(day), 'value': totalsByDay[dayKey] ?? 0};
    });
  }

  Future<List<Map<String, Object?>>> _buildServicePerformance(
    Database db,
    DateTime start,
    DateTime end,
    int totalRevenue,
  ) async {
    final rows = await db.rawQuery(
      'SELECT ii.title, COALESCE(SUM(ii.total_price), 0) AS total, COUNT(*) AS bookings '
      'FROM invoice_items ii '
      'JOIN invoices i ON ii.invoice_id = i.id '
      "WHERE ii.item_type = 'service' AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ? "
      'GROUP BY ii.title '
      'ORDER BY total DESC '
      'LIMIT 3',
      [start.toIso8601String(), end.toIso8601String()],
    );

    if (rows.isEmpty) return const [];

    return rows
        .map((row) {
          final serviceRevenue = _toInt(row['total']);
          final bookings = _toInt(row['bookings']);
          final share = totalRevenue > 0
              ? (serviceRevenue / totalRevenue * 100).round()
              : 0;
          final name = row['title']?.toString() ?? 'Dịch vụ';
          return {
            'name': name,
            'revenue': _currency(serviceRevenue),
            'bookings': bookings,
            'share': '$share%',
            'note': _serviceNote(name, bookings, share),
          };
        })
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _buildEmployeePerformance(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      'SELECT e.full_name, e.role, e.specialty, e.rating_label, '
      '  COALESCE(SUM(ii.total_price), 0) AS total, '
      '  COUNT(DISTINCT i.customer_id) AS clients '
      'FROM employees e '
      'JOIN invoice_items ii ON ii.employee_id = e.id '
      'JOIN invoices i ON ii.invoice_id = i.id '
      "WHERE ii.item_type = 'service' AND i.paid_at IS NOT NULL "
      'AND i.paid_at >= ? AND i.paid_at < ? '
      'GROUP BY e.id '
      'ORDER BY total DESC '
      'LIMIT 3',
      [start.toIso8601String(), end.toIso8601String()],
    );

    if (rows.isEmpty) return const [];

    return rows
        .map((row) {
          final revenue = _toInt(row['total']);
          final clients = _toInt(row['clients']);
          final ratingLabel = row['rating_label']?.toString().trim() ?? '';
          final rating = ratingLabel.isNotEmpty ? ratingLabel : '5.0';
          final specialty = row['specialty']?.toString().trim() ?? '';
          return {
            'name': row['full_name']?.toString() ?? 'Nhân viên',
            'role': row['role']?.toString() ?? 'Stylist',
            'revenue': _currency(revenue),
            'clients': clients,
            'rating': rating,
            'focus': specialty.isNotEmpty
                ? specialty
                : 'Đang tích lũy dữ liệu hiệu suất.',
          };
        })
        .toList(growable: false);
  }

  List<String> _buildInsights(
    int revenue,
    double fillRate,
    List<Map<String, Object?>> employees,
  ) {
    final insights = <String>[];

    if (fillRate >= 80) {
      insights.add(
        'Tỷ lệ kín lịch ${fillRate.round()}% — salon đang vận hành hiệu quả trong tuần này.',
      );
    } else if (fillRate >= 50) {
      insights.add(
        'Tỷ lệ kín lịch ${fillRate.round()}% — còn dư slot, nên chủ động khuyến mãi giờ thấp điểm.',
      );
    } else if (fillRate > 0) {
      insights.add(
        'Tỷ lệ kín lịch ${fillRate.round()}% — cần đẩy phễu booking để tăng lịch hẹn tuần tới.',
      );
    } else {
      insights.add(
        'Chưa có dữ liệu lịch hẹn hoàn thành tuần này. Tiếp tục ghi nhận để theo dõi xu hướng.',
      );
    }

    if (revenue > 0) {
      insights.add(
        'Doanh thu giai đoạn đã chọn đạt ${_currency(revenue)}. Theo dõi định kỳ để phát hiện xu hướng tăng trưởng.',
      );
    } else {
      insights.add(
        'Chưa có doanh thu ghi nhận trong giai đoạn đã chọn. Xác nhận thanh toán để cập nhật số liệu thực.',
      );
    }

    if (employees.isNotEmpty) {
      final topName = employees.first['name']?.toString() ?? '---';
      final topRevenue = employees.first['revenue']?.toString() ?? '---';
      insights.add(
        'Nhân sự dẫn đầu là $topName với doanh thu $topRevenue trong giai đoạn này.',
      );
    } else {
      insights.add(
        'Chưa có dữ liệu nhân sự trong giai đoạn đã chọn. Cần ghi nhận lịch hoàn thành để đo hiệu suất cá nhân.',
      );
    }

    return insights;
  }

  String _serviceNote(String name, int bookings, int sharePct) {
    if (bookings >= 10) {
      return '$name tần suất cao ($bookings lượt), chiếm $sharePct% doanh thu — dịch vụ chủ lực.';
    }
    if (sharePct >= 30) {
      return '$name đóng góp $sharePct% doanh thu, biên lợi nhuận tốt dù ít lịch hơn.';
    }
    return '$name chiếm $sharePct% doanh thu tuần, tiếp tục quan sát xu hướng booking.';
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Hôm nay';
    }

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  String _currency(int value) {
    return _currencyFormatter.format(value).replaceAll(',', '.');
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
