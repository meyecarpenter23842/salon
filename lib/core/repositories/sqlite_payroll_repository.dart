import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/salon_database.dart';
import '../models/attendance.dart';
import '../models/entity_id.dart';
import '../models/payroll.dart';
import '../services/sensitive_action_service.dart';

class SqlitePayrollRepository {
  SqlitePayrollRepository(
    this.database,
    this.security, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;
  static String month(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
  static void validatePeriod(String value) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) {
      throw ArgumentError('Kỳ phải có dạng YYYY-MM.');
    }
    final d = DateTime.tryParse('$value-01');
    if (d == null || month(d) != value) {
      throw ArgumentError('Kỳ lương không hợp lệ.');
    }
  }

  Future<PayrollWorkspace> fetch(String period) async {
    validatePeriod(period);
    await security.authorizePayrollAction('payroll_read', period);
    final db = await database.database;
    return db.transaction((tx) async {
      final employees = await tx.query(
        'employees',
        columns: ['id', 'full_name', 'status'],
        orderBy: 'full_name,id',
      );
      final policies = await tx.query(
        'payroll_policies',
        orderBy: 'employee_id,effective_period DESC,revision DESC',
      );
      final rows = await tx.query(
        'payroll_runs',
        where: 'period=?',
        whereArgs: [period],
        orderBy: 'employee_name,id',
      );
      final views = <PayrollView>[];
      for (final row in rows) {
        views.add(await _view(tx, row));
      }
      return PayrollWorkspace(employees, policies, views, await _pending(tx));
    });
  }

  Future<PayrollView> document(String id) async {
    await security.authorizePayrollAction('payroll_read', id);
    final db = await database.database;
    return db.transaction((tx) async => _view(tx, await _run(tx, id)));
  }

  Future<List<Map<String, Object?>>> history(String id) async {
    await security.authorizePayrollAction('payroll_read', id);
    final db = await database.database;
    return db.query(
      'payroll_events',
      where: "target_type='run' AND target_id=?",
      whereArgs: [id],
      orderBy: 'created_at DESC,rowid DESC',
    );
  }

  Future<List<Map<String, Object?>>> closedFor(
    String employeeId,
    String beforePeriod,
  ) async {
    await security.authorizePayrollAction('payroll_read', employeeId);
    final db = await database.database;
    return db.query(
      'payroll_runs',
      where: "employee_id=? AND state='closed' AND period<?",
      whereArgs: [employeeId, beforePeriod],
      orderBy: 'period DESC',
    );
  }

