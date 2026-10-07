import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../services/sensitive_action_service.dart';
import 'commission_ledger.dart';

class CommissionAccount {
  const CommissionAccount({required this.id, required this.name,
    required this.earned, required this.settled, required this.paid});
  final String id, name;
  final int earned, settled, paid;
  int get balance => settled - paid;
}

class CommissionSnapshot {
  const CommissionSnapshot({required this.periods, required this.closed,
    required this.accounts, required this.entries, required this.payouts});
  final List<String> periods;
  final Set<String> closed;
  final List<CommissionAccount> accounts;
  final List<Map<String,Object?>> entries, payouts;
}

class SqliteCommissionRepository {
  SqliteCommissionRepository(this.database, this.security, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;

  Future<Map<String,Object?>?> pendingPayout() async {
    final db=await database.database;
    final row=await db.query('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
    return row.isEmpty ? null : Map<String,Object?>.from(jsonDecode(row.single['value'] as String) as Map);
  }

  /// Cancel only after checking the live database for a committed receipt.
  Future<bool> resolvePendingPayout(String requestId) async {
    final actor=await security.authorizeCommissionAction('commission_resolve',requestId);
    final db=await database.database;
    return db.transaction((tx) async {
      final row=await tx.query('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
      if(row.isEmpty) {
        // A committed transaction clears pending before the caller receives its result.
        final committed=await tx.query('commission_payouts',where:'id=?',whereArgs:[requestId]);
        return committed.isNotEmpty;
      }
      final pending=jsonDecode(row.single['value'] as String) as Map;
      if(pending['requestId'] != requestId) throw StateError('Yêu cầu chi trả đang chờ đã thay đổi.');
      final proof=await tx.query('commission_payouts',where:'id=?',whereArgs:[requestId]);
      await tx.delete('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
      await _audit(tx,actor,'commission_resolve',requestId,
        proof.isEmpty?'Đã kiểm tra: chưa ghi chi trả; bỏ yêu cầu':'Đã đối chiếu chứng từ chi trả',clock());
      return proof.isNotEmpty;
    });
  }

  Future<CommissionSnapshot> fetch() async {
    final db = await database.database;
    // One read transaction prevents mixed balances across concurrent payouts.
    return db.transaction((tx) async {
      final entries = await tx.query('commission_entries', orderBy: 'period DESC, created_at DESC, id');
      final payouts = await tx.query('commission_payouts', orderBy: 'created_at DESC,id');
      final closed = (await tx.query('commission_periods')).map((r)=>r['period'] as String).toSet();
      final rows = await tx.rawQuery("""SELECT e.id,e.full_name,
        COALESCE((SELECT SUM(c.amount) FROM commission_entries c WHERE c.employee_id=e.id),0) earned,
        COALESCE((SELECT SUM(c.amount) FROM commission_entries c JOIN commission_periods p ON p.period=c.period WHERE c.employee_id=e.id),0) settled,
        COALESCE((SELECT SUM(p.amount) FROM commission_payouts p WHERE p.employee_id=e.id),0) paid
        FROM employees e WHERE EXISTS(SELECT 1 FROM commission_entries c WHERE c.employee_id=e.id)
        OR EXISTS(SELECT 1 FROM commission_payouts p WHERE p.employee_id=e.id)
        ORDER BY e.full_name,e.id""");
      final periods = {...closed,...entries.map((r)=>r['period'] as String)}.toList()..sort((a,b)=>b.compareTo(a));
      return CommissionSnapshot(periods: periods, closed: closed,
        accounts: rows.map((r)=>CommissionAccount(id:r['id'] as String,name:r['full_name'] as String,
          earned:r['earned'] as int,settled:r['settled'] as int,paid:r['paid'] as int)).toList(),
        entries:entries,payouts:payouts);
    });
  }

  Future<void> closePeriod(String period) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) throw ArgumentError('Kỳ không hợp lệ.');
    final date = DateTime.tryParse('$period-01');
    if (date == null || CommissionLedger.month(date) != period) throw ArgumentError('Kỳ không hợp lệ.');
    final now = clock();
    if (period.compareTo(CommissionLedger.month(now)) >= 0) throw StateError('Chỉ chốt tháng đã kết thúc.');
    final actor = await security.authorizeCommissionAction('commission_close',period);
    final db = await database.database;
    await db.transaction((tx) async {
      if ((await tx.query('commission_periods',where:'period=?',whereArgs:[period])).isNotEmpty) return;
      if ((await tx.query('commission_entries',where:'period=?',whereArgs:[period],limit:1)).isEmpty) {
        throw StateError('Tháng này chưa có phát sinh hoa hồng được ghi nhận.');
      }
      final older = await tx.rawQuery("""SELECT 1 FROM commission_entries c
        WHERE c.period < ? AND NOT EXISTS(SELECT 1 FROM commission_periods p WHERE p.period=c.period) LIMIT 1""",[period]);
      if (older.isNotEmpty) throw StateError('Chốt các tháng trước theo thứ tự.');
      await tx.insert('commission_periods',{'period':period,'closed_at':now.toIso8601String(),'closed_by':actor});
      await _audit(tx,actor,'commission_close',period,'Chốt tháng; không phát sinh chi tiền',now);
    });
  }

  /// Caller retains requestId on an uncertain result. Exact replay returns proof.
  Future<String> pay({required String requestId,required String employeeId,
    required int amount, required String method, String reference='',String note=''}) async {
    if (requestId.trim().isEmpty || amount <= 0 || amount > 9000000000000 ||
      !['cash','transfer'].contains(method)) {
      throw ArgumentError('Thông tin chi trả không hợp lệ.');
    }
    if (method=='transfer' && reference.trim().isEmpty) throw ArgumentError('Nhập mã giao dịch chuyển khoản.');
    final signature=jsonEncode([employeeId,amount,method,reference.trim(),note.trim()]);
    final actor=await security.authorizeCommissionAction('commission_pay',requestId);
    final db=await database.database;
    // Persist the exact request before money changes, so a restart retains its ID.
    await db.transaction((tx) async {
      final rows=await tx.query('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
      if(rows.isNotEmpty) {
        final old=jsonDecode(rows.single['value'] as String) as Map;
        if(old['requestId']!=requestId || old['signature']!=signature) {
          throw StateError('Có khoản trả đang chờ đối chiếu. Mở lại khoản đó trước.');
        }
      } else {
        await tx.insert('app_settings',{'key':'commission.pending_payout',
          'value':jsonEncode({'requestId':requestId,'employeeId':employeeId,'amount':amount,
            'method':method,'reference':reference.trim(),'note':note.trim(),'signature':signature}),
          'updated_at':clock().toIso8601String()});
      }
    });
    return db.transaction((tx) async {
      final pendingRows=await tx.query('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
      if(pendingRows.isNotEmpty) {
        final current=jsonDecode(pendingRows.single['value'] as String) as Map;
        if(current['requestId']!=requestId || current['signature']!=signature) {
          throw StateError('Khoản trả đang chờ đã thay đổi. Đối chiếu trước khi tiếp tục.');
        }
      }
      final replay=await tx.query('commission_payouts',where:'id=?',whereArgs:[requestId]);
      if(replay.isNotEmpty) {
        if(replay.single['signature']!=signature) throw StateError('Mã yêu cầu đã dùng cho khoản trả khác.');
        await tx.delete('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
        return requestId;
      }
      if(pendingRows.isEmpty) throw StateError('Yêu cầu đã được đối chiếu hoặc bỏ. Tải lại sổ.');
      final employee=await tx.query('employees',where:'id=?',whereArgs:[employeeId],limit:1);
      if(employee.isEmpty) throw StateError('Không tìm thấy nhân viên.');
      final sums=await tx.rawQuery("""SELECT
        COALESCE((SELECT SUM(c.amount) FROM commission_entries c JOIN commission_periods p ON p.period=c.period WHERE c.employee_id=?),0)
        - COALESCE((SELECT SUM(amount) FROM commission_payouts WHERE employee_id=?),0) balance""",[employeeId,employeeId]);
      if(amount>(sums.single['balance'] as int)) throw StateError('Số trả vượt số còn phải trả đã chốt. Tải lại sổ hoa hồng.');
      if(method=='transfer') {
        final duplicate=await tx.query('commission_payouts',
          where:"employee_id=? AND method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs:[employeeId,reference.trim()],limit:1);
        if(duplicate.isNotEmpty) throw StateError('Mã chuyển khoản đã ghi trả cho nhân viên này. Đối chiếu chứng từ cũ.');
        final salaryDuplicate=await tx.query('payroll_payouts',
          where:"employee_id=? AND method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs:[employeeId,reference.trim()],limit:1);
        if(salaryDuplicate.isNotEmpty) { throw StateError('Mã chuyển khoản đã ghi trả lương cho nhân viên. Đối chiếu chứng từ cũ.'); }
        final expenseDuplicate=await tx.query('expense_payments',
          where:"method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs:[reference.trim()],limit:1);
        final supplierDuplicate=await tx.query('supplier_payments',
          where:"method='transfer' AND reference=? COLLATE NOCASE",
          whereArgs:[reference.trim()],limit:1);
        if(expenseDuplicate.isNotEmpty || supplierDuplicate.isNotEmpty) {
          throw StateError('Mã chuyển khoản đã dùng cho chứng từ chi phí/NCC. Đối chiếu chứng từ cũ.');
        }
      }
      final now=clock();
      String? movementId;
      if(method=='cash') {
        final shift=await tx.query('cashier_shifts',where:'closed_at IS NULL',limit:1);
        if(shift.isEmpty) throw StateError('Mở ca thu ngân trước khi trả tiền mặt.');
        movementId='commission-cash-$requestId';
        await tx.insert('cash_movements',{'id':movementId,'shift_id':shift.single['id'],
          'movement_type':'out','amount':amount,'reason':'Trả hoa hồng ${employee.single['full_name']} · $requestId',
          'created_at':now.toIso8601String()});
      }
      await tx.insert('commission_payouts',{'id':requestId,'employee_id':employeeId,
        'employee_name':employee.single['full_name'],'amount':amount,'method':method,
        'reference':reference.trim(),'note':note.trim(),'actor':actor,
        'cash_movement_id':movementId,'signature':signature,'created_at':now.toIso8601String()});
      await _audit(tx,actor,'commission_pay',requestId,'$amount VND; $method; $employeeId',now);
      await tx.delete('app_settings',where:'key=?',whereArgs:['commission.pending_payout']);
      return requestId;
    });
  }

  Future<void> _audit(DatabaseExecutor tx,String actor,String action,String target,String detail,DateTime now) =>
    tx.insert('audit_events',{'id':EntityId.create('commission_audit'),'actor_name':actor,
      'action':action,'target_type':'commission','target_id':target,'result':'success',
      'detail':detail,'created_at':now.toIso8601String()}).then((_) {});
}
