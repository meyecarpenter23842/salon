import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/salon_database.dart';
import '../models/finance_workspace.dart';
import '../providers/data_backend_provider.dart';
import '../providers/repository_providers.dart';
import '../services/sensitive_action_service.dart';

final financeWorkspaceRepositoryProvider =
    Provider<FinanceWorkspaceRepository?>(
      (ref) => ref.watch(appDataBackendProvider) == AppDataBackend.fake
          ? null
          : FinanceWorkspaceRepository(
              SalonDatabase.instance,
              ref.watch(sensitiveActionServiceProvider),
            ),
    );

/// Read-only projection. All writes stay in the verified B1/B2 repositories.
class FinanceWorkspaceRepository {
  FinanceWorkspaceRepository(this.database, this.security);
  final SalonDatabase database;
  final SensitiveActionService security;
  Future<FinanceWorkspace> fetch() async {
    await security.authorizeExpenseAction('expense_read', 'workspace');
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      'workspace',
    );
    final db = await database.database;
    final result = await db.transaction((tx) async {
      final accounts = <FinanceAccount>[];
      final proofs = <FinanceProof>[];
      final events = <FinanceBook, List<Map<String, Object?>>>{};
      final pending = <FinanceBook, Map<String, Object?>>{};
      for (final book in FinanceBook.values) {
        final expense = book == FinanceBook.expense;
        final entries = await tx.query(
          expense ? 'expense_entries' : 'supplier_payable_obligations',
          orderBy:
              '${expense ? 'expense_date' : 'source_date'} DESC,created_at DESC,id',
        );
        final reversals = entries
            .where((r) => r['kind'] == 'reversal')
            .map((r) => r['original_id'])
            .toSet();
        final payments = await tx.query(
          expense ? 'expense_payments' : 'supplier_payments',
          orderBy: 'created_at DESC,id',
        );
        final allocations = expense
            ? <Map<String, Object?>>[]
            : await tx.query('supplier_payment_allocations');
        for (final p in payments) {
          proofs.add(
            FinanceProof(
              book,
              p,
              expense
                  ? {p['expense_id'] as String: p['amount'] as int}
                  : {
                      for (final a in allocations.where(
                        (a) => a['payment_id'] == p['id'],
                      ))
                        a['obligation_id'] as String: a['amount'] as int,
                    },
            ),
          );
        }
        final paid = <String, int>{};
        for (final p in proofs.where((p) => p.book == book)) {
          for (final a in p.allocations.entries) {
            paid.update(a.key, (v) => v + a.value, ifAbsent: () => a.value);
          }
        }
        for (final r in entries.where((r) => r['kind'] != 'reversal')) {
          accounts.add(
            FinanceAccount(
              book,
              r,
              paid[r['id']] ?? 0,
              reversals.contains(r['id']),
            ),
          );
        }
        events[book] = await tx.query(
          expense ? 'expense_events' : 'supplier_payable_events',
          orderBy: 'created_at DESC,rowid DESC',
        );
        final setting = await tx.query(
          'app_settings',
          where: 'key=?',
          whereArgs: [
            expense
                ? 'expense.pending_payment'
                : 'supplier_payable.pending_payment',
          ],
        );
        if (setting.isNotEmpty) {
          pending[book] = Map<String, Object?>.from(
            jsonDecode(setting.single['value'] as String) as Map,
          );
        }
      }
      return FinanceWorkspace(
        at: DateTime.now(),
        accounts: accounts,
        proofs: proofs,
        categories: await tx.query(
          'expense_categories',
          orderBy: 'is_active DESC,name',
        ),
        suppliers: await tx.query(
          'stock_suppliers',
          orderBy: 'is_active DESC,name',
        ),
        pending: pending,
        events: events,
      );
    });
    // A session can expire while reading a large ledger.
    await security.authorizeExpenseAction('expense_read', 'workspace');
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      'workspace',
    );
    return result;
  }
}
