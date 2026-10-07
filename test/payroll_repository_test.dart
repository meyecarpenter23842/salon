import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/database/payroll_schema.dart';
import 'package:salonmanager/core/models/payroll.dart';
import 'package:salonmanager/core/repositories/sqlite_payroll_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_commission_repository.dart';
import 'package:salonmanager/core/repositories/commission_ledger.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/features/employees/presentation/pages/payroll_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SensitiveActionService security;
  late SqlitePayrollRepository repo;
  final now = DateTime(2026, 10, 7);
  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.initialize();
    security = SensitiveActionService(SalonDatabase.instance);
    repo = SqlitePayrollRepository(
      SalonDatabase.instance,
      security,
      clock: () => now,
    );
    await db.insert('employees', {
      'id': 'emp',
      'full_name': 'Thợ A',
      'role': 'Stylist',
      'status': 'Đang làm việc',
      'commission_rate': 0.1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  });
  tearDown(() async {
    await SalonDatabase.instance.close();
  });
  Future<void> policy({
    String id = 'policy',
    String period = '2026-09',
    String mode = 'fixed',
    int rate = 8000000,
    int minutes = 12000,
  }) => repo.setPolicy(
    requestId: id,
    employeeId: 'emp',
    effectivePeriod: period,
    mode: mode,
    rate: rate,
    standardMinutes: minutes,
    reason: 'Thỏa thuận lương',
  );
  Future<PayrollView> draft({String period = '2026-09'}) async {
    final id = await repo.createDraft(
      requestId: 'create-$period',
      employeeId: 'emp',
      period: period,
    );
    return repo.document(id);
  }

  Future<PayrollView> closed() async {
    await policy();
    final r = await draft();
    await repo.close(requestId: 'close', run: r);
    return repo.document(r.id);
  }

  Future<void> attendance({String state = 'completed'}) async {
    final start = DateTime(2026, 9, 30, 21), end = DateTime(2026, 10, 1, 5);
    await db.insert('attendance_shifts', {
      'id': 'time',
      'employee_id': 'emp',
      'employee_name': 'Thợ A',
      'label': 'Ca đêm',
      'work_day': '2026-09-30',
      'planned_start': start.millisecondsSinceEpoch,
      'planned_end': end.millisecondsSinceEpoch,
      'state': state,
      'clock_in': state == 'completed' ? start.millisecondsSinceEpoch : null,
      'clock_out': state == 'completed' ? end.millisecondsSinceEpoch : null,
      'breaks_json': jsonEncode([
        {
          'start': DateTime(2026, 9, 30, 23).millisecondsSinceEpoch,
          'end': DateTime(2026, 9, 30, 23, 30).millisecondsSinceEpoch,
        },
      ]),
      'revision': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<SqliteCommissionRepository> commission() async {
    final date = DateTime(2026, 9, 15).toIso8601String();
    await db.insert('customers', {
      'id': 'cust',
      'full_name': 'Khách',
      'phone': '0',
      'created_at': date,
      'updated_at': date,
    });
    await db.insert('invoices', {
      'id': 'inv',
      'customer_id': 'cust',
      'subtotal': 1000000,
      'discount_amount': 0,
      'total_amount': 1000000,
      'payment_method': 'Tiền mặt',
      'paid_at': date,
      'created_at': date,
      'updated_at': date,
    });
    await db.insert('invoice_items', {
      'id': 'line',
      'invoice_id': 'inv',
      'item_type': 'service',
      'employee_id': 'emp',
      'title': 'Cắt',
      'quantity': 1,
      'unit_price': 1000000,
      'total_price': 1000000,
    });
    await db.transaction(
      (tx) => CommissionLedger.capture(tx, 'inv', DateTime(2026, 9, 15)),
    );
    final c = SqliteCommissionRepository(
      SalonDatabase.instance,
      security,
      clock: () => now,
    );
    await c.closePeriod('2026-09');
    return c;
  }

  test(
    'three policies round once in integer VND and cap prorated monthly wages',
    () {
      expect(payrollBase('fixed', 8000000, 0, 0), 8000000);
      expect(
        payrollBase('monthly_work', 8000000, 180 * 3600, 200 * 60),
        7200000,
      );
      expect(
        payrollBase('monthly_work', 8000000, 220 * 3600, 200 * 60),
        8000000,
      );
      expect(payrollBase('hourly', 50000, 90 * 60, 0), 75000);
      expect(payrollBase('hourly', 1800, 1, 0), 1);
      expect(() => payrollBase('monthly_work', 1, 1, 0), throwsArgumentError);
      expect(
        () => payrollBase('hourly', payrollMoneyLimit, 7200, 0),
        throwsArgumentError,
      );
      expect(
        () => SqlitePayrollRepository.checkedTotal([payrollMoneyLimit, 1]),
        throwsArgumentError,
      );
      expect(
        () => SqlitePayrollRepository.validatePeriod('2026-13'),
        throwsArgumentError,
      );
    },
  );
  test(
    'effective policies preserve revisions and use net overnight attendance in start month',
    () async {
      await policy(mode: 'hourly', rate: 50000);
      await policy(id: 'next', period: '2026-10', rate: 9000000);
      await attendance();
      final r = await draft();
      expect(r.seconds, 27000);
      expect(r.base, 375000);
      expect((await draft(period: '2026-10')).base, 9000000);
      await policy(mode: 'hourly', rate: 50000);
      expect(await db.query('payroll_policies'), hasLength(2));
      await expectLater(policy(mode: 'hourly', rate: 60000), throwsStateError);
      await expectLater(
        db.update('payroll_policies', {'rate': 1}),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
  test('owner gate protects reads, policy edits, close and payments', () async {
    final r = await closed();
    await security.configureOwnerPin('1234');
    security.lockOwnerSession();
    await expectLater(repo.fetch('2026-09'), throwsStateError);
    await expectLater(repo.document(r.id), throwsStateError);
    await expectLater(repo.history(r.id), throwsStateError);
    await expectLater(policy(id: 'locked'), throwsStateError);
    await expectLater(
      repo.pay(
        requestId: 'denied',
        run: r,
        amount: 1,
        method: 'transfer',
        advance: false,
        reference: 'bank',
      ),
      throwsStateError,
    );
    expect(await db.query('payroll_payouts'), isEmpty);
    await security.unlockOwner('1234');
    expect((await repo.document(r.id)).net, 8000000);
  });
  test('stale preview and unfinished or current month cannot close', () async {
    await policy();
    final r = await draft();
    await policy(id: 'raise', rate: 9000000);
    await expectLater(repo.close(requestId: 'stale', run: r), throwsStateError);
    await attendance(state: 'planned');
    final fresh = await repo.document(r.id);
    await expectLater(
      repo.close(requestId: 'unfinished', run: fresh),
      throwsStateError,
    );
    final current = await draft(period: '2026-10');
    await expectLater(
      repo.close(requestId: 'current', run: current),
      throwsStateError,
    );
    expect((await repo.document(r.id)).closed, isFalse);
  });
  test(
    'closed wage stays frozen after policy changes; linked correction in next period',
    () async {
      final r = await closed();
      await policy(id: 'raise', rate: 9000000);
      final old = await repo.document(r.id);
      expect(old.net, 8000000);
      expect(old.sourceChanged, isTrue);
      final next = await draft(period: '2026-10');
      await repo.addItem(
        requestId: 'adjust',
        run: next,
        kind: 'correction',
        amount: 1000000,
        reason: 'Bù kỳ trước',
        sourceRunId: r.id,
      );
      expect((await repo.document(next.id)).net, 10000000);
      await expectLater(
        repo.addItem(
          requestId: 'old-edit',
          run: old,
          kind: 'allowance',
          amount: 1,
          reason: 'X',
        ),
        throwsStateError,
      );
      await expectLater(
        db.update(
          'payroll_runs',
          {'snapshot_json': '{}', 'revision': old.revision + 1},
          where: 'id=?',
          whereArgs: [old.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'items replay exactly, reject stale writer, retain reversal and arithmetic rollback',
    () async {
      await policy();
      final r = await draft();
      await repo.addItem(
        requestId: 'item',
        run: r,
        kind: 'allowance',
        amount: 200000,
        reason: 'Ăn trưa',
      );
      await repo.addItem(
        requestId: 'item',
        run: r,
        kind: 'allowance',
        amount: 200000,
        reason: 'Ăn trưa',
      );
      await expectLater(
        repo.addItem(
          requestId: 'stale',
          run: r,
          kind: 'deduction',
          amount: -1000,
          reason: 'X',
        ),
        throwsStateError,
      );
      final fresh = await repo.document(r.id);
      await repo.addItem(
        requestId: 'reverse',
        run: fresh,
        kind: 'reversal',
        amount: -200000,
        reason: 'Nhập nhầm',
        reversedItemId: fresh.items.single['id'] as String,
      );
      expect((await repo.document(r.id)).extras, 0);
      final updated = await repo.document(r.id);
      await expectLater(
        repo.addItem(
          requestId: 'overflow',
          run: updated,
          kind: 'allowance',
          amount: payrollMoneyLimit,
          reason: 'X',
        ),
        throwsArgumentError,
      );
      expect((await repo.document(r.id)).revision, updated.revision);
      expect(await db.query('payroll_items'), hasLength(2));
      expect(await repo.history(r.id), hasLength(3));
    },
  );
  test(
    'advance reduces salary balance; close does not pay commission or create money movement',
    () async {
      await commission();
      await policy();
      final r = await draft();
      await repo.pay(
        requestId: 'advance',
        run: r,
        amount: 2000000,
        method: 'transfer',
        advance: true,
        reference: 'A',
      );
      final preview = await repo.document(r.id);
      expect(preview.paid, 2000000);
      expect(preview.balance, 6000000);
      expect(preview.commissionBalance, 100000);
      expect(preview.net, 8000000);
      await repo.close(requestId: 'close', run: preview);
      final frozen = await repo.document(r.id);
      await repo.pay(
        requestId: 'partial',
        run: frozen,
        amount: 3000000,
        method: 'transfer',
        advance: false,
        reference: 'B',
      );
      expect((await repo.document(r.id)).balance, 3000000);
      expect(await db.query('commission_payouts'), isEmpty);
      expect(await db.query('cash_movements'), isEmpty);
      final bytes = await buildPayrollPdf(await repo.document(r.id));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
  test(
    'cash payment commits one receipt and movement on replay, blocks overspend',
    () async {
      final r = await closed();
      await db.insert('cashier_shifts', {
        'id': 'till',
        'opening_cash': 10000000,
        'opened_at': now.toIso8601String(),
      });
      Future<String> pay() => repo.pay(
        requestId: 'cash',
        run: r,
        amount: 1000000,
        method: 'cash',
        advance: false,
      );
      await pay();
      await pay();
      expect(await db.query('payroll_payouts'), hasLength(1));
      expect(await db.query('cash_movements'), hasLength(1));
      expect((await repo.fetch('2026-09')).pending, isNull);
      await expectLater(
        db.delete('cash_movements'),
        throwsA(isA<DatabaseException>()),
      );
      final fresh = await repo.document(r.id);
      await expectLater(
        repo.pay(
          requestId: 'over',
          run: fresh,
          amount: 7000001,
          method: 'cash',
          advance: false,
        ),
        throwsStateError,
      );
      expect(await repo.resolvePending('over'), isFalse);
      expect((await repo.document(r.id)).paid, 1000000);
    },
  );
  test(
    'failed payout leaves durable request; transaction rollback removes receipt, event and cash',
    () async {
      final r = await closed();
      await db.insert('cashier_shifts', {
        'id': 'till',
        'opening_cash': 10000000,
        'opened_at': now.toIso8601String(),
      });
      await db.execute(
        """CREATE TRIGGER fail_payroll BEFORE INSERT ON payroll_events WHEN NEW.operation='pay'
      BEGIN SELECT RAISE(ABORT,'fixture failure'); END""",
      );
      await expectLater(
        repo.pay(
          requestId: 'retry',
          run: r,
          amount: 1,
          method: 'cash',
          advance: false,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('payroll_payouts'), isEmpty);
      expect(await db.query('cash_movements'), isEmpty);
      expect((await repo.document(r.id)).revision, r.revision);
      final reopened = SqlitePayrollRepository(
        SalonDatabase.instance,
        security,
        clock: () => now,
      );
      expect((await reopened.fetch('2026-09')).pending!['requestId'], 'retry');
      await expectLater(
        reopened.pay(
          requestId: 'other',
          run: r,
          amount: 2,
          method: 'cash',
          advance: false,
        ),
        throwsStateError,
      );
      await db.execute('DROP TRIGGER fail_payroll');
      await reopened.pay(
        requestId: 'retry',
        run: r,
        amount: 1,
        method: 'cash',
        advance: false,
      );
      expect(await reopened.resolvePending('retry'), isTrue);
      expect(await db.query('cash_movements'), hasLength(1));
    },
  );
  test(
    'concurrent windows serialize payouts and stale version cannot pay twice',
    () async {
      final r = await closed();
      final results = await Future.wait(
        ['a', 'b'].map((id) async {
          try {
            await repo.pay(
              requestId: id,
              run: r,
              amount: 1000,
              method: 'transfer',
              advance: false,
              reference: id,
            );
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(results.where((v) => v), hasLength(1));
      expect(await db.query('payroll_payouts'), hasLength(1));
      final pending = (await repo.fetch('2026-09')).pending;
      if (pending != null) {
        await repo.resolvePending(pending['requestId'] as String);
      }
    },
  );
  test(
    'same bank receipt cannot pay payroll and commission in either direction',
    () async {
      final c = await commission();
      final r = await closed();
      await c.pay(
        requestId: 'commission',
        employeeId: 'emp',
        amount: 1000,
        method: 'transfer',
        reference: 'Bank-X',
      );
      await expectLater(
        repo.pay(
          requestId: 'duplicate',
          run: r,
          amount: 1000,
          method: 'transfer',
          advance: false,
          reference: 'bank-x',
        ),
        throwsStateError,
      );
      await repo.resolvePending('duplicate');
      await repo.pay(
        requestId: 'salary',
        run: r,
        amount: 1000,
        method: 'transfer',
        advance: false,
        reference: 'Bank-Y',
      );
      await expectLater(
        c.pay(
          requestId: 'duplicate-c',
          employeeId: 'emp',
          amount: 1000,
          method: 'transfer',
          reference: 'bank-y',
        ),
        throwsStateError,
      );
      await c.resolvePendingPayout('duplicate-c');
      expect(await db.query('payroll_payouts'), hasLength(1));
      expect(await db.query('commission_payouts'), hasLength(1));
    },
  );
  test(
    'schema 22 and partially installed 23 migrate idempotently; backup verifies all tables',
    () async {
      await policy();
      final r = await draft();
      await PayrollSchema.install(db);
      await db.execute('PRAGMA user_version=22');
      await db.update(
        'app_settings',
        {'value': '22'},
        where: 'key=?',
        whereArgs: ['schema_version'],
      );
      expect(
        (await const BackupService().validateBackupFile(db.path)).isValid,
        isTrue,
      );
      await SalonDatabase.instance.close();
      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(await db.getVersion(), 23);
      expect((await repo.document(r.id)).net, 8000000);
      await PayrollSchema.install(db);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final backup = await const BackupService().createBackup();
      expect(backup.success, isTrue);
      await policy(id: 'raise', rate: 9000000);
      expect((await repo.document(r.id)).net, 9000000);
      expect(
        (await const BackupService().restoreFromBackup(
          backup.filePath!,
        )).success,
        isTrue,
      );
      db = await SalonDatabase.instance.database;
      expect((await repo.document(r.id)).net, 8000000);
      await db.execute('DROP TABLE payroll_events');
      final invalid = await const BackupService().validateBackupFile(db.path);
      expect(invalid.isValid, isFalse);
      expect(invalid.message, contains('payroll_events'));
    },
  );
}

