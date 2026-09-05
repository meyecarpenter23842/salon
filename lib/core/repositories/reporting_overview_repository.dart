import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import 'invoice_revenue_allocation.dart';
import 'repository_contracts.dart';

class ReportingOverviewRepository implements OverviewRepository {
  ReportingOverviewRepository(this._database, this._delegate);

  final SalonDatabase _database;
  final OverviewRepository _delegate;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );

  @override
  Future<Map<String, Object?>> fetchOverviewSummary() async {
    final summary = Map<String, Object?>.from(
      await _delegate.fetchOverviewSummary(),
    );
    final database = await _database.database;
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final startYesterday = startToday.subtract(const Duration(days: 1));

    final appointmentsToday = await _countActiveAppointments(
      database,
      startToday,
      startTomorrow,
    );
    final appointmentsYesterday = await _countActiveAppointments(
      database,
      startYesterday,
      startToday,
    );
    final customersToday = await _countActiveCustomers(
      database,
      startToday,
      startTomorrow,
    );
    final customersYesterday = await _countActiveCustomers(
      database,
      startYesterday,
      startToday,
    );

    final kpis = summary['kpis'];
    if (kpis is List) {
      summary['kpis'] = kpis.map((raw) {
        if (raw is! Map) return raw;
        final item = Map<String, Object?>.from(raw.cast<String, Object?>());
        switch (item['title']?.toString()) {
          case 'Khách hôm nay':
            item['value'] = customersToday.toString();
            item['note'] = _deltaLabel(
              customersToday,
              customersYesterday,
              unit: 'khách',
            );
            break;
          case 'Lịch hôm nay':
            item['value'] = appointmentsToday.toString();
            item['note'] = _deltaLabel(
              appointmentsToday,
              appointmentsYesterday,
              unit: 'lịch',
            );
            break;
        }
        return item;
      }).toList(growable: false);
    }

    final allocatedLines = await loadAllocatedInvoiceLines(
      database,
      start: startToday,
      end: startTomorrow,
    );
    summary['topSales'] = _buildTopSales(allocatedLines);

    return summary;
  }

  Future<int> _countActiveAppointments(
    DatabaseExecutor database,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await database.rawQuery(
      "SELECT COUNT(*) AS total FROM appointments "
      "WHERE starts_at >= ? AND starts_at < ? AND status != 'Đã hủy'",
      [start.toIso8601String(), end.toIso8601String()],
    );
    return _toInt(rows.first['total']);
  }

  Future<int> _countActiveCustomers(
    DatabaseExecutor database,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await database.rawQuery(
      "SELECT COUNT(DISTINCT customer_id) AS total FROM appointments "
      "WHERE starts_at >= ? AND starts_at < ? AND status != 'Đã hủy'",
      [start.toIso8601String(), end.toIso8601String()],
    );
    return _toInt(rows.first['total']);
  }

  List<Map<String, Object?>> _buildTopSales(
    List<AllocatedInvoiceLine> lines,
  ) {
    final aggregates = <String, _SalesAggregate>{};
    for (final line in lines) {
      final type = line.itemType == 'product' ? 'Sản phẩm' : 'Dịch vụ';
      final title = line.title.trim().isEmpty ? 'Mục bán' : line.title.trim();
      final key = '${line.itemType}\u0000$title';
      final aggregate = aggregates.putIfAbsent(
        key,
        () => _SalesAggregate(title: title, type: type),
      );
      aggregate.quantity += line.quantity;
      aggregate.revenue += line.netRevenue;
    }

    final ordered = aggregates.values.toList()
      ..sort((left, right) {
        final revenueCompare = right.revenue.compareTo(left.revenue);
        if (revenueCompare != 0) return revenueCompare;
        final quantityCompare = right.quantity.compareTo(left.quantity);
        return quantityCompare != 0
            ? quantityCompare
            : left.title.compareTo(right.title);
      });

    return ordered.take(6).map((aggregate) {
      return <String, Object?>{
        'title': aggregate.title,
        'type': aggregate.type,
        'quantity': aggregate.quantity,
        'revenue': aggregate.revenue,
        'revenueLabel': _currency(aggregate.revenue),
      };
    }).toList(growable: false);
  }

  String _deltaLabel(int current, int previous, {required String unit}) {
    if (previous <= 0) {
      if (current <= 0) return 'Chưa phát sinh so với hôm qua';
      return 'Tăng mới $current $unit so với hôm qua';
    }
    final delta = current - previous;
    if (delta == 0) return 'Giữ nguyên so với hôm qua';
    final ratio = (delta.abs() / previous) * 100;
    return '${delta > 0 ? 'Tăng' : 'Giảm'} ${ratio.round()}% so với hôm qua';
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

class _SalesAggregate {
  _SalesAggregate({required this.title, required this.type});

  final String title;
  final String type;
  int quantity = 0;
  int revenue = 0;
}
