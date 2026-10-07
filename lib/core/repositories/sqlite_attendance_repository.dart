import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/salon_database.dart';
import '../models/attendance.dart';
import '../models/entity_id.dart';
import '../services/sensitive_action_service.dart';

class SqliteAttendanceRepository {
  SqliteAttendanceRepository(
    this.database,
    this.security, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;

  Future<AttendanceSnapshot> fetch(DateTime day) async {
    final db = await database.database;
    return db.transaction((tx) async {
      final employees = await tx.query(
        'employees',
        columns: ['id', 'full_name', 'status'],
        orderBy: 'full_name,id',
      );
      // Keep overnight/open shifts visible even after their scheduled work day.
      final rows = await tx.query(
        'attendance_shifts',
        where: "work_day=? OR state='working'",
        whereArgs: [dayKey(day)],
        orderBy: 'planned_start,employee_name,id',
      );
      return AttendanceSnapshot(
        employees,
        rows.map(AttendanceShift.new).toList(),
      );
    });
  }

  Future<List<Map<String, Object?>>> history(String id) async {
    final db = await database.database;
    return db.query(
      'attendance_events',
      where: 'shift_id=?',
      whereArgs: [id],
      orderBy: 'revision DESC',
    );
  }

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<void> plan({
    required String requestId,
    required String employeeId,
    required String label,
    required DateTime start,
    required DateTime end,
  }) async {
    if (label.trim().isEmpty || !end.isAfter(start)) {
      throw ArgumentError('Nhập tên ca và giờ kết thúc sau giờ bắt đầu.');
    }
    final actor = await security.authorizeAttendanceAction(
      'attendance_plan',
      employeeId,
    );
    final db = await database.database;
    final signature = jsonEncode([
      'plan',
      employeeId,
      label.trim(),
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    ]);
    await db.transaction((tx) async {
      if (await _replayed(tx, requestId, signature)) return;
      final employee = await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      );
      if (employee.isEmpty || !_active(employee.single)) {
        throw StateError('Nhân viên không còn làm việc; không tạo ca mới.');
      }
      final overlap = await tx.query(
        'attendance_shifts',
        where:
            "employee_id=? AND state NOT IN ('cancelled') AND planned_start < ? AND planned_end > ?",
        whereArgs: [
          employeeId,
          end.millisecondsSinceEpoch,
          start.millisecondsSinceEpoch,
        ],
        limit: 1,
      );
      if (overlap.isNotEmpty)
        throw StateError('Ca bị trùng giờ với ca đã xếp của nhân viên.');
      final now = clock().toIso8601String();
      final row = <String, Object?>{
        'id': EntityId.create('attendance'),
        'employee_id': employeeId,
        'employee_name': employee.single['full_name'],
        'label': label.trim(),
        'work_day': dayKey(start),
        'planned_start': start.millisecondsSinceEpoch,
        'planned_end': end.millisecondsSinceEpoch,
        'state': 'planned',
        'clock_in': null,
        'clock_out': null,
        'breaks_json': '[]',
        'revision': 1,
        'created_at': now,
        'updated_at': now,
      };
      await tx.insert('attendance_shifts', row);
      await _event(
        tx,
        requestId,
        signature,
        'plan',
        actor,
        'Xếp ca',
        null,
        row,
      );
    });
  }

