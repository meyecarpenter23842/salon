import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/expense.dart';
import '../services/sensitive_action_service.dart';

const expenseMoneyLimit = 9000000000000;

class SqliteExpenseRepository {
  SqliteExpenseRepository(
    this.database,
    this.security, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static const _pendingKey = 'expense.pending_payment';

  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;

  Future<ExpenseSnapshot> fetch({
    String query = '',
    String? categoryId,
    String? status,
    DateTime? from,
    DateTime? to,
    int offset = 0,
    int limit = 50,
  }) async {
    await security.authorizeExpenseAction('expense_read', 'ledger');
    final db = await database.database;
    return db.transaction((tx) async {
      final categories = await _categories(tx, includeInactive: true);
      final rows = await tx.query(
        'expense_entries',
        where: "kind='expense'",
        orderBy: 'expense_date DESC,created_at DESC,id',
      );
      final q = query.trim().toLowerCase();
      final accounts = <ExpenseAccount>[];
      for (final row in rows) {
        final entry = _entry(row);
        if (categoryId != null && entry.categoryId != categoryId) continue;
        if (from != null && entry.date.isBefore(from)) continue;
        if (to != null && entry.date.isAfter(to)) continue;
        if (q.isNotEmpty &&
            ![
              entry.categoryName,
              entry.payee,
              entry.reason,
              entry.externalReference,
            ].any((value) => value.toLowerCase().contains(q))) {
          continue;
        }
        final account = await _account(tx, row);
        if (status != null && account.state != status) continue;
        accounts.add(account);
      }
      final page = accounts
          .skip(offset < 0 ? 0 : offset)
          .take(limit.clamp(1, 500))
          .toList(growable: false);
      final payments = <ExpensePayment>[];
      for (final account in page) {
        final paymentRows = await tx.query(
          'expense_payments',
          where: 'expense_id=?',
          whereArgs: [account.expense.id],
          orderBy: 'created_at DESC,id',
        );
        payments.addAll(paymentRows.map(_payment));
      }
      return ExpenseSnapshot(
        categories: categories,
        accounts: page,
        payments: payments,
        pendingPayment: await _pending(tx),
      );
    });
  }

  Future<List<ExpenseCategory>> categories({
    bool includeInactive = true,
  }) async {
    await security.authorizeExpenseAction('expense_read', 'categories');
    final db = await database.database;
    return _categories(db, includeInactive: includeInactive);
  }

  Future<ExpenseAccount> document(String id) async {
    await security.authorizeExpenseAction('expense_read', id);
    final db = await database.database;
    return db.transaction((tx) async {
      final row = await _expenseRow(tx, id);
      return _account(tx, row);
    });
  }

  Future<List<Map<String, Object?>>> history(String id) async {
    await security.authorizeExpenseAction('expense_read', id);
    final db = await database.database;
    return db.query(
      'expense_events',
      where: 'target_id=?',
      whereArgs: [id],
      orderBy: 'created_at DESC,rowid DESC',
    );
  }

  Future<Map<String, Object?>?> pendingPayment() async {
    await security.authorizeExpenseAction('expense_read', 'pending');
    final db = await database.database;
    return _pending(db);
  }

  Future<ExpenseCategory> createCategory({
    required String requestId,
    required String name,
  }) async {
    _validateRequestId(requestId);
    final normalized = _normalizeName(name);
    final actor = await security.authorizeExpenseAction(
      'expense_category_create',
      requestId,
    );
    final signature = jsonEncode(['category_create', normalized]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        return _categoryById(tx, replay['target_id'] as String);
      }
      final duplicate = await tx.query(
        'expense_categories',
        where: 'normalized_name=?',
        whereArgs: [_nameKey(normalized)],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError(
          duplicate.single['is_active'] == 1
              ? 'Danh mục khoản chi đã tồn tại.'
              : 'Tên đã có trong danh mục ngừng dùng. Hãy bật lại.',
        );
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('expense_category'),
        'name': normalized,
        'normalized_name': _nameKey(normalized),
        'is_active': 1,
        'revision': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      await tx.insert('expense_categories', row);
      await _event(
        tx,
        requestId,
        signature,
        'category_create',
        'expense_category',
        row['id'] as String,
        actor,
        'Tạo danh mục khoản chi',
        null,
        row,
      );
      await _audit(
        tx,
        actor,
        'expense_category_create',
        'expense_category',
        row['id'] as String,
        normalized,
        now,
      );
      return _category(row);
    });
  }

