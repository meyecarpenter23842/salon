import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../models/employee_upsert_input.dart';
import '../models/entity_id.dart';
import 'employee_profile_repository.dart';
import 'repository_contracts.dart';

class SqliteEmployeesRepository
    implements EmployeesRepository, EmployeeProfileRepository {
  SqliteEmployeesRepository(this._database, FakeSalonDataSource dataSource)
      : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
  static final DateFormat _timeFormatter = DateFormat('HH:mm');
  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');

  @override
  Future<List<Map<String, Object?>>> fetchEmployeesView() async {
    final database = await _database.database;
    await _seed.seedEmployeesIfNeeded(database);

    final rows = await database.query(
      'employees',
      orderBy: 'role ASC, full_name ASC',
    );
    return rows.map(_toViewRow).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> fetchEmployeeProfile(String employeeId) async {
    final database = await _database.database;
    await _seed.seedEmployeesIfNeeded(database);

    final employee = await _findById(database, employeeId);
    if (employee == null) {
      throw StateError('Employee $employeeId not found');
    }

    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final startTomorrow = startToday.add(const Duration(days: 1));
    final startMonth = DateTime(now.year, now.month, 1);
    final startNextMonth = DateTime(now.year, now.month + 1, 1);

    final todayAppointments = await _fetchAppointments(
      database,
      employeeId,
      start: startToday,
      end: startTomorrow,
      limit: 20,
    );
    final upcomingAppointments = await _fetchAppointments(
      database,
      employeeId,
      start: now,
      excludeCompleted: true,
      limit: 12,
    );
    final history = await _fetchServiceHistory(database, employeeId, limit: 30);
    final monthMetrics = await _fetchMonthMetrics(
      database,
      employeeId,
      startMonth,
      startNextMonth,
    );
    final topServices = await _fetchTopServices(
      database,
      employeeId,
      startMonth,
      startNextMonth,
    );

    final revenue = _toInt(monthMetrics['revenue']);
    final serviceCount = _toInt(monthMetrics['service_count']);
    final customerCount = _toInt(monthMetrics['customer_count']);
    final commissionRate = _toDouble(employee['commission_rate']);
    final estimatedCommission = (revenue * commissionRate).round();
    final nextAppointment = upcomingAppointments.isEmpty
        ? null
        : upcomingAppointments.first;

    return {
      ..._toViewRow(employee),
      'todayAppointments': todayAppointments,
      'upcomingAppointments': upcomingAppointments,
      'serviceHistory': history,
      'topServices': topServices,
      'todayAppointmentCount': todayAppointments.length,
      'monthRevenueValue': revenue,
      'monthRevenue': _currency(revenue),
      'monthServiceCount': serviceCount,
      'monthCustomerCount': customerCount,
      'commissionRate': commissionRate,
      'estimatedCommissionValue': estimatedCommission,
      'estimatedCommission': commissionRate > 0
          ? _currency(estimatedCommission)
          : 'KPI cố định',
      'nextAppointmentLabel': nextAppointment == null
          ? 'Chưa có lịch sắp tới'
          : '${nextAppointment['timeRange']} · ${nextAppointment['customerName']}',
      'dataNote':
          'Doanh thu và hoa hồng lấy từ các dòng dịch vụ đã thanh toán; không dùng số liệu nhập tay.',
    };
  }

  @override
  Future<Map<String, Object?>> saveEmployee(
    EmployeeUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    await _seed.seedEmployeesIfNeeded(database);
    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    if (existingId != null && existing == null) {
      throw StateError('Employee $existingId not found');
    }

    final now = DateTime.now().toIso8601String();
    final id = existing?['id']?.toString() ?? EntityId.create('emp');

    final row = <String, Object?>{
      'id': id,
      'full_name': input.fullName.trim(),
      'initials': _buildInitials(input.fullName),
      'role': input.role,
      'status': input.status,
      'phone': input.phone.trim(),
      'email': existing?['email'],
      'shift_label': input.shift.trim(),
      'specialty': input.specialty.trim(),
      'commission_rate': _parseCommissionRate(input.commissionLabel),
      'commission_label': input.commissionLabel.trim(),
      'today_schedule': input.todaySchedule.trim(),
      'services_done': input.servicesDone,
      'monthly_revenue_label': input.monthlyRevenue.trim(),
      'rating_label': input.rating.trim(),
      'notes': input.note.trim(),
      'created_at': existing?['created_at'] ?? now,
      'updated_at': now,
    };

    if (existing == null) {
      await database.insert(
        'employees',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final updatedCount = await database.update(
        'employees',
        row,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updatedCount != 1) {
        throw StateError('Employee $id disappeared during edit');
      }
    }
    return _toViewRow(row);
  }

  @override
  Future<Map<String, Object?>> updateEmployeeStatus(
    String employeeId,
    String status,
  ) async {
    final database = await _database.database;
    await _seed.seedEmployeesIfNeeded(database);
    final existing = await _findById(database, employeeId);
    if (existing == null) {
      throw StateError('Employee $employeeId not found');
    }

    await database.update(
      'employees',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [employeeId],
    );

    final updated = await _findById(database, employeeId);
    return _toViewRow(updated!);
  }

  Future<List<Map<String, Object?>>> _fetchAppointments(
    Database database,
    String employeeId, {
    required DateTime start,
    DateTime? end,
    bool excludeCompleted = false,
    required int limit,
  }) async {
    final clauses = <String>['employee_id = ?', 'starts_at >= ?'];
    final args = <Object?>[employeeId, start.toIso8601String()];
    if (end != null) {
      clauses.add('starts_at < ?');
      args.add(end.toIso8601String());
    }
    if (excludeCompleted) {
      clauses.add('status != ?');
      args.add('Hoàn thành');
    }

    final rows = await database.query(
      'appointments',
      columns: const [
        'id',
        'customer_id',
        'customer_name',
        'customer_phone',
        'service_name',
        'status',
        'starts_at',
        'duration_minutes',
        'note',
      ],
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'starts_at ASC',
      limit: limit,
    );

    return rows.map((row) {
      final startsAt = _parseDate(row['starts_at']);
      final duration = _toInt(row['duration_minutes']);
      final endsAt = startsAt.add(Duration(minutes: duration));
      return <String, Object?>{
        'id': row['id']?.toString() ?? '',
        'customerId': row['customer_id']?.toString() ?? '',
        'customerName': row['customer_name']?.toString() ?? 'Khách',
        'customerPhone': row['customer_phone']?.toString() ?? '',
        'serviceName': row['service_name']?.toString() ?? 'Dịch vụ',
        'status': row['status']?.toString() ?? '',
        'startsAt': startsAt.toIso8601String(),
        'dateLabel': _dateFormatter.format(startsAt),
        'timeLabel': _timeFormatter.format(startsAt),
        'timeRange':
            '${_timeFormatter.format(startsAt)}–${_timeFormatter.format(endsAt)}',
        'durationMinutes': duration,
        'note': row['note']?.toString() ?? '',
      };
    }).toList(growable: false);
  }

  Future<List<Map<String, Object?>>> _fetchServiceHistory(
    Database database,
    String employeeId, {
    required int limit,
  }) async {
    final rows = await database.rawQuery(
      'SELECT i.id AS invoice_id, i.paid_at, i.customer_id, '
      'c.full_name AS customer_name, ii.title, ii.quantity, '
      'ii.unit_price, ii.discount_amount, ii.total_price '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'LEFT JOIN customers c ON c.id = i.customer_id '
      "WHERE ii.employee_id = ? AND ii.item_type = 'service' "
      'AND i.paid_at IS NOT NULL '
      'ORDER BY i.paid_at DESC '
      'LIMIT ?',
      [employeeId, limit],
    );

    return rows.map((row) {
      final paidAt = _parseDate(row['paid_at']);
      return <String, Object?>{
        'invoiceId': row['invoice_id']?.toString() ?? '',
        'paidAt': paidAt.toIso8601String(),
        'dateLabel': _dateFormatter.format(paidAt),
        'timeLabel': _timeFormatter.format(paidAt),
        'customerId': row['customer_id']?.toString() ?? '',
        'customerName': row['customer_name']?.toString() ?? 'Khách',
        'title': row['title']?.toString() ?? 'Dịch vụ',
        'quantity': _toInt(row['quantity']),
        'unitPrice': _toInt(row['unit_price']),
        'discountAmount': _toInt(row['discount_amount']),
        'totalPrice': _toInt(row['total_price']),
        'revenueLabel': _currency(_toInt(row['total_price'])),
      };
    }).toList(growable: false);
  }

  Future<Map<String, Object?>> _fetchMonthMetrics(
    Database database,
    String employeeId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await database.rawQuery(
      'SELECT COALESCE(SUM(ii.total_price), 0) AS revenue, '
      'COALESCE(SUM(ii.quantity), 0) AS service_count, '
      'COUNT(DISTINCT i.customer_id) AS customer_count '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      "WHERE ii.employee_id = ? AND ii.item_type = 'service' "
      'AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ?',
      [employeeId, start.toIso8601String(), end.toIso8601String()],
    );
    return rows.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(rows.first);
  }

  Future<List<Map<String, Object?>>> _fetchTopServices(
    Database database,
    String employeeId,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await database.rawQuery(
      'SELECT ii.title, COALESCE(SUM(ii.quantity), 0) AS quantity, '
      'COALESCE(SUM(ii.total_price), 0) AS revenue '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      "WHERE ii.employee_id = ? AND ii.item_type = 'service' "
      'AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ? '
      'GROUP BY ii.title '
      'ORDER BY revenue DESC, quantity DESC '
      'LIMIT 5',
      [employeeId, start.toIso8601String(), end.toIso8601String()],
    );

    return rows
        .map(
          (row) => <String, Object?>{
            'title': row['title']?.toString() ?? 'Dịch vụ',
            'quantity': _toInt(row['quantity']),
            'revenue': _toInt(row['revenue']),
            'revenueLabel': _currency(_toInt(row['revenue'])),
          },
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>?> _findById(
    Database database,
    String employeeId,
  ) async {
    final rows = await database.query(
      'employees',
      where: 'id = ?',
      whereArgs: [employeeId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Map<String, Object?> _toViewRow(Map<String, Object?> row) {
    return {
      'id': row['id']?.toString() ?? '',
      'initials':
          row['initials']?.toString() ??
          _buildInitials(row['full_name']?.toString() ?? ''),
      'name': row['full_name']?.toString() ?? '',
      'role': row['role']?.toString() ?? '',
      'status': row['status']?.toString() ?? 'Đang làm việc',
      'phone': row['phone']?.toString() ?? '',
      'shift': row['shift_label']?.toString() ?? '',
      'specialty': row['specialty']?.toString() ?? '',
      'commission': row['commission_label']?.toString() ?? 'KPI cố định',
      'todaySchedule': row['today_schedule']?.toString() ?? '',
      'servicesDone': _toInt(row['services_done']),
      'monthlyRevenue': row['monthly_revenue_label']?.toString() ?? '',
      'rating': row['rating_label']?.toString() ?? '',
      'note': row['notes']?.toString() ?? '',
    };
  }

  String _buildInitials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NS';
    }

    if (parts.length == 1) {
      final name = parts.first;
      return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  double _parseCommissionRate(String label) {
    final digits = label.replaceAll('%', '').trim().replaceAll(',', '.');
    final raw = double.tryParse(digits) ?? 0;
    return raw / 100;
  }

  String _currency(int value) {
    return _currencyFormatter.format(value).replaceAll(',', '.');
  }

  DateTime _parseDate(Object? value) {
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

  double _toDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