  /// Desktop operator records time using this machine's clock.
  /// It does not authenticate a selected employee or infer time from sales.
  Future<void> stamp({
    required String requestId,
    required AttendanceShift shift,
    required String operation,
  }) async {
    if (!['in', 'break_start', 'break_end', 'out'].contains(operation)) {
      throw ArgumentError('Thao tác chấm công không hợp lệ.');
    }
    final db = await database.database;
    final signature = jsonEncode([operation, shift.id, shift.revision]);
    await db.transaction((tx) async {
      if (await _replayed(tx, requestId, signature)) return;
      final old = await _current(tx, shift.id, shift.revision);
      final current = AttendanceShift(old);
      final row = Map<String, Object?>.from(old);
      final time = clock();
      final breaks = current.breaks.map((b) => b.toJson()).toList();
      switch (operation) {
        case 'in':
          if (current.state != 'planned')
            throw StateError('Ca này đã được chấm hoặc đã nghỉ/hủy.');
          final employee = await tx.query(
            'employees',
            where: 'id=?',
            whereArgs: [current.employeeId],
          );
          if (employee.isEmpty || !_active(employee.single)) {
            throw StateError('Nhân viên không còn làm việc.');
          }
          final open = await tx.query(
            'attendance_shifts',
            where: "employee_id=? AND state='working'",
            whereArgs: [current.employeeId],
            limit: 1,
          );
          if (open.isNotEmpty)
            throw StateError('Nhân viên còn ca chưa ra. Kết thúc ca đó trước.');
          row['clock_in'] = time.millisecondsSinceEpoch;
          row['state'] = 'working';
        case 'break_start':
          if (current.state != 'working' || current.onBreak)
            throw StateError('Không thể bắt đầu nghỉ.');
          breaks.add(AttendanceBreak(time, null).toJson());
        case 'break_end':
          if (current.state != 'working' || !current.onBreak)
            throw StateError('Không có lần nghỉ đang mở.');
          breaks.last['end'] = time.millisecondsSinceEpoch;
        case 'out':
          if (current.state != 'working' || current.onBreak) {
            throw StateError('Kết thúc nghỉ trước khi ra ca.');
          }
          row['clock_out'] = time.millisecondsSinceEpoch;
          row['state'] = 'completed';
      }
      row['breaks_json'] = jsonEncode(breaks);
      _validate(row, time);
      await _save(
        tx,
        requestId,
        signature,
        operation,
        'Máy salon',
        'Chấm tại desktop',
        old,
        row,
      );
    });
  }

