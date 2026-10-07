import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/models/supplier_payable.dart';
import 'package:salonmanager/core/repositories/sqlite_cashier_shift_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_expense_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_supplier_payable_repository.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SensitiveActionService security;
  late StockDocumentRepository stock;
  late SqliteSupplierPayableRepository payables;

  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.initialize();
    security = SensitiveActionService(SalonDatabase.instance);
    stock = StockDocumentRepository(SalonDatabase.instance, security);
    payables = SqliteSupplierPayableRepository(
      SalonDatabase.instance,
      security,
      clock: () => DateTime(2026, 10, 7, 12),
    );
    const stamp = '2026-10-07T08:00:00.000';
    await db.insert('retail_products', {
      'id': 'p1',
      'name': 'Dầu test',
      'brand': '',
      'volume_label': '500 ml',
      'unit_name': 'Chai',
      'product_type': 'Gội',
      'sale_price': 100000,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await stock.saveSupplier(
      const StockSupplier(
        id: 'supplier',
        name: 'NCC A',
        phone: '0900000001',
      ),
    );
    await stock.saveSupplier(
      const StockSupplier(
        id: 'supplier-b',
        name: 'NCC B',
        phone: '0900000002',
      ),
    );
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  Future<StockDocument> postReceipt(
    String id, {
    String? supplierId = 'supplier',
    int quantity = 3,
    int unitCost = 1000,
  }) async {
    final draft = await stock.saveDraft(
      StockDocumentInput(
        id: id,
        kind: StockDocumentKind.receipt,
        date: DateTime(2026, 10, 7),
        preparedBy: 'Owner',
        supplierId: supplierId,
        lines: [
          StockDocumentLineInput(
            productId: 'p1',
            quantity: quantity,
            unitCost: unitCost,
          ),
        ],
      ),
    );
    return stock.post(draft.id, expectedRevision: draft.revision);
  }

  test(
    'new posted PN creates one payable atomically; no supplier/zero/retry do not invent debt',
    () async {
      final posted = await postReceipt('pn-auto');
      var snapshot = await payables.fetch();
      expect(snapshot.accounts, hasLength(1));
      final account = snapshot.accounts.single;
      expect(account.obligation.sourceType, 'stock_receipt');
      expect(account.obligation.sourceId, posted.id);
      expect(account.obligation.sourceNumber, posted.number);
      expect(account.obligation.supplierName, 'NCC A');
      expect(account.obligation.amount, 3000);
      expect(account.paid, 0);
      expect(account.balance, 3000);

      await stock.post('pn-auto', expectedRevision: posted.revision - 1);
      expect(
        await db.query(
          'supplier_payable_obligations',
          where: "kind='charge' AND source_id=?",
          whereArgs: ['pn-auto'],
        ),
        hasLength(1),
      );

      await postReceipt('pn-no-supplier', supplierId: null);
      await postReceipt('pn-zero', unitCost: 0);
      snapshot = await payables.fetch();
      expect(snapshot.accounts, hasLength(1));

      final rollbackDraft = await stock.saveDraft(
        StockDocumentInput(
          id: 'pn-rollback',
          kind: StockDocumentKind.receipt,
          date: DateTime(2026, 10, 7),
          preparedBy: 'Owner',
          supplierId: 'supplier',
          lines: const [
            StockDocumentLineInput(
              productId: 'p1',
              quantity: 2,
              unitCost: 500,
            ),
          ],
        ),
      );
      await db.execute(
        "CREATE TRIGGER fail_supplier_payable BEFORE INSERT ON "
        "supplier_payable_obligations WHEN NEW.source_id='pn-rollback' "
        "BEGIN SELECT RAISE(ABORT,'forced payable failure'); END",
      );
      await expectLater(
        stock.post(
          rollbackDraft.id,
          expectedRevision: rollbackDraft.revision,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await stock.document('pn-rollback')).isDraft, isTrue);
      expect(
        await db.query(
          'inventory_movements',
          where: 'document_id=?',
          whereArgs: ['pn-rollback'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'supplier_payable_obligations',
          where: 'source_id=?',
          whereArgs: ['pn-rollback'],
        ),
        isEmpty,
      );
      await db.execute('DROP TRIGGER fail_supplier_payable');
    },
  );

  test(
    'schema 25 migration keeps historical posted PN without backfilled payable',
    () async {
      const stamp = '2026-10-01T08:00:00.000';
      await db.insert('stock_documents', {
        'id': 'legacy-pn',
        'number': 'PN-LEGACY',
        'kind': 'receipt',
        'status': 'draft',
        'document_date': stamp,
        'supplier_id': 'supplier',
        'supplier_name': 'NCC A',
        'prepared_by': 'Owner',
        'external_reference': '',
        'note': 'Phiếu cũ',
        'request_signature': 'legacy',
        'revision': 1,
        'total': 2000,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await db.insert('stock_document_lines', {
        'id': 'legacy-line',
        'document_id': 'legacy-pn',
        'product_id': 'p1',
        'product_name': 'Dầu test',
        'unit_name': 'Chai',
        'quantity': 2,
        'unit_cost': 1000,
        'amount': 2000,
      });
      await db.update(
        'stock_documents',
        {
          'status': 'posted',
          'posted_by': 'Owner',
          'posted_at': stamp,
          'revision': 2,
          'updated_at': stamp,
        },
        where: 'id=?',
        whereArgs: ['legacy-pn'],
      );
      await db.insert('inventory_stock', {
        'product_id': 'p1',
        'stock_on_hand': 2,
        'updated_at': stamp,
      });
      await db.insert('inventory_movements', {
        'id': 'stock-doc-legacy-pn-legacy-line-post',
        'product_id': 'p1',
        'movement_type': 'receive',
        'quantity_delta': 2,
        'stock_before': 0,
        'stock_after': 2,
        'note': 'Phiếu cũ',
        'created_at': stamp,
        'document_id': 'legacy-pn',
        'document_line_id': 'legacy-line',
        'source': 'document',
      });

      await db.execute('DROP TRIGGER IF EXISTS supplier_cash_no_update');
      await db.execute('DROP TRIGGER IF EXISTS supplier_cash_no_delete');
      await db.execute('DROP TABLE supplier_payment_allocations');
      await db.execute('DROP TABLE supplier_payable_events');
      await db.execute('DROP TABLE supplier_payments');
      await db.execute('DROP TABLE supplier_payable_obligations');
      await db.execute('PRAGMA user_version=25');
      await db.update(
        'app_settings',
        {'value': '25'},
        where: 'key=?',
        whereArgs: ['schema_version'],
      );
      await SalonDatabase.instance.close();

      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(await db.getVersion(), DatabaseSchema.version);
      expect(await db.query('supplier_payable_obligations'), isEmpty);
      expect(
        (await db.query(
          'stock_documents',
          where: 'id=?',
          whereArgs: ['legacy-pn'],
        )).single['status'],
        'posted',
      );

      stock = StockDocumentRepository(SalonDatabase.instance, security);
      payables = SqliteSupplierPayableRepository(
        SalonDatabase.instance,
        security,
      );
      final cancelled = await stock.cancel(
        'legacy-pn',
        expectedRevision: 2,
        reason: 'Hủy phiếu cũ',
      );
      expect(cancelled.status, 'cancelled');
      expect(await db.query('supplier_payable_obligations'), isEmpty);
    },
  );

  test(
    'paid PN cannot cancel until payment reversal; cash proof and stock/AP rollback stay atomic',
    () async {
      final posted = await postReceipt('pn-paid');
      final account = (await payables.fetch()).accounts.single;
      await expectLater(
        payables.pay(
          requestId: 'supplier-cash-no-shift',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: account.obligation.id,
              amount: 1000,
            ),
          ],
          method: 'cash',
        ),
        throwsStateError,
      );
      expect(await payables.pendingPayment(), isNull);

      await SqliteCashierShiftRepository(
        SalonDatabase.instance,
      ).openShift(openingCash: 100000);

      await payables.pay(
        requestId: 'supplier-cash-pay',
        supplierId: 'supplier',
        allocations: [
          SupplierPaymentAllocationInput(
            obligationId: account.obligation.id,
            amount: 1000,
          ),
        ],
        method: 'cash',
      );
      expect(
        await payables.pay(
          requestId: 'supplier-cash-pay',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: account.obligation.id,
              amount: 1000,
            ),
          ],
          method: 'cash',
        ),
        'supplier-cash-pay',
      );
      expect(
        await db.query(
          'cash_movements',
          where: "id='supplier-cash-supplier-cash-pay'",
        ),
        hasLength(1),
      );
      final partial = await payables.document(account.obligation.id);
      expect(partial.paid, 1000);
      expect(partial.balance, 2000);
      expect(partial.state, 'partial');

      await expectLater(
        stock.cancel(
          posted.id,
          expectedRevision: posted.revision,
          reason: 'Hủy khi đã trả',
        ),
        throwsStateError,
      );
      expect((await stock.document(posted.id)).isPosted, isTrue);
      expect(
        await db.query(
          'inventory_movements',
          where: "document_id=? AND movement_type='reverse'",
          whereArgs: [posted.id],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'supplier_payable_obligations',
          where: "kind='reversal' AND original_id=?",
          whereArgs: [account.obligation.id],
        ),
        isEmpty,
      );

      await payables.reversePayment(
        requestId: 'supplier-cash-reverse',
        paymentId: 'supplier-cash-pay',
        reason: 'Hoàn quỹ trước khi hủy PN',
      );
      expect((await payables.document(account.obligation.id)).paid, 0);

      final cancelled = await stock.cancel(
        posted.id,
        expectedRevision: posted.revision,
        reason: 'Hủy sau đối soát',
      );
      expect(cancelled.status, 'cancelled');
      final reversed = await payables.document(account.obligation.id);
      expect(reversed.reversed, isTrue);
      expect(reversed.balance, 0);

      final cash = await db.query(
        'cash_movements',
        where: "id LIKE 'supplier-cash-%'",
        orderBy: 'created_at,id',
      );
      expect(cash, hasLength(2));
      expect(cash.map((row) => row['movement_type']), containsAll(['out', 'in']));
      expect(cash.map((row) => row['amount']), everyElement(1000));
    },
  );

  test(
    'opening balances allocate partially, reject overpay, replay exactly and block cross-ledger duplicates',
    () async {
      final first = await payables.createOpeningBalance(
        requestId: 'opening-a',
        supplierId: 'supplier',
        date: DateTime(2026, 10, 1),
        amount: 1000,
        reason: 'Nợ cũ đối chiếu',
      );
      final second = await payables.createOpeningBalance(
        requestId: 'opening-b',
        supplierId: 'supplier',
        date: DateTime(2026, 10, 1),
        amount: 600,
        reason: 'Nợ cũ số 2',
      );

      expect(
        await payables.pay(
          requestId: 'supplier-transfer-1',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: second,
              amount: 200,
            ),
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 400,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-SUP-001',
        ),
        'supplier-transfer-1',
      );
      expect(
        await payables.pay(
          requestId: 'supplier-transfer-1',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 400,
            ),
            SupplierPaymentAllocationInput(
              obligationId: second,
              amount: 200,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-SUP-001',
        ),
        'supplier-transfer-1',
      );

      await SalonDatabase.instance.close();
      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      security = SensitiveActionService(SalonDatabase.instance);
      stock = StockDocumentRepository(SalonDatabase.instance, security);
      payables = SqliteSupplierPayableRepository(
        SalonDatabase.instance,
        security,
        clock: () => DateTime(2026, 10, 7, 12),
      );
      expect(
        await payables.pay(
          requestId: 'supplier-transfer-1',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 400,
            ),
            SupplierPaymentAllocationInput(
              obligationId: second,
              amount: 200,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-SUP-001',
        ),
        'supplier-transfer-1',
      );
      expect((await payables.document(first)).balance, 600);
      expect((await payables.document(second)).balance, 400);

      await expectLater(
        payables.pay(
          requestId: 'supplier-transfer-1',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 300,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-SUP-001',
        ),
        throwsStateError,
      );

      await payables.reversePayment(
        requestId: 'supplier-transfer-reverse',
        paymentId: 'supplier-transfer-1',
        reason: 'Ngân hàng hoàn giao dịch',
        reference: 'BANK-SUP-REV-001',
      );
      expect((await payables.document(first)).balance, 1000);
      expect((await payables.document(second)).balance, 600);

      final reversible = await payables.createOpeningBalance(
        requestId: 'opening-reversible',
        supplierId: 'supplier',
        date: DateTime(2026, 10, 1),
        amount: 300,
        reason: 'Số dư nhập thử',
      );
      expect(
        await payables.createOpeningBalance(
          requestId: 'opening-reversible',
          supplierId: 'supplier',
          date: DateTime(2026, 10, 1),
          amount: 300,
          reason: 'Số dư nhập thử',
        ),
        reversible,
      );
      await expectLater(
        payables.createOpeningBalance(
          requestId: 'opening-reversible',
          supplierId: 'supplier',
          date: DateTime(2026, 10, 1),
          amount: 301,
          reason: 'Số dư nhập thử',
        ),
        throwsStateError,
      );
      final openingReversal = await payables.reverseOpeningBalance(
        requestId: 'opening-reversible-reverse',
        obligationId: reversible,
        reason: 'Nhập nhầm số dư',
      );
      expect(
        await payables.reverseOpeningBalance(
          requestId: 'opening-reversible-reverse',
          obligationId: reversible,
          reason: 'Nhập nhầm số dư',
        ),
        openingReversal,
      );
      expect((await payables.document(reversible)).state, 'reversed');

      await expectLater(
        payables.pay(
          requestId: 'supplier-overpay',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 1001,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-OVERPAY',
        ),
        throwsStateError,
      );
      expect(await payables.pendingPayment(), isNull);

      final expense = SqliteExpenseRepository(
        SalonDatabase.instance,
        security,
      );
      final category = await expense.createCategory(
        requestId: 'expense-category',
        name: 'Điện nước',
      );
      final expenseId = await expense.createExpense(
        requestId: 'expense-create',
        categoryId: category.id,
        date: DateTime(2026, 10, 7),
        payee: 'Điện lực',
        amount: 500,
        reason: 'Tiền điện',
      );
      await expense.pay(
        requestId: 'expense-proof',
        expenseId: expenseId,
        amount: 100,
        method: 'transfer',
        reference: 'BANK-EXP-001',
      );
      await expectLater(
        payables.pay(
          requestId: 'supplier-duplicate-expense-ref',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 100,
            ),
          ],
          method: 'transfer',
          reference: 'bank-exp-001',
        ),
        throwsStateError,
      );
      await expectLater(
        payables.pay(
          requestId: 'expense-proof',
          supplierId: 'supplier',
          allocations: [
            SupplierPaymentAllocationInput(
              obligationId: first,
              amount: 100,
            ),
          ],
          method: 'transfer',
          reference: 'BANK-SUP-X',
        ),
        throwsStateError,
      );

      await stock.saveSupplier(
        const StockSupplier(
          id: 'supplier',
          name: 'NCC A',
          phone: '0900000001',
          isActive: false,
        ),
      );
      await payables.pay(
        requestId: 'supplier-after-inactive',
        supplierId: 'supplier',
        allocations: [
          SupplierPaymentAllocationInput(
            obligationId: first,
            amount: 100,
          ),
        ],
        method: 'transfer',
        reference: 'BANK-SUP-002',
      );
      expect((await payables.document(first)).balance, 900);

      await expectLater(
        expense.pay(
          requestId: 'expense-same-supplier-request',
          expenseId: expenseId,
          amount: 50,
          method: 'transfer',
          reference: 'BANK-SUP-002',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'concurrent supplier payments cannot overpay latest balance',
    () async {
      final obligation = await payables.createOpeningBalance(
        requestId: 'opening-concurrent',
        supplierId: 'supplier',
        date: DateTime(2026, 10, 1),
        amount: 1000,
        reason: 'Nợ để thử đồng thời',
      );

      Future<Object> attempt(String requestId, String reference) async {
        try {
          return await payables.pay(
            requestId: requestId,
            supplierId: 'supplier',
            allocations: [
              SupplierPaymentAllocationInput(
                obligationId: obligation,
                amount: 1000,
              ),
            ],
            method: 'transfer',
            reference: reference,
          );
        } catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        attempt('supplier-concurrent-a', 'BANK-CON-A'),
        attempt('supplier-concurrent-b', 'BANK-CON-B'),
      ]);
      expect(results.whereType<String>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      final account = await payables.document(obligation);
      expect(account.paid, 1000);
      expect(account.balance, 0);
    },
  );

  test(
    'pending reconciliation, Owner lock and schema 26 backup stay explicit',
    () async {
      await db.insert('app_settings', {
        'key': 'supplier_payable.pending_payment',
        'value': jsonEncode({
          'requestId': 'ghost-supplier-pay',
          'signature': 'ghost-signature',
          'operation': 'payment',
          'payload': <String, Object?>{},
        }),
        'updated_at': DateTime.now().toIso8601String(),
      });
      await SalonDatabase.instance.close();
      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      security = SensitiveActionService(SalonDatabase.instance);
      payables = SqliteSupplierPayableRepository(
        SalonDatabase.instance,
        security,
      );
      expect(
        (await payables.pendingPayment())?['requestId'],
        'ghost-supplier-pay',
      );
      expect(
        await payables.resolvePendingPayment('ghost-supplier-pay'),
        isFalse,
      );
      expect(await payables.pendingPayment(), isNull);

      await security.configureOwnerPin('1234');
      security.lockOwnerSession();
      await expectLater(payables.fetch(), throwsStateError);
      expect(await security.unlockOwner('1234'), isTrue);
      expect((await payables.fetch()).accounts, isEmpty);

      const backupService = BackupService();
      final backup = await backupService.createBackup();
      expect(backup.success, isTrue, reason: backup.message);
      final copy = await openDatabase(
        backup.filePath!,
        singleInstance: false,
      );
      try {
        await copy.execute('DROP TABLE supplier_payable_events');
      } finally {
        await copy.close();
      }
      final validation = await backupService.validateBackupFile(
        backup.filePath!,
      );
      expect(validation.isValid, isFalse);
      expect(validation.message, contains('công nợ NCC'));
      await File(backup.filePath!).delete();
    },
  );
}
