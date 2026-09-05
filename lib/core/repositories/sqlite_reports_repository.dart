import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../models/reports_period.dart';
import 'invoice_revenue_allocation.dart';
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

    final now = DateTime.now();
    final range = _buildRange(period, now);
    final allocatedLines = await loadAllocatedInvoiceLines(
      database,
      start: range.start,
      end: range.end,
    );

    final revenue = await _sumRevenue(database, range.start, range.end);
    final invoiceCount = await _countInvoices(database, range.start, range.end);
    final servicePerformance = _buildServicePerformance(
      allocatedLines,
      revenue,
    );
    final employeePerformance = await _buildEmployeePerformance(
      database,
      allocatedLines,
    );
    final completionRate = await _calcCompletionRate(
      database,
      range.start,
      range.end,
      now,
    );
    final revenueTrend = await _buildRevenueTrend(
      database,
      range.start,
      range.end,
    );
    final insights = _buildInsights(
      period,
      revenue,
      completionRate,
      employeePerformance,
    );

    return {
      'revenue': _currency(revenue),
      'invoiceCount': invoiceCount,
      'topService': servicePerformance.isEmpty
          ? 'Chưa có dữ liệu'
          : servicePerformance.first['name'],
      'topEmployee': employeePerformance.isEmpty
          ? 'Chưa có dữ liệu'
          : employeePerformance.first['name'],
      'completionRate': '${completionRate.round()}%',
      // Compatibility for callers that still read the old field name. The
      // value now has completion-rate semantics and the UI no longer labels it
      // as schedule occupancy.
      'fillRate': '${completionRate.round()}%',
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

  Future<double> _calcCompletionRate(
    Database db,
    DateTime start,
    DateTime end,
    DateTime now,
  ) async {
    final effectiveEnd = end.isAfter(now) ? now : end;
    if (!effectiveEnd.isAfter(start)) return 0;

    final totalRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM appointments "
      "WHERE status != 'Đã hủy' AND starts_at >= ? AND starts_at < ?",
      [start.toIso8601String(), effectiveEnd.toIso8601String()],
    );
    final completedRows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM appointments "
      "WHERE status = 'Hoàn thành' AND starts_at >= ? AND starts_at < ?",
      [start.toIso8601String(), effectiveEnd.toIso8601String()],
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

  List<Map<String, Object?>> _buildServicePerformance(
    List<AllocatedInvoiceLine> lines,
    int totalRevenue,
  ) {
    final aggregates = <String, _ServiceAggregate>{};
    for (final line in lines) {
      if (line.itemType != 'service') continue;
      final name = line.title.trim().isEmpty ? 'Dịch vụ' : line.title.trim();
      final aggregate = aggregates.putIfAbsent(
        name,
        () => _ServiceAggregate(name),
      );
      aggregate.revenue += line.netRevenue;
      aggregate.bookings += line.quantity > 0 ? line.quantity : 1;
    }

    final ordered = aggregates.values.toList()
      ..sort((left, right) {
        final revenueCompare = right.revenue.compareTo(left.revenue);
        return revenueCompare != 0
            ? revenueCompare
            : left.name.compareTo(right.name);
      });

    return ordered.take(3).map((aggregate) {
      final share = totalRevenue > 0
          ? (aggregate.revenue / totalRevenue * 100)
                .round()
                .clamp(0, 100)
                .toInt()
          : 0;
      return <String, Object?>{
        'name': aggregate.name,
        'revenue': _currency(aggregate.revenue),
        'bookings': aggregate.bookings,
        'share': '$share%',
        'note': _serviceNote(aggregate.name, aggregate.bookings, share),
      };
    }).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _buildEmployeePerformance(
    Database db,
    List<AllocatedInvoiceLine> lines,
  ) async {
    final aggregates = <String, _EmployeeAggregate>{};
    for (final line in lines) {
      final employeeId = line.employeeId;
      if (line.itemType != 'service' || employeeId == null) continue;
      final aggregate = aggregates.putIfAbsent(
        employeeId,
        () => _EmployeeAggregate(employeeId),
      );
      aggregate.revenue += line.netRevenue;
      if (line.customerId.isNotEmpty) {
        aggregate.customerIds.add(line.customerId);
      }
    }
    if (aggregates.isEmpty) return const [];

    final employeeRows = await db.query(
      'employees',
      columns: const ['id', 'full_name', 'role', 'specialty', 'rating_label'],
    );
    final employeeById = <String, Map<String, Object?>>{
      for (final row in employeeRows) row['id']?.toString() ?? '': row,
    };

    final ordered = aggregates.values.toList()
      ..sort((left, right) {
        final revenueCompare = right.revenue.compareTo(left.revenue);
        if (revenueCompare != 0) return revenueCompare;
        final leftName = employeeById[left.employeeId]?['full_name']?.toString() ?? '';
        final rightName = employeeById[right.employeeId]?['full_name']?.toString() ?? '';
        return leftName.compareTo(rightName);
      });

    return ordered.take(3).map((aggregate) {
      final row = employeeById[aggregate.employeeId];
      final ratingLabel = row?['rating_label']?.toString().trim() ?? '';
      final specialty = row?['specialty']?.toString().trim() ?? '';
      return <String, Object?>{
        'name': row?['full_name']?.toString() ?? 'Nhân viên',
        'role': row?['role']?.toString() ?? 'Stylist',
        'revenue': _currency(aggregate.revenue),
        'clients': aggregate.customerIds.length,
        'rating': ratingLabel.isEmpty ? 'Chưa có đánh giá' : ratingLabel,
        'focus': specialty.isNotEmpty
            ? specialty
            : 'Đang tích lũy dữ liệu hiệu suất.',
      };
    }).toList(growable: false);
  }

  List<String> _buildInsights(
    ReportsPeriod period,
    int revenue,
    double completionRate,
    List<Map<String, Object?>> employees,
  ) {
    final context = _periodContext(period);
    final insights = <String>[];

    if (completionRate >= 80) {
      insights.add(
        'Tỷ lệ hoàn thành ${completionRate.round()}% $context — phần lớn lịch đã qua được hoàn tất.',
      );
    } else if (completionRate >= 50) {
      insights.add(
        'Tỷ lệ hoàn thành ${completionRate.round()}% $context — nên rà soát các lịch đã qua chưa hoàn tất.',
      );
    } else if (completionRate > 0) {
      insights.add(
        'Tỷ lệ hoàn thành ${completionRate.round()}% $context — còn nhiều lịch đã qua chưa được chốt trạng thái.',
      );
    } else {
      insights.add(
        'Chưa có lịch đã qua đủ dữ liệu để tính tỷ lệ hoàn thành $context.',
      );
    }

    if (revenue > 0) {
      insights.add(
        'Doanh thu $context đạt ${_currency(revenue)}. Theo dõi định kỳ để phát hiện xu hướng tăng trưởng.',
      );
    } else {
      insights.add(
        'Chưa có doanh thu ghi nhận $context. Xác nhận thanh toán để cập nhật số liệu thực.',
      );
    }

    if (employees.isNotEmpty) {
      final topName = employees.first['name']?.toString() ?? '---';
      final topRevenue = employees.first['revenue']?.toString() ?? '---';
      insights.add(
        'Nhân sự dẫn đầu $context là $topName với doanh thu phân bổ sau giảm giá $topRevenue.',
      );
    } else {
      insights.add(
        'Chưa có doanh thu dịch vụ gắn nhân viên $context để đo hiệu suất cá nhân.',
      );
    }

    return insights;
  }

  String _periodContext(ReportsPeriod period) {
    switch (period) {
      case ReportsPeriod.today:
        return 'hôm nay';
      case ReportsPeriod.last7Days:
        return 'trong 7 ngày qua';
      case ReportsPeriod.last30Days:
        return 'trong 30 ngày qua';
      case ReportsPeriod.thisMonth:
        return 'trong tháng này';
    }
  }

  String _serviceNote(String name, int bookings, int sharePct) {
    if (bookings >= 10) {
      return '$name tần suất cao ($bookings lượt), chiếm $sharePct% doanh thu — dịch vụ chủ lực.';
    }
    if (sharePct >= 30) {
      return '$name đóng góp $sharePct% doanh thu sau giảm giá dù ít lượt hơn.';
    }
    return '$name chiếm $sharePct% doanh thu giai đoạn đã chọn; tiếp tục quan sát xu hướng.';
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

class _ServiceAggregate {
  _ServiceAggregate(this.name);

  final String name;
  int revenue = 0;
  int bookings = 0;
}

class _EmployeeAggregate {
  _EmployeeAggregate(this.employeeId);

  final String employeeId;
  int revenue = 0;
  final Set<String> customerIds = <String>{};
}