  /// Owner correction is optimistic and retains both snapshots atomically.
  Future<void> correct({
    required String requestId,
    required AttendanceShift shift,
    required String state,
    required DateTime? clockIn,
    required DateTime? clockOut,
    required List<AttendanceBreak> breaks,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('Nhập lý do sửa công.');
    final actor = await security.authorizeAttendanceAction(
      'attendance_correct',
      shift.id,
    );
    final signature = jsonEncode([
      'correct',
      shift.id,
      shift.revision,
      state,
      clockIn?.millisecondsSinceEpoch,
      clockOut?.millisecondsSinceEpoch,
      breaks.map((b) => b.toJson()).toList(),
      reason.trim(),
    ]);
    final db = await database.database;
    await db.transaction((tx) async {
      if (await _replayed(tx, requestId, signature)) return;
      final old = await _current(tx, shift.id, shift.revision);
      final row = Map<String, Object?>.from(old)
        ..['state'] = state
        ..['clock_in'] = clockIn?.millisecondsSinceEpoch
        ..['clock_out'] = clockOut?.millisecondsSinceEpoch
        ..['breaks_json'] = jsonEncode(breaks.map((b) => b.toJson()).toList());
      _validate(row, clock());
      await _save(
        tx,
        requestId,
        signature,
        'correct',
        actor,
        reason.trim(),
        old,
        row,
      );
    });
  }

  static bool _active(Map<String, Object?> row) =>
      !['Tạm nghỉ', 'Đã nghỉ việc', 'Nghỉ việc'].contains(row['status']);

  Future<Map<String, Object?>> _current(
    DatabaseExecutor tx,
    String id,
    int revision,
  ) async {
    final rows = await tx.query(
      'attendance_shifts',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty || rows.single['revision'] != revision) {
      throw StateError(
        'Công đã thay đổi ở cửa sổ khác. Tải lại trước khi thao tác.',
      );
    }
    return rows.single;
  }

  Future<bool> _replayed(
    DatabaseExecutor tx,
    String id,
    String signature,
  ) async {
    if (id.trim().isEmpty) throw ArgumentError('Thiếu mã thao tác.');
    final rows = await tx.query(
      'attendance_events',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return false;
    if (rows.single['signature'] != signature)
      throw StateError('Mã thao tác đã được dùng cho nội dung khác.');
    return true;
  }

  void _validate(Map<String, Object?> row, DateTime now) {
    final shift = AttendanceShift(row);
    if (![
      'planned',
      'working',
      'completed',
      'leave',
      'cancelled',
    ].contains(shift.state)) {
      throw ArgumentError('Trạng thái công không hợp lệ.');
    }
    final start = shift.clockIn, end = shift.clockOut, breaks = shift.breaks;
    if (['planned', 'leave', 'cancelled'].contains(shift.state)) {
      if (start != null || end != null || breaks.isNotEmpty) {
        throw ArgumentError('Ca chưa chấm/nghỉ/hủy không được có giờ công.');
      }
      return;
    }
    if (start == null ||
        start.isAfter(now) ||
        (shift.state == 'working' && end != null) ||
        (shift.state == 'completed' && end == null) ||
        (end != null && (end.isBefore(start) || end.isAfter(now)))) {
      throw ArgumentError('Giờ vào/ra không hợp lệ hoặc nằm trong tương lai.');
    }
    var previous = start;
    for (var i = 0; i < breaks.length; i++) {
      final b = breaks[i];
      if (b.start.isBefore(previous) ||
          b.start.isAfter(end ?? now) ||
          (b.end == null && (i != breaks.length - 1 || end != null)) ||
          (b.end != null &&
              (b.end!.isBefore(b.start) || b.end!.isAfter(end ?? now)))) {
        throw ArgumentError(
          'Các lần nghỉ phải nằm trong ca, đúng thứ tự và không chồng nhau.',
        );
      }
      previous = b.end ?? b.start;
    }
  }

  Future<void> _save(
    DatabaseExecutor tx,
    String requestId,
    String signature,
    String operation,
    String actor,
    String reason,
    Map<String, Object?> old,
    Map<String, Object?> row,
  ) async {
    if (row['state'] != 'cancelled') {
      final scheduled = await tx.query(
        'attendance_shifts',
        where:
            "employee_id=? AND id!=? AND state!='cancelled' AND planned_start < ? AND planned_end > ?",
        whereArgs: [
          row['employee_id'],
          row['id'],
          row['planned_end'],
          row['planned_start'],
        ],
        limit: 1,
      );
      if (scheduled.isNotEmpty)
        throw StateError(
          'Ca bị trùng lịch; đối chiếu ca đã xếp trước khi khôi phục.',
        );
    }
    if (row['clock_in'] != null) {
      final overlap = await tx.query(
        'attendance_shifts',
        where:
            "employee_id=? AND id!=? AND clock_in IS NOT NULL AND clock_in < ? AND COALESCE(clock_out,9223372036854775807) > ?",
        whereArgs: [
          row['employee_id'],
          row['id'],
          row['clock_out'] ?? 9223372036854775807,
          row['clock_in'],
        ],
        limit: 1,
      );
      if (overlap.isNotEmpty)
        throw StateError(
          'Giờ công bị trùng với ca khác; đối chiếu trước khi lưu.',
        );
    }
    row['revision'] = (old['revision'] as int) + 1;
    row['updated_at'] = clock().toIso8601String();
    final count = await tx.update(
      'attendance_shifts',
      row,
      where: 'id=? AND revision=?',
      whereArgs: [old['id'], old['revision']],
    );
    if (count != 1) throw StateError('Công đã thay đổi; tải lại.');
    await _event(tx, requestId, signature, operation, actor, reason, old, row);
  }

  Future<void> _event(
    DatabaseExecutor tx,
    String id,
    String signature,
    String operation,
    String actor,
    String reason,
    Map<String, Object?>? before,
    Map<String, Object?> after,
  ) async {
    await tx.insert('attendance_events', {
      'id': id,
      'shift_id': after['id'],
      'revision': after['revision'],
      'operation': operation,
      'actor': actor,
      'reason': reason,
      'signature': signature,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': clock().toIso8601String(),
    });
    await tx.insert('audit_events', {
      'id': EntityId.create('attendance_audit'),
      'actor_name': actor,
      'action': 'attendance_$operation',
      'target_type': 'attendance',
      'target_id': after['id'],
      'result': 'success',
      'detail': reason,
      'created_at': clock().toIso8601String(),
    });
  }
}
