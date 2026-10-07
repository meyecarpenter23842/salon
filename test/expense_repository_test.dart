import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_cashier_shift_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_expense_repository.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('expense ledger keeps category snapshot and supports partial payment, replay and reversals',
      () async {
    final fixed = DateTime(2026, 10, 7, 10);
    final repo = SqliteExpenseRepository(
      SalonDatabase.instance,
      SensitiveActionService(SalonDatabase.instance),
      clock: () => fixed,
    );

    final category = await repo.createCategory(
      requestId: 'cat-create-1',
      name: 'Thuê mặt bằng',
    );
    final expenseId = await repo.createExpense(
      requestId: 'expense-create-1',
      categoryId: category.id,
      date: DateTime(2026, 10, 1),
      payee: 'Chủ nhà',
      amount: 1000000,
      reason: 'Tiền thuê tháng 10',
      externalReference: 'HD-10',
    );

    final renamed = await repo.renameCategory(
      requestId: 'cat-rename-1',
      id: category.id,
      expectedRevision: category.revision,
      name: 'Mặt bằng',
    );
    final frozen = await repo.document(expenseId);
    expect(frozen.expense.categoryName, 'Thuê mặt bằng');
    expect(frozen.balance, 1000000);
    expect(frozen.state, 'unpaid');

    final inactive = await repo.setCategoryActive(
      requestId: 'cat-disable-1',
      id: renamed.id,
      expectedRevision: renamed.revision,
      active: false,
    );
    await expectLater(
      repo.createExpense(
        requestId: 'expense-blocked',
        categoryId: inactive.id,
        date: fixed,
        payee: 'NCC khác',
        amount: 1,
        reason: 'Không được ghi mới',
      ),
      throwsStateError,
    );

    await expectLater(
      repo.pay(
        requestId: 'pay-cash-1',
        expenseId: expenseId,
        amount: 400000,
        method: 'cash',
      ),
      throwsStateError,
    );
    expect(await repo.pendingPayment(), isNull);

    await SqliteCashierShiftRepository(SalonDatabase.instance)
        .openShift(openingCash: 2000000);

    expect(
      await repo.pay(
        requestId: 'pay-cash-1',
        expenseId: expenseId,
        amount: 400000,
        method: 'cash',
      ),
      'pay-cash-1',
    );
    expect(
      await repo.pay(
        requestId: 'pay-cash-1',
        expenseId: expenseId,
        amount: 400000,
        method: 'cash',
      ),
      'pay-cash-1',
    );
    await expectLater(
      repo.pay(
        requestId: 'pay-cash-1',
        expenseId: expenseId,
        amount: 300000,
        method: 'cash',
      ),
      throwsStateError,
    );

    await repo.pay(
      requestId: 'pay-transfer-1',
      expenseId: expenseId,
      amount: 600000,
      method: 'transfer',
      reference: 'BANK-EXP-001',
    );
    final paid = await repo.document(expenseId);
    expect(paid.paid, 1000000);
    expect(paid.balance, 0);
    expect(paid.state, 'paid');

    final activeAgain = await repo.setCategoryActive(
      requestId: 'cat-enable-1',
      id: inactive.id,
      expectedRevision: inactive.revision,
      active: true,
    );
    final secondExpense = await repo.createExpense(
      requestId: 'expense-create-2',
      categoryId: activeAgain.id,
      date: fixed,
      payee: 'Người nhận khác',
      amount: 500000,
      reason: 'Chi phí khác',
    );
    await expectLater(
      repo.pay(
        requestId: 'pay-duplicate-ref',
        expenseId: secondExpense,
        amount: 100000,
        method: 'transfer',
        reference: 'bank-exp-001',
      ),
      throwsStateError,
    );
    expect(await repo.pendingPayment(), isNull);

    await repo.reversePayment(
      requestId: 'reverse-transfer-1',
      paymentId: 'pay-transfer-1',
      reason: 'Ngân hàng hoàn lại',
      reference: 'BANK-REFUND-001',
    );
    await repo.reversePayment(
      requestId: 'reverse-cash-1',
      paymentId: 'pay-cash-1',
      reason: 'Hoàn quỹ',
    );
    final unpaidAgain = await repo.document(expenseId);
    expect(unpaidAgain.paid, 0);
    expect(unpaidAgain.balance, 1000000);

    await repo.reverseExpense(
      requestId: 'reverse-expense-1',
      expenseId: expenseId,
      reason: 'Chứng từ lập nhầm',
    );
    final reversed = await repo.document(expenseId);
    expect(reversed.reversed, isTrue);
    expect(reversed.state, 'reversed');
    expect(reversed.balance, 0);

    await expectLater(
      repo.pay(
        requestId: 'pay-reversed',
        expenseId: expenseId,
        amount: 1,
        method: 'cash',
      ),
      throwsStateError,
    );

    final db = await SalonDatabase.instance.database;
    final cash = await db.query(
      'cash_movements',
      where: "id LIKE 'expense-cash-%'",
      orderBy: 'created_at,id',
    );
    expect(cash, hasLength(2));
    expect(cash.map((row) => row['movement_type']), containsAll(['out', 'in']));
    expect(cash.map((row) => row['amount']), everyElement(400000));

    final history = await repo.history(expenseId);
    expect(
      history.map((row) => row['operation']),
      containsAll([
        'expense_create',
        'expense_pay',
        'expense_payment_reverse',
        'expense_reverse',
      ]),
    );
  });

  test('pending payment is reconciled without inventing a receipt', () async {
    final repo = SqliteExpenseRepository(
      SalonDatabase.instance,
      SensitiveActionService(SalonDatabase.instance),
    );
    final db = await SalonDatabase.instance.database;
    await db.insert('app_settings', {
      'key': 'expense.pending_payment',
      'value': jsonEncode({
        'requestId': 'ghost-payment',
        'signature': 'ghost-signature',
        'operation': 'payment',
        'payload': <String, Object?>{},
      }),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(await repo.resolvePendingPayment('ghost-payment'), isFalse);
    expect(await repo.pendingPayment(), isNull);
    expect(
      await db.query(
        'expense_payments',
        where: 'id=?',
        whereArgs: ['ghost-payment'],
      ),
      isEmpty,
    );
  });

  test('schema 25 backup requires the expense ledger tables', () async {
    const service = BackupService();
    await SalonDatabase.instance.initialize();
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    final copy = await openDatabase(
      backup.filePath!,
      singleInstance: false,
    );
    try {
      await copy.execute('DROP TABLE expense_events');
    } finally {
      await copy.close();
    }
    final validation = await service.validateBackupFile(backup.filePath!);
    expect(validation.isValid, isFalse);
    expect(validation.message, contains('chi phí'));
    await File(backup.filePath!).delete();
  });
}
