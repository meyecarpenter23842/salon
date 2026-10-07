import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/finance_workspace.dart';
import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/models/supplier_payable.dart';
import 'package:salonmanager/core/repositories/finance_workspace_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_cashier_shift_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_expense_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_supplier_payable_repository.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/features/finance/presentation/finance_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async => SalonDatabase.instance.close());
  tearDown(() async => SalonDatabase.instance.close());
  test(
    'snapshot separates obligation dates, payment dates and signed allocations; preserves after restore',
    () async {
      final security = SensitiveActionService(SalonDatabase.instance);
      final expenses = SqliteExpenseRepository(
        SalonDatabase.instance,
        security,
        clock: () => DateTime(2026, 10, 7, 15),
      );
      final payables = SqliteSupplierPayableRepository(
        SalonDatabase.instance,
        security,
        clock: () => DateTime(2026, 10, 7, 15),
      );
      final report = FinanceWorkspaceRepository(
        SalonDatabase.instance,
        security,
      );
      final cat = await expenses.createCategory(
        requestId: 'cat',
        name: 'Thuê mặt bằng',
      );
      final expense = await expenses.createExpense(
        requestId: 'create',
        categoryId: cat.id,
        date: DateTime(2026, 9, 30),
        payee: 'Chủ nhà',
        amount: 1000,
        reason: 'Tháng 9',
      );
      final stock = StockDocumentRepository(SalonDatabase.instance, security);
      await stock.saveSupplier(
        const StockSupplier(id: 'ncc', name: 'Nhà cung cấp Việt'),
      );
      final a = await payables.createOpeningBalance(
        requestId: 'opening-a',
        supplierId: 'ncc',
        date: DateTime(2026, 9, 30),
        amount: 500,
        reason: 'Nợ cũ đã đối chiếu',
      );
      final b = await payables.createOpeningBalance(
        requestId: 'opening-b',
        supplierId: 'ncc',
        date: DateTime(2026, 10, 7),
        amount: 700,
        reason: 'Nợ cũ khác',
      );
      await SqliteCashierShiftRepository(
        SalonDatabase.instance,
      ).openShift(openingCash: 10000);
      await expenses.pay(
        requestId: 'expense-cash',
        expenseId: expense,
        amount: 400,
        method: 'cash',
      );
      await payables.pay(
        requestId: 'supplier-transfer',
        supplierId: 'ncc',
        allocations: [
          SupplierPaymentAllocationInput(obligationId: a, amount: 200),
          SupplierPaymentAllocationInput(obligationId: b, amount: 300),
        ],
        method: 'transfer',
        reference: 'VCB-139',
      );
      final snapshot = await report.fetch();
      final expenseFilter = FinanceFilter(
        book: FinanceBook.expense,
        from: DateTime(2026, 10, 7),
        to: DateTime(2026, 10, 7),
      );
      expect(snapshot.select(expenseFilter), isEmpty);
      expect(
        snapshot.flowTotal(expenseFilter, 'cash'),
        400,
      ); // old obligation paid today
      final supplierFilter = FinanceFilter(
        book: FinanceBook.supplier,
        from: DateTime(2026, 10, 7),
        to: DateTime(2026, 10, 7),
        state: 'unpaid',
      );
      expect(snapshot.select(supplierFilter), isEmpty);
      expect(
        snapshot.flowTotal(supplierFilter, 'transfer'),
        500,
      ); // status does not hide today's cash flow
      expect(snapshot.cashFlow(supplierFilter).single.allocations.length, 2);
      expect(snapshot.accounts.singleWhere((v) => v.id == b).balance, 400);
      final backup = await const BackupService().createBackup();
      expect(backup.success, isTrue, reason: backup.message);
      await payables.reversePayment(
        requestId: 'supplier-refund',
        paymentId: 'supplier-transfer',
        reason: 'Hoàn tiền đã nhận',
        reference: 'VCB-139-R',
      );
      final reversed = await report.fetch();
      expect(reversed.flowTotal(supplierFilter, 'transfer'), 0);
      expect(reversed.accounts.singleWhere((v) => v.id == a).balance, 500);
      expect(
        snapshot.flowTotal(supplierFilter, 'transfer'),
        500,
      ); // previous snapshot remains frozen
      await stock.saveSupplier(
        const StockSupplier(id: 'ncc', name: 'Tên đã đổi', isActive: false),
      );
      expect(
        (await report.fetch()).accounts.singleWhere((v) => v.id == a).name,
        'Nhà cung cấp Việt',
      );
      await expenses.reversePayment(
        requestId: 'expense-refund',
        paymentId: 'expense-cash',
        reason: 'Nhận tiền hoàn',
      );
      await expenses.reverseExpense(
        requestId: 'expense-reversal',
        expenseId: expense,
        reason: 'Hủy nghĩa vụ',
      );
      final cancelled = await report.fetch();
      expect(
        cancelled.accounts.singleWhere((v) => v.id == expense).state,
        'reversed',
      );
      expect(cancelled.flowTotal(expenseFilter, 'cash'), 0);
      final db = await SalonDatabase.instance.database;
      expect(
        (await db.query('cash_movements')).length,
        2,
      ); // two signed cash proofs, no report movement
      final restored = await const BackupService().restoreFromBackup(
        backup.filePath!,
      );
      expect(restored.success, isTrue, reason: restored.message);
      expect((await report.fetch()).flowTotal(supplierFilter, 'transfer'), 500);
      await SalonDatabase.instance.close();
      await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(
        (await report.fetch()).accounts
            .singleWhere((v) => v.id == expense)
            .paid,
        400,
      );
      final pdf = await buildFinancePdf(snapshot, supplierFilter);
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      final receipt = await buildFinancePdf(
        snapshot,
        supplierFilter,
        proof: snapshot.proofs.singleWhere((p) => p.id == 'supplier-transfer'),
      );
      expect(receipt.length, greaterThan(1000));
      if (Platform.isLinux) {
        final output = Directory('build/mobile-ui-review')
          ..createSync(recursive: true);
        await File('${output.path}/finance-statement.pdf').writeAsBytes(pdf);
        await File('${output.path}/finance-receipt.pdf').writeAsBytes(receipt);
      }
    },
  );
  test(
    'report reads every obligation and receipt beyond existing domain page caps',
    () async {
      final security = SensitiveActionService(SalonDatabase.instance);
      final repo = SqliteExpenseRepository(SalonDatabase.instance, security);
      final cat = await repo.createCategory(
        requestId: 'category',
        name: 'Điện nước',
      );
      final db = await SalonDatabase.instance.database;
      await db.transaction((tx) async {
        for (var i = 0; i < 501; i++) {
          await tx.insert('expense_entries', {
            'id': 'expense-$i',
            'kind': 'expense',
            'category_id': cat.id,
            'category_name': cat.name,
            'expense_date': '2026-10-07T23:59:59.000',
            'payee': '',
            'amount': 1000,
            'reason': 'Test',
            'external_reference': '',
            'actor': 'Owner',
            'signature': 'fixture-$i',
            'created_at': '2026-10-07T23:59:59.000',
          });
          await tx.insert('expense_payments', {
            'id': 'receipt-$i',
            'expense_id': 'expense-$i',
            'kind': 'payment',
            'amount': 1,
            'method': 'transfer',
            'reference': 'TEST-$i',
            'note': '',
            'actor': 'Owner',
            'signature': 'fixture-$i',
            'created_at': '2026-10-07T23:59:59.000',
          });
        }
      });
      final snapshot = await FinanceWorkspaceRepository(
        SalonDatabase.instance,
        security,
      ).fetch();
      final filter = FinanceFilter(
        book: FinanceBook.expense,
        to: DateTime(2026, 10, 7),
      );
      expect(snapshot.select(filter).length, 501);
      expect(snapshot.flowTotal(filter, 'transfer'), 501);
      expect(
        snapshot.accounts.fold<int>(0, (s, a) => s + a.balance),
        501 * 999,
      );
    },
  );
  test('protected report cannot read without active Owner', () async {
    final security = _LockedSecurity();
    await expectLater(
      FinanceWorkspaceRepository(SalonDatabase.instance, security).fetch(),
      throwsStateError,
    );
  });
}

class _LockedSecurity extends SensitiveActionService {
  _LockedSecurity() : super(SalonDatabase.instance);
  @override
  Future<String> authorizeExpenseAction(String action, String targetId) async =>
      throw StateError('Owner required');
}
