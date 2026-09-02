import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../models/employee_upsert_input.dart';
import 'repository_contracts.dart';

class SqliteEmployeesRepository implements EmployeesRepository {
  SqliteEmployeesRepository(this._database, FakeSalonDataSource dataSource)
    : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

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
  Future<Map<String, Object?>> saveEmployee(
    EmployeeUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    await _seed.seedEmployeesIfNeeded(database);
    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    final now = DateTime.now().toIso8601String();
    final id =
        existing?['id']?.toString() ??
        'emp-${DateTime.now().microsecondsSinceEpoch}';

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

    await database.insert(
      'employees',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    final digits = label.replaceAll('%', '').trim();
    final raw = double.tryParse(digits) ?? 0;
    return raw / 100;
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