  Future<void> setPolicy({
    required String requestId,
    required String employeeId,
    required String effectivePeriod,
    required String mode,
    required int rate,
    required int standardMinutes,
    required String reason,
  }) async {
    validatePeriod(effectivePeriod);
    payrollBase(mode, rate, 0, standardMinutes);
    if (reason.trim().isEmpty || standardMinutes > 600000) {
      throw ArgumentError('Nhập lý do và công chuẩn hợp lệ.');
    }
    final actor = await security.authorizePayrollAction(
      'payroll_policy',
      employeeId,
    );
    final signature = jsonEncode([
      'policy',
      employeeId,
      effectivePeriod,
      mode,
      rate,
      standardMinutes,
      reason.trim(),
    ]);
    final db = await database.database;
    await db.transaction((tx) async {
      if (await _replay(tx, requestId, signature) != null) {
        return;
      }
      final employee = await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      );
      if (employee.isEmpty) {
        throw StateError('Không tìm thấy nhân viên.');
      }
      final old = await tx.query(
        'payroll_policies',
        where: 'employee_id=?',
        whereArgs: [employeeId],
        orderBy: 'revision DESC',
        limit: 1,
      );
      final row = <String, Object?>{
        'id': EntityId.create('salary_policy'),
        'employee_id': employeeId,
        'revision': old.isEmpty ? 1 : (old.single['revision'] as int) + 1,
        'effective_period': effectivePeriod,
        'mode': mode,
        'rate': rate,
        'standard_minutes': standardMinutes,
        'reason': reason.trim(),
        'actor': actor,
        'created_at': clock().toIso8601String(),
      };
      await tx.insert('payroll_policies', row);
      await _event(
        tx,
        requestId,
        signature,
        'policy',
        'policy',
        row['id'] as String,
        actor,
        reason.trim(),
        old.isEmpty ? null : old.single,
        row,
      );
    });
  }

  Future<String> createDraft({
    required String requestId,
    required String employeeId,
    required String period,
  }) async {
    validatePeriod(period);
    if (period.compareTo(month(clock())) > 0) {
      throw ArgumentError('Chưa lập kỳ lương tương lai.');
    }
    final actor = await security.authorizePayrollAction(
      'payroll_create',
      employeeId,
    );
    final signature = jsonEncode(['create', employeeId, period]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return replay['target_id'] as String;
      }
      await _policy(tx, employeeId, period);
      final employee = await tx.query(
        'employees',
        where: 'id=?',
        whereArgs: [employeeId],
      );
      if (employee.isEmpty) {
        throw StateError('Không tìm thấy nhân viên.');
      }
      if ((await tx.query(
        'payroll_runs',
        where: 'employee_id=? AND period=?',
        whereArgs: [employeeId, period],
      )).isNotEmpty) {
        throw StateError('Nhân viên đã có bảng lương kỳ này. Tải lại.');
      }
      final now = clock().toIso8601String();
      final row = <String, Object?>{
        'id': EntityId.create('payroll'),
        'employee_id': employeeId,
        'employee_name': employee.single['full_name'],
        'period': period,
        'state': 'draft',
        'snapshot_json': '{}',
        'revision': 1,
        'created_at': now,
        'updated_at': now,
        'closed_at': null,
        'closed_by': null,
      };
      await tx.insert('payroll_runs', row);
      await _event(
        tx,
        requestId,
        signature,
        'create',
        'run',
        row['id'] as String,
        actor,
        'Lập bảng lương nháp',
        null,
        row,
      );
      return row['id'] as String;
    });
  }

  Future<void> addItem({
    required String requestId,
    required PayrollView run,
    required String kind,
    required int amount,
    required String reason,
    String? sourceRunId,
    String? reversedItemId,
  }) async {
    if (!['allowance', 'deduction', 'correction', 'reversal'].contains(kind) ||
        amount == 0 ||
        amount.abs() > payrollMoneyLimit ||
        reason.trim().isEmpty ||
        (kind == 'allowance' && amount < 0) ||
        (kind == 'deduction' && amount > 0) ||
        (kind == 'correction' && sourceRunId == null) ||
        (kind == 'reversal' && reversedItemId == null)) {
      throw ArgumentError(
        'Khoản điều chỉnh không hợp lệ; cần số tiền và lý do.',
      );
    }
    final actor = await security.authorizePayrollAction('payroll_item', run.id);
    final signature = jsonEncode([
      'item',
      run.id,
      run.revision,
      kind,
      amount,
      reason.trim(),
      sourceRunId,
      reversedItemId,
    ]);
    final db = await database.database;
    await db.transaction((tx) async {
      if (await _replay(tx, requestId, signature) != null) {
        return;
      }
      final old = await _run(tx, run.id, run.revision);
      if (old['state'] != 'draft') {
        throw StateError('Kỳ đã chốt; ghi điều chỉnh trong kỳ sau.');
      }
      if (sourceRunId != null) {
        final source = await _run(tx, sourceRunId);
        if (source['state'] != 'closed' ||
            source['employee_id'] != old['employee_id'] ||
            (source['period'] as String).compareTo(old['period'] as String) >=
                0) {
          throw StateError('Chọn kỳ đã chốt trước đó của cùng nhân viên.');
        }
      }
      if (reversedItemId != null) {
        final original = await tx.query(
          'payroll_items',
          where: 'id=?',
          whereArgs: [reversedItemId],
        );
        if (original.isEmpty ||
            original.single['run_id'] != run.id ||
            original.single['kind'] == 'reversal' ||
            amount != -(original.single['amount'] as int) ||
            kind != 'reversal') {
          throw StateError(
            'Khoản bỏ phải đảo đúng khoản gốc của bảng lương này.',
          );
        }
      } else if (kind == 'reversal') {
        throw ArgumentError('Thiếu khoản gốc.');
      }
      final row = <String, Object?>{
        'id': EntityId.create('payroll_item'),
        'run_id': run.id,
        'kind': kind,
        'amount': amount,
        'reason': reason.trim(),
        'actor': actor,
        'source_run_id': sourceRunId,
        'reversed_item_id': reversedItemId,
        'created_at': clock().toIso8601String(),
      };
      await tx.insert('payroll_items', row);
      await _touch(tx, old);
      // Recompute now to reject arithmetic overflow within the same transaction.
      await _snapshot(tx, old);
      await _event(
        tx,
        requestId,
        signature,
        'item',
        'run',
        run.id,
        actor,
        reason.trim(),
        old,
        row,
      );
    });
  }

  Future<void> close({
    required String requestId,
    required PayrollView run,
  }) async {
    final actor = await security.authorizePayrollAction(
      'payroll_close',
      run.id,
    );
    final signature = jsonEncode([
      'close',
      run.id,
      run.revision,
      run.previewSignature,
    ]);
    final db = await database.database;
    await db.transaction((tx) async {
      if (await _replay(tx, requestId, signature) != null) {
        return;
      }
      final old = await _run(tx, run.id, run.revision);
      if (old['state'] != 'draft') {
        throw StateError('Kỳ đã chốt.');
      }
      if ((old['period'] as String).compareTo(month(clock())) >= 0) {
        throw StateError('Chỉ chốt tháng đã kết thúc.');
      }
      final snapshot = await _snapshot(tx, old);
      if (jsonEncode(snapshot) != run.previewSignature) {
        throw StateError(
          'Công/chính sách/khoản lương đã thay đổi. Tải lại và đối chiếu trước khi chốt.',
        );
      }
      if ((snapshot['unresolved'] as int) > 0) {
        throw StateError(
          'Còn ca chưa vào/ra. Hoàn tất hoặc ghi nghỉ/hủy trước khi chốt.',
        );
      }
      if ((snapshot['net'] as int) < 0) {
        throw StateError(
          'Khấu trừ vượt lương; đối chiếu và điều chỉnh khoản nhập trước khi chốt.',
        );
      }
      final row = Map<String, Object?>.from(old)
        ..['state'] = 'closed'
        ..['snapshot_json'] = jsonEncode(snapshot)
        ..['closed_at'] = clock().toIso8601String()
        ..['closed_by'] = actor;
      await _touch(tx, old, values: row);
      await _event(
        tx,
        requestId,
        signature,
        'close',
        'run',
        run.id,
        actor,
        'Chốt kỳ; chưa chi tiền',
        old,
        row,
      );
    });
  }

  Future<String> pay({
    required String requestId,
    required PayrollView run,
    required int amount,
    required String method,
    required bool advance,
    String reference = '',
    String note = '',
  }) async {
    if (requestId.trim().isEmpty ||
        amount <= 0 ||
        amount > payrollMoneyLimit ||
        !['cash', 'transfer'].contains(method) ||
        (method == 'transfer' && reference.trim().isEmpty)) {
      throw ArgumentError('Nhập số tiền và chứng từ thanh toán hợp lệ.');
    }
    final actor = await security.authorizePayrollAction('payroll_pay', run.id);
    final signature = jsonEncode([
      'pay',
      run.id,
      run.revision,
      amount,
      method,
      advance,
      reference.trim(),
      note.trim(),
    ]);
    final db = await database.database;
    await db.transaction((tx) async {
      final pending = await _pending(tx);
      if (pending != null &&
          (pending['requestId'] != requestId ||
              pending['signature'] != signature)) {
        throw StateError(
          'Có khoản trả lương chưa đối chiếu. Xử lý khoản đó trước.',
        );
      }
      if (pending == null) {
        await tx.insert('app_settings', {
          'key': 'payroll.pending_payout',
          'value': jsonEncode({
            'requestId': requestId,
            'runId': run.id,
            'revision': run.revision,
            'amount': amount,
            'method': method,
            'advance': advance,
            'reference': reference.trim(),
            'note': note.trim(),
            'signature': signature,
          }),
          'updated_at': clock().toIso8601String(),
        });
      }
    });
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        await _clearPending(tx);
        return requestId;
      }
      final pending = await _pending(tx);
      if (pending == null ||
          pending['requestId'] != requestId ||
          pending['signature'] != signature) {
        throw StateError('Yêu cầu chi lương đã thay đổi hoặc đã bỏ. Tải lại.');
      }
      final old = await _run(tx, run.id, run.revision);
      if ((advance && old['state'] != 'draft') ||
          (!advance && old['state'] != 'closed')) {
        throw StateError('Tạm ứng cho kỳ nháp; chi lương cho kỳ đã chốt.');
      }
      final latest = await _view(tx, old);
      if (!advance && amount > latest.balance) {
        throw StateError('Số trả vượt lương còn phải trả.');
      }
      checkedTotal([...latest.payouts.map((p) => p['amount'] as int), amount]);
      if (method == 'transfer') {
        final payroll = await tx.query(
          'payroll_payouts',
          where:
              "employee_id=? AND reference=? COLLATE NOCASE AND method='transfer'",
          whereArgs: [old['employee_id'], reference.trim()],
          limit: 1,
        );
        final commission = await tx.query(
          'commission_payouts',
          where:
              "employee_id=? AND reference=? COLLATE NOCASE AND method='transfer'",
          whereArgs: [old['employee_id'], reference.trim()],
          limit: 1,
        );
        if (payroll.isNotEmpty || commission.isNotEmpty) {
          throw StateError(
            'Mã chuyển khoản đã ghi trả lương/hoa hồng cho nhân viên.',
          );
        }
        final expense = await tx.query(
          'expense_payments',
          columns: const ['id'],
          where: "method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs: [reference.trim()],
          limit: 1,
        );
        final supplier = await tx.query(
          'supplier_payments',
          columns: const ['id'],
          where: "method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs: [reference.trim()],
          limit: 1,
        );
        if (expense.isNotEmpty || supplier.isNotEmpty) {
          throw StateError(
            'Mã chuyển khoản đã dùng cho chứng từ chi phí/NCC.',
          );
        }
      }
      String? movementId;
      final now = clock().toIso8601String();
      if (method == 'cash') {
        final till = await tx.query(
          'cashier_shifts',
          where: 'closed_at IS NULL',
          limit: 1,
        );
        if (till.isEmpty) {
          throw StateError('Mở ca thu ngân trước khi trả tiền mặt.');
        }
        movementId = 'payroll-cash-$requestId';
        await tx.insert('cash_movements', {
          'id': movementId,
          'shift_id': till.single['id'],
          'movement_type': 'out',
          'amount': amount,
          'reason':
              '${advance ? 'Tạm ứng' : 'Trả lương'} ${old['employee_name']} · ${old['period']} · $requestId',
          'created_at': now,
        });
      }
      final row = <String, Object?>{
        'id': requestId,
        'run_id': run.id,
        'employee_id': old['employee_id'],
        'kind': advance ? 'advance' : 'salary',
        'amount': amount,
        'method': method,
        'reference': reference.trim(),
        'note': note.trim(),
        'actor': actor,
        'cash_movement_id': movementId,
        'signature': signature,
        'created_at': now,
      };
      await tx.insert('payroll_payouts', row);
      await _touch(tx, old);
      await _event(
        tx,
        requestId,
        signature,
        'pay',
        'run',
        run.id,
        actor,
        note.trim(),
        old,
        row,
      );
      await _clearPending(tx);
      return requestId;
    });
  }

  Future<bool> resolvePending(String requestId) async {
    final actor = await security.authorizePayrollAction(
      'payroll_resolve',
      requestId,
    );
    final db = await database.database;
    return db.transaction((tx) async {
      final pending = await _pending(tx);
      if (pending != null && pending['requestId'] != requestId) {
        throw StateError('Khoản đang chờ đã thay đổi.');
      }
      final proof = await tx.query(
        'payroll_payouts',
        where: 'id=?',
        whereArgs: [requestId],
      );
      await _clearPending(tx);
      await tx.insert('audit_events', {
        'id': EntityId.create('payroll_audit'),
        'actor_name': actor,
        'action': 'payroll_resolve',
        'target_type': 'payroll',
        'target_id': requestId,
        'result': 'success',
        'detail': proof.isEmpty
            ? 'Đã đọc sổ: chưa ghi trả; bỏ yêu cầu'
            : 'Đã tìm thấy chứng từ trả',
        'created_at': clock().toIso8601String(),
      });
      return proof.isNotEmpty;
    });
  }

  static int checkedTotal(Iterable<int> values) {
    final total = values.fold<BigInt>(
      BigInt.zero,
      (sum, v) => sum + BigInt.from(v),
    );
    if (total.abs() > BigInt.from(payrollMoneyLimit)) {
      throw ArgumentError('Tổng tiền vượt giới hạn.');
    }
    return total.toInt();
  }

  Future<Map<String, Object?>> _policy(
    DatabaseExecutor tx,
    String employeeId,
    String period,
  ) async {
    final rows = await tx.query(
      'payroll_policies',
      where: 'employee_id=? AND effective_period<=?',
      whereArgs: [employeeId, period],
      orderBy: 'effective_period DESC,revision DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        'Thiết lập lương có hiệu lực cho nhân viên trong kỳ này trước.',
      );
    }
    return rows.single;
  }

  Future<Map<String, Object?>> _run(
    DatabaseExecutor tx,
    String id, [
    int? revision,
  ]) async {
    final rows = await tx.query('payroll_runs', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty ||
        (revision != null && rows.single['revision'] != revision)) {
      throw StateError(
        'Bảng lương đã thay đổi ở cửa sổ khác. Tải lại trước khi thao tác.',
      );
    }
    return rows.single;
  }

  Future<Map<String, Object?>> _snapshot(
    DatabaseExecutor tx,
    Map<String, Object?> row,
  ) async {
    final policy = await _policy(
      tx,
      row['employee_id'] as String,
      row['period'] as String,
    );
    final attendance = await tx.query(
      'attendance_shifts',
      where: "employee_id=? AND work_day LIKE ?",
      whereArgs: [row['employee_id'], '${row['period']}-%'],
      orderBy: 'work_day,planned_start,id',
    );
    var seconds = 0, unresolved = 0;
    for (final a in attendance) {
      final s = AttendanceShift(a);
      seconds += s.workedSeconds ?? 0;
      if (['working', 'planned'].contains(s.state)) {
        unresolved++;
      }
    }
    final items = await tx.query(
      'payroll_items',
      where: 'run_id=?',
      whereArgs: [row['id']],
      orderBy: 'created_at,id',
    );
    final extras = checkedTotal(items.map((i) => i['amount'] as int));
    final base = payrollBase(
      policy['mode'] as String,
      policy['rate'] as int,
      seconds,
      policy['standard_minutes'] as int,
    );
    final commission = await _commission(tx, row['employee_id'] as String);
    return {
      'policy': policy,
      'attendance': attendance,
      'items': items,
      'worked_seconds': seconds,
      'unresolved': unresolved,
      'base': base,
      'extras': extras,
      'net': checkedTotal([base, extras]),
      'commission_separate': commission,
    };
  }

  Future<int> _commission(DatabaseExecutor tx, String id) async {
    final rows = await tx.rawQuery(
      """SELECT
      COALESCE((SELECT SUM(c.amount) FROM commission_entries c JOIN commission_periods p ON p.period=c.period WHERE c.employee_id=?),0)
      - COALESCE((SELECT SUM(amount) FROM commission_payouts WHERE employee_id=?),0) balance""",
      [id, id],
    );
    return rows.single['balance'] as int;
  }

  Future<PayrollView> _view(
    DatabaseExecutor tx,
    Map<String, Object?> row,
  ) async {
    final closed = row['state'] == 'closed';
    final stored = closed
        ? Map<String, Object?>.from(
            jsonDecode(row['snapshot_json'] as String) as Map,
          )
        : await _snapshot(tx, row);
    final currentAttendance = await tx.query(
      'attendance_shifts',
      where: 'employee_id=? AND work_day LIKE ?',
      whereArgs: [row['employee_id'], '${row['period']}-%'],
      orderBy: 'work_day,planned_start,id',
    );
    final currentPolicy = await _policy(
      tx,
      row['employee_id'] as String,
      row['period'] as String,
    );
    final payouts = await tx.query(
      'payroll_payouts',
      where: 'run_id=?',
      whereArgs: [row['id']],
      orderBy: 'created_at,id',
    );
    final items = await tx.query(
      'payroll_items',
      where: 'run_id=?',
      whereArgs: [row['id']],
      orderBy: 'created_at,id',
    );
    final policies = await tx.query(
      'payroll_policies',
      where: 'employee_id=?',
      whereArgs: [row['employee_id']],
      orderBy: 'revision DESC',
    );
    final changed =
        row['state'] == 'closed' &&
        jsonEncode([stored['attendance'], stored['policy']]) !=
            jsonEncode([currentAttendance, currentPolicy]);
    return PayrollView(
      row: row,
      snapshot: stored,
      items: items,
      payouts: payouts,
      policyHistory: policies,
      sourceChanged: changed,
      commissionBalance: await _commission(tx, row['employee_id'] as String),
    );
  }

  Future<void> _touch(
    DatabaseExecutor tx,
    Map<String, Object?> old, {
    Map<String, Object?>? values,
  }) async {
    final row = values ?? Map<String, Object?>.from(old);
    row['revision'] = (old['revision'] as int) + 1;
    row['updated_at'] = clock().toIso8601String();
    final count = await tx.update(
      'payroll_runs',
      row,
      where: 'id=? AND revision=?',
      whereArgs: [old['id'], old['revision']],
    );
    if (count != 1) {
      throw StateError('Bảng lương đã thay đổi.');
    }
  }

  Future<Map<String, Object?>?> _replay(
    DatabaseExecutor tx,
    String id,
    String signature,
  ) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('Thiếu mã yêu cầu.');
    }
    final rows = await tx.query(
      'payroll_events',
      where: 'id=?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    if (rows.single['signature'] != signature) {
      throw StateError('Mã yêu cầu đã dùng cho nội dung khác.');
    }
    return rows.single;
  }

  Future<Map<String, Object?>?> _pending(DatabaseExecutor tx) async {
    final rows = await tx.query(
      'app_settings',
      where: 'key=?',
      whereArgs: ['payroll.pending_payout'],
    );
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  Future<void> _clearPending(DatabaseExecutor tx) => tx
      .delete(
        'app_settings',
        where: 'key=?',
        whereArgs: ['payroll.pending_payout'],
      )
      .then((_) {});
  Future<void> _event(
    DatabaseExecutor tx,
    String id,
    String signature,
    String operation,
    String type,
    String target,
    String actor,
    String reason,
    Map<String, Object?>? before,
    Map<String, Object?> after,
  ) async {
    await tx.insert('payroll_events', {
      'id': id,
      'target_type': type,
      'target_id': target,
      'operation': operation,
      'signature': signature,
      'actor': actor,
      'reason': reason,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': clock().toIso8601String(),
    });
    await tx.insert('audit_events', {
      'id': EntityId.create('payroll_audit'),
      'actor_name': actor,
      'action': 'payroll_$operation',
      'target_type': 'payroll',
      'target_id': target,
      'result': 'success',
      'detail': reason,
      'created_at': clock().toIso8601String(),
    });
  }
}