  Future<ExpenseCategory> renameCategory({
    required String requestId,
    required String id,
    required int expectedRevision,
    required String name,
  }) async {
    _validateRequestId(requestId);
    final normalized = _normalizeName(name);
    final actor = await security.authorizeExpenseAction(
      'expense_category_rename',
      id,
    );
    final signature = jsonEncode([
      'category_rename',
      id,
      expectedRevision,
      normalized,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return _categoryById(tx, id);
      final old = await _categoryRow(tx, id);
      if (old['revision'] != expectedRevision) {
        throw StateError('Danh mục đã thay đổi. Tải lại trước khi sửa.');
      }
      final duplicate = await tx.query(
        'expense_categories',
        where: 'normalized_name=? AND id<>?',
        whereArgs: [_nameKey(normalized), id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw StateError('Tên danh mục khoản chi đã được sử dụng.');
      }
      final now = clock();
      final next = <String, Object?>{
        ...old,
        'name': normalized,
        'normalized_name': _nameKey(normalized),
        'revision': expectedRevision + 1,
        'updated_at': now.toIso8601String(),
      };
      await tx.update(
        'expense_categories',
        {
          'name': next['name'],
          'normalized_name': next['normalized_name'],
          'revision': next['revision'],
          'updated_at': next['updated_at'],
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await _event(
        tx,
        requestId,
        signature,
        'category_rename',
        'expense_category',
        id,
        actor,
        'Đổi tên danh mục khoản chi',
        old,
        next,
      );
      await _audit(
        tx,
        actor,
        'expense_category_rename',
        'expense_category',
        id,
        normalized,
        now,
      );
      return _category(next);
    });
  }

  Future<ExpenseCategory> setCategoryActive({
    required String requestId,
    required String id,
    required int expectedRevision,
    required bool active,
  }) async {
    _validateRequestId(requestId);
    final actor = await security.authorizeExpenseAction(
      'expense_category_active',
      id,
    );
    final signature = jsonEncode([
      'category_active',
      id,
      expectedRevision,
      active,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return _categoryById(tx, id);
      final old = await _categoryRow(tx, id);
      if (old['revision'] != expectedRevision) {
        throw StateError('Danh mục đã thay đổi. Tải lại trước khi sửa.');
      }
      final now = clock();
      final next = <String, Object?>{
        ...old,
        'is_active': active ? 1 : 0,
        'revision': expectedRevision + 1,
        'updated_at': now.toIso8601String(),
      };
      await tx.update(
        'expense_categories',
        {
          'is_active': next['is_active'],
          'revision': next['revision'],
          'updated_at': next['updated_at'],
        },
        where: 'id=?',
        whereArgs: [id],
      );
      await _event(
        tx,
        requestId,
        signature,
        'category_active',
        'expense_category',
        id,
        actor,
        active ? 'Bật lại danh mục khoản chi' : 'Ngừng dùng danh mục khoản chi',
        old,
        next,
      );
      await _audit(
        tx,
        actor,
        'expense_category_active',
        'expense_category',
        id,
        active ? 'active' : 'inactive',
        now,
      );
      return _category(next);
    });
  }

  Future<String> createExpense({
    required String requestId,
    required String categoryId,
    required DateTime date,
    required String payee,
    required int amount,
    required String reason,
    String externalReference = '',
  }) async {
    _validateRequestId(requestId);
    final normalizedPayee = payee.trim();
    final normalizedReason = reason.trim();
    final normalizedReference = externalReference.trim();
    if (amount <= 0 ||
        amount > expenseMoneyLimit ||
        normalizedPayee.length > 200 ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        normalizedReference.length > 200) {
      throw ArgumentError('Thông tin khoản chi không hợp lệ.');
    }
    final actor = await security.authorizeExpenseAction(
      'expense_create',
      requestId,
    );
    final signature = jsonEncode([
      'expense_create',
      categoryId,
      date.toIso8601String(),
      normalizedPayee,
      amount,
      normalizedReason,
      normalizedReference,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return replay['target_id'] as String;
      final category = await _categoryRow(tx, categoryId);
      if (category['is_active'] != 1) {
        throw StateError('Danh mục khoản chi đã ngừng sử dụng.');
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('expense'),
        'kind': 'expense',
        'original_id': null,
        'category_id': categoryId,
        'category_name': category['name'],
        'expense_date': date.toIso8601String(),
        'payee': normalizedPayee,
        'amount': amount,
        'reason': normalizedReason,
        'external_reference': normalizedReference,
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('expense_entries', row);
      await _event(
        tx,
        requestId,
        signature,
        'expense_create',
        'expense',
        row['id'] as String,
        actor,
        normalizedReason,
        null,
        row,
      );
      await _audit(
        tx,
        actor,
        'expense_create',
        'expense',
        row['id'] as String,
        '$amount VND',
        now,
      );
      return row['id'] as String;
    });
  }

  Future<String> pay({
    required String requestId,
    required String expenseId,
    required int amount,
    required String method,
    String reference = '',
    String note = '',
  }) async {
    _validateRequestId(requestId);
    final normalizedReference = reference.trim();
    final normalizedNote = note.trim();
    if (amount <= 0 ||
        amount > expenseMoneyLimit ||
        !['cash', 'transfer'].contains(method) ||
        normalizedReference.length > 200 ||
        normalizedNote.length > 2000) {
      throw ArgumentError('Thông tin thanh toán chi phí không hợp lệ.');
    }
    if (method == 'transfer' && normalizedReference.isEmpty) {
      throw ArgumentError('Nhập mã giao dịch chuyển khoản.');
    }
    final signature = jsonEncode([
      'expense_pay',
      expenseId,
      amount,
      method,
      normalizedReference,
      normalizedNote,
    ]);
    final actor = await security.authorizeExpenseAction(
      'expense_pay',
      requestId,
    );
    final db = await database.database;
    final existing = await db.query(
      'expense_payments',
      where: 'id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      _verifyProof(existing.single, signature, 'payment');
      return requestId;
    }
    await _ensureExternalRequestIdAvailable(db, requestId);
    await _preparePending(
      db,
      requestId,
      signature,
      'payment',
      {
        'expenseId': expenseId,
        'amount': amount,
        'method': method,
        'reference': normalizedReference,
        'note': normalizedNote,
      },
    );
    try {
      return await db.transaction((tx) async {
        await _requirePending(tx, requestId, signature);
        final replay = await tx.query(
          'expense_payments',
          where: 'id=?',
          whereArgs: [requestId],
          limit: 1,
        );
        if (replay.isNotEmpty) {
          _verifyProof(replay.single, signature, 'payment');
          await _clearPending(tx, requestId);
          return requestId;
        }
        final row = await _expenseRow(tx, expenseId);
        if (await _isReversed(tx, expenseId)) {
          throw StateError('Khoản chi đã được đảo.');
        }
        final paid = await _paid(tx, expenseId);
        final balance = (row['amount'] as int) - paid;
        if (amount > balance) {
          throw StateError('Số trả vượt số còn phải trả. Tải lại sổ chi phí.');
        }
        if (method == 'transfer') {
          await _ensureTransferReferenceAvailable(tx, normalizedReference);
        }
        final now = clock();
        String? cashMovementId;
        if (method == 'cash') {
          final shift = await tx.query(
            'cashier_shifts',
            where: 'closed_at IS NULL',
            limit: 1,
          );
          if (shift.isEmpty) {
            throw StateError('Mở ca thu ngân trước khi chi tiền mặt.');
          }
          cashMovementId = 'expense-cash-$requestId';
          await tx.insert('cash_movements', {
            'id': cashMovementId,
            'shift_id': shift.single['id'],
            'movement_type': 'out',
            'amount': amount,
            'reason': 'Chi phí ${row['category_name']} · $requestId',
            'created_at': now.toIso8601String(),
          });
        }
        final proof = <String, Object?>{
          'id': requestId,
          'expense_id': expenseId,
          'kind': 'payment',
          'original_payment_id': null,
          'amount': amount,
          'method': method,
          'reference': normalizedReference,
          'note': normalizedNote,
          'actor': actor,
          'cash_movement_id': cashMovementId,
          'signature': signature,
          'created_at': now.toIso8601String(),
        };
        await tx.insert('expense_payments', proof);
        await _event(
          tx,
          requestId,
          signature,
          'expense_pay',
          'expense',
          expenseId,
          actor,
          '$amount VND; $method',
          null,
          proof,
        );
        await _audit(
          tx,
          actor,
          'expense_pay',
          'expense',
          expenseId,
          '$amount VND; $method',
          now,
        );
        await _clearPending(tx, requestId);
        return requestId;
      });
    } catch (_) {
      await _clearRejectedPending(db, requestId, signature);
      rethrow;
    }
  }

  Future<String> reversePayment({
    required String requestId,
    required String paymentId,
    required String reason,
    String reference = '',
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = reason.trim();
    final normalizedReference = reference.trim();
    if (normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        normalizedReference.length > 200) {
      throw ArgumentError('Nhập lý do đảo thanh toán hợp lệ.');
    }
    final signature = jsonEncode([
      'expense_payment_reverse',
      paymentId,
      normalizedReason,
      normalizedReference,
    ]);
    final actor = await security.authorizeExpenseAction(
      'expense_payment_reverse',
      requestId,
    );
    final db = await database.database;
    final existing = await db.query(
      'expense_payments',
      where: 'id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      _verifyProof(existing.single, signature, 'reversal');
      return requestId;
    }
    await _ensureExternalRequestIdAvailable(db, requestId);
    await _preparePending(
      db,
      requestId,
      signature,
      'reversal',
      {
        'paymentId': paymentId,
        'reason': normalizedReason,
        'reference': normalizedReference,
      },
    );
    try {
      return await db.transaction((tx) async {
        await _requirePending(tx, requestId, signature);
        final replay = await tx.query(
          'expense_payments',
          where: 'id=?',
          whereArgs: [requestId],
          limit: 1,
        );
        if (replay.isNotEmpty) {
          _verifyProof(replay.single, signature, 'reversal');
          await _clearPending(tx, requestId);
          return requestId;
        }
        final originals = await tx.query(
          'expense_payments',
          where: "id=? AND kind='payment'",
          whereArgs: [paymentId],
          limit: 1,
        );
        if (originals.isEmpty) {
          throw StateError('Không tìm thấy chứng từ thanh toán gốc.');
        }
        final original = originals.single;
        final already = await tx.query(
          'expense_payments',
          where: "kind='reversal' AND original_payment_id=?",
          whereArgs: [paymentId],
          limit: 1,
        );
        if (already.isNotEmpty) {
          throw StateError('Chứng từ thanh toán đã được đảo.');
        }
        final method = original['method'] as String;
        if (method == 'transfer' && normalizedReference.isEmpty) {
          throw ArgumentError('Đảo chuyển khoản cần mã giao dịch đối soát.');
        }
        if (method == 'transfer') {
          await _ensureTransferReferenceAvailable(tx, normalizedReference);
        }
        final now = clock();
        String? cashMovementId;
        final amount = original['amount'] as int;
        if (method == 'cash') {
          final shift = await tx.query(
            'cashier_shifts',
            where: 'closed_at IS NULL',
            limit: 1,
          );
          if (shift.isEmpty) {
            throw StateError('Mở ca thu ngân trước khi ghi hoàn tiền mặt.');
          }
          cashMovementId = 'expense-cash-$requestId';
          await tx.insert('cash_movements', {
            'id': cashMovementId,
            'shift_id': shift.single['id'],
            'movement_type': 'in',
            'amount': amount,
            'reason': 'Đảo chi phí · $paymentId',
            'created_at': now.toIso8601String(),
          });
        }
        final proof = <String, Object?>{
          'id': requestId,
          'expense_id': original['expense_id'],
          'kind': 'reversal',
          'original_payment_id': paymentId,
          'amount': -amount,
          'method': method,
          'reference': method == 'transfer' ? normalizedReference : '',
          'note': normalizedReason,
          'actor': actor,
          'cash_movement_id': cashMovementId,
          'signature': signature,
          'created_at': now.toIso8601String(),
        };
        await tx.insert('expense_payments', proof);
        final expenseId = original['expense_id'] as String;
        await _event(
          tx,
          requestId,
          signature,
          'expense_payment_reverse',
          'expense',
          expenseId,
          actor,
          normalizedReason,
          original,
          proof,
        );
        await _audit(
          tx,
          actor,
          'expense_payment_reverse',
          'expense',
          expenseId,
          normalizedReason,
          now,
        );
        await _clearPending(tx, requestId);
        return requestId;
      });
    } catch (_) {
      await _clearRejectedPending(db, requestId, signature);
      rethrow;
    }
  }

  Future<String> reverseExpense({
    required String requestId,
    required String expenseId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 2000) {
      throw ArgumentError('Nhập lý do đảo khoản chi.');
    }
    final actor = await security.authorizeExpenseAction(
      'expense_reverse',
      expenseId,
    );
    final signature = jsonEncode([
      'expense_reverse',
      expenseId,
      normalizedReason,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return replay['target_id'] as String;
      final original = await _expenseRow(tx, expenseId);
      if (await _isReversed(tx, expenseId)) {
        throw StateError('Khoản chi đã được đảo.');
      }
      if (await _paid(tx, expenseId) != 0) {
        throw StateError(
          'Đảo hết chứng từ thanh toán trước khi đảo khoản chi.',
        );
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('expense_reversal'),
        'kind': 'reversal',
        'original_id': expenseId,
        'category_id': original['category_id'],
        'category_name': original['category_name'],
        'expense_date': now.toIso8601String(),
        'payee': original['payee'],
        'amount': -(original['amount'] as int),
        'reason': normalizedReason,
        'external_reference': original['external_reference'],
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('expense_entries', row);
      await _event(
        tx,
        requestId,
        signature,
        'expense_reverse',
        'expense',
        expenseId,
        actor,
        normalizedReason,
        original,
        row,
      );
      await _audit(
        tx,
        actor,
        'expense_reverse',
        'expense',
        expenseId,
        normalizedReason,
        now,
      );
      return row['id'] as String;
    });
  }

  Future<bool> resolvePendingPayment(String requestId) async {
    _validateRequestId(requestId);
    final actor = await security.authorizeExpenseAction(
      'expense_resolve',
      requestId,
    );
    final db = await database.database;
    return db.transaction((tx) async {
      final pending = await _pending(tx);
      final proof = await tx.query(
        'expense_payments',
        where: 'id=?',
        whereArgs: [requestId],
        limit: 1,
      );
      if (pending == null) return proof.isNotEmpty;
      if (pending['requestId'] != requestId) {
        throw StateError('Yêu cầu thanh toán đang chờ đã thay đổi.');
      }
      await _clearPending(tx, requestId);
      final now = clock();
      await _audit(
        tx,
        actor,
        'expense_resolve',
        'expense_payment',
        requestId,
        proof.isEmpty
            ? 'Đã kiểm tra: chưa ghi chứng từ; bỏ yêu cầu'
            : 'Đã đối chiếu chứng từ đã ghi',
        now,
      );
      return proof.isNotEmpty;
    });
  }

  Future<List<ExpenseCategory>> _categories(
    DatabaseExecutor db, {
    required bool includeInactive,
  }) async {
    final rows = await db.query(
      'expense_categories',
      where: includeInactive ? null : 'is_active=1',
      orderBy: 'is_active DESC,name COLLATE NOCASE,id',
    );
    return rows.map(_category).toList(growable: false);
  }

  Future<Map<String, Object?>> _categoryRow(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'expense_categories',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy danh mục khoản chi.');
    return rows.single;
  }

  Future<ExpenseCategory> _categoryById(
    DatabaseExecutor db,
    String id,
  ) async {
    return _category(await _categoryRow(db, id));
  }

  Future<Map<String, Object?>> _expenseRow(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'expense_entries',
      where: "id=? AND kind='expense'",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy khoản chi.');
    return rows.single;
  }

  Future<ExpenseAccount> _account(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    return ExpenseAccount(
      expense: _entry(row),
      paid: await _paid(db, row['id'] as String),
      reversed: await _isReversed(db, row['id'] as String),
    );
  }

  Future<int> _paid(DatabaseExecutor db, String expenseId) async {
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) total FROM expense_payments WHERE expense_id=?',
      [expenseId],
    );
    final value = rows.single['total'];
    return value is int ? value : int.tryParse(value.toString()) ?? 0;
  }

  Future<bool> _isReversed(DatabaseExecutor db, String expenseId) async {
    final rows = await db.query(
      'expense_entries',
      columns: const ['id'],
      where: "kind='reversal' AND original_id=?",
      whereArgs: [expenseId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, Object?>?> _pending(DatabaseExecutor db) async {
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key=?',
      whereArgs: const [_pendingKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(
      jsonDecode(rows.single['value'] as String) as Map,
    );
  }

  Future<void> _preparePending(
    Database db,
    String requestId,
    String signature,
    String operation,
    Map<String, Object?> payload,
  ) async {
    await db.transaction((tx) async {
      final current = await _pending(tx);
      if (current != null) {
        if (current['requestId'] != requestId ||
            current['signature'] != signature) {
          throw StateError(
            'Có chứng từ tiền đang chờ đối chiếu. Mở lại chứng từ đó trước.',
          );
        }
        return;
      }
      await tx.insert('app_settings', {
        'key': _pendingKey,
        'value': jsonEncode({
          'requestId': requestId,
          'signature': signature,
          'operation': operation,
          'payload': payload,
        }),
        'updated_at': clock().toIso8601String(),
      });
    });
  }

  Future<void> _requirePending(
    DatabaseExecutor db,
    String requestId,
    String signature,
  ) async {
    final current = await _pending(db);
    if (current == null ||
        current['requestId'] != requestId ||
        current['signature'] != signature) {
      throw StateError(
        'Yêu cầu đã được đối chiếu hoặc thay đổi. Tải lại sổ chi phí.',
      );
    }
  }

  Future<void> _clearPending(
    DatabaseExecutor db,
    String requestId,
  ) async {
    final current = await _pending(db);
    if (current != null && current['requestId'] == requestId) {
      await db.delete(
        'app_settings',
        where: 'key=?',
        whereArgs: const [_pendingKey],
      );
    }
  }

  Future<void> _clearRejectedPending(
    Database db,
    String requestId,
    String signature,
  ) async {
    try {
      await db.transaction((tx) async {
        final proof = await tx.query(
          'expense_payments',
          where: 'id=?',
          whereArgs: [requestId],
          limit: 1,
        );
        if (proof.isNotEmpty) return;
        final current = await _pending(tx);
        if (current != null &&
            current['requestId'] == requestId &&
            current['signature'] == signature) {
          await tx.delete(
            'app_settings',
            where: 'key=?',
            whereArgs: const [_pendingKey],
          );
        }
      });
    } catch (_) {
      // If reconciliation itself is uncertain, keep the pending marker.
    }
  }

  Future<void> _ensureExternalRequestIdAvailable(
    DatabaseExecutor db,
    String requestId,
  ) async {
    final rows = await db.query(
      'supplier_payments',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw StateError(
        'Mã yêu cầu đã được dùng cho chứng từ thanh toán NCC.',
      );
    }
  }

  Future<void> _ensureTransferReferenceAvailable(
    DatabaseExecutor db,
    String reference,
  ) async {
    for (final table in [
      'expense_payments',
      'supplier_payments',
      'commission_payouts',
      'payroll_payouts',
    ]) {
      final rows = await db.query(
        table,
        columns: const ['id'],
        where: "method='transfer' AND reference=? COLLATE NOCASE",
        whereArgs: [reference],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        throw StateError(
          'Mã chuyển khoản đã được dùng cho chứng từ tiền khác. Đối chiếu chứng từ cũ.',
        );
      }
    }
  }

  Future<Map<String, Object?>?> _replay(
    DatabaseExecutor db,
    String requestId,
    String signature,
  ) async {
    final rows = await db.query(
      'expense_events',
      where: 'request_id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    if (rows.single['signature'] != signature) {
      throw StateError('Mã yêu cầu đã được dùng cho thao tác khác.');
    }
    return rows.single;
  }

  void _verifyProof(
    Map<String, Object?> proof,
    String signature,
    String kind,
  ) {
    if (proof['signature'] != signature || proof['kind'] != kind) {
      throw StateError('Mã yêu cầu đã được dùng cho chứng từ tiền khác.');
    }
  }

  Future<void> _event(
    DatabaseExecutor db,
    String requestId,
    String signature,
    String operation,
    String targetType,
    String targetId,
    String actor,
    String detail,
    Map<String, Object?>? before,
    Map<String, Object?> after,
  ) {
    return db.insert('expense_events', {
      'request_id': requestId,
      'operation': operation,
      'target_type': targetType,
      'target_id': targetId,
      'signature': signature,
      'actor': actor,
      'detail': detail,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': clock().toIso8601String(),
    });
  }

  Future<void> _audit(
    DatabaseExecutor db,
    String actor,
    String action,
    String targetType,
    String targetId,
    String detail,
    DateTime now,
  ) {
    return db.insert('audit_events', {
      'id': EntityId.create('expense_audit'),
      'actor_name': actor,
      'action': action,
      'target_type': targetType,
      'target_id': targetId,
      'result': 'success',
      'detail': detail,
      'created_at': now.toIso8601String(),
    });
  }

  ExpenseCategory _category(Map<String, Object?> row) {
    return ExpenseCategory(
      id: row['id'] as String,
      name: row['name'] as String,
      isActive: row['is_active'] == 1,
      revision: row['revision'] as int,
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  ExpenseEntry _entry(Map<String, Object?> row) {
    return ExpenseEntry(
      id: row['id'] as String,
      kind: row['kind'] as String,
      originalId: row['original_id'] as String?,
      categoryId: row['category_id'] as String,
      categoryName: row['category_name'] as String,
      date: DateTime.parse(row['expense_date'] as String),
      payee: row['payee'] as String,
      amount: row['amount'] as int,
      reason: row['reason'] as String,
      externalReference: row['external_reference'] as String,
      actor: row['actor'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  ExpensePayment _payment(Map<String, Object?> row) {
    return ExpensePayment(
      id: row['id'] as String,
      expenseId: row['expense_id'] as String,
      kind: row['kind'] as String,
      originalPaymentId: row['original_payment_id'] as String?,
      amount: row['amount'] as int,
      method: row['method'] as String,
      reference: row['reference'] as String,
      note: row['note'] as String,
      actor: row['actor'] as String,
      cashMovementId: row['cash_movement_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  String _normalizeName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || normalized.length > 120) {
      throw ArgumentError('Tên danh mục khoản chi không hợp lệ.');
    }
    return normalized;
  }

  String _nameKey(String value) => value.toLowerCase();

  void _validateRequestId(String requestId) {
    if (requestId.trim().isEmpty || requestId.length > 200) {
      throw ArgumentError('Mã yêu cầu không hợp lệ.');
    }
  }
}
