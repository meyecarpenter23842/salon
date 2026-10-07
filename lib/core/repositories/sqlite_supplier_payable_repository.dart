import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/supplier_payable.dart';
import '../services/sensitive_action_service.dart';
import 'supplier_payable_ledger.dart';

const supplierPayableMoneyLimit = 9000000000000;

class SqliteSupplierPayableRepository {
  SqliteSupplierPayableRepository(
    this.database,
    this.security, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  static const _pendingKey = 'supplier_payable.pending_payment';

  final SalonDatabase database;
  final SensitiveActionService security;
  final DateTime Function() clock;

  Future<SupplierPayableSnapshot> fetch({
    String query = '',
    String? supplierId,
    String? status,
    DateTime? from,
    DateTime? to,
    int offset = 0,
    int limit = 50,
  }) async {
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      supplierId ?? 'ledger',
    );
    final db = await database.database;
    return db.transaction((tx) async {
      final rows = await tx.query(
        'supplier_payable_obligations',
        where: "kind='charge'",
        orderBy: 'source_date DESC,created_at DESC,id',
      );
      final normalizedQuery = query.trim().toLowerCase();
      final accounts = <SupplierPayableAccount>[];
      for (final row in rows) {
        final obligation = _obligation(row);
        if (supplierId != null && obligation.supplierId != supplierId) {
          continue;
        }
        if (from != null && obligation.sourceDate.isBefore(from)) continue;
        if (to != null && obligation.sourceDate.isAfter(to)) continue;
        if (normalizedQuery.isNotEmpty &&
            ![
              obligation.supplierName,
              obligation.sourceNumber,
              obligation.reason,
              obligation.externalReference,
            ].any(
              (value) => value.toLowerCase().contains(normalizedQuery),
            )) {
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
      final paymentRows = await tx.query(
        'supplier_payments',
        where: supplierId == null ? null : 'supplier_id=?',
        whereArgs: supplierId == null ? null : [supplierId],
        orderBy: 'created_at DESC,id',
        limit: 200,
      );
      final payments = <SupplierPayment>[];
      for (final row in paymentRows) {
        payments.add(await _payment(tx, row));
      }
      return SupplierPayableSnapshot(
        accounts: page,
        payments: payments,
        pendingPayment: await _pending(tx),
      );
    });
  }

  Future<SupplierPayableAccount> document(String obligationId) async {
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      obligationId,
    );
    final db = await database.database;
    return db.transaction((tx) async {
      final row = await _obligationRow(tx, obligationId);
      return _account(tx, row);
    });
  }

  Future<List<Map<String, Object?>>> history(String targetId) async {
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      targetId,
    );
    final db = await database.database;
    return db.query(
      'supplier_payable_events',
      where: 'target_id=?',
      whereArgs: [targetId],
      orderBy: 'created_at DESC,rowid DESC',
    );
  }

  Future<Map<String, Object?>?> pendingPayment() async {
    await security.authorizeSupplierPayableAction(
      'supplier_payable_read',
      'pending',
    );
    final db = await database.database;
    return _pending(db);
  }

  Future<String> createOpeningBalance({
    required String requestId,
    required String supplierId,
    required DateTime date,
    required int amount,
    required String reason,
    String externalReference = '',
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = reason.trim();
    final normalizedReference = externalReference.trim();
    if (amount <= 0 ||
        amount > supplierPayableMoneyLimit ||
        normalizedReason.isEmpty ||
        normalizedReason.length > 2000 ||
        normalizedReference.length > 200) {
      throw ArgumentError('Số dư đầu kỳ NCC không hợp lệ.');
    }
    final actor = await security.authorizeSupplierPayableAction(
      'supplier_payable_opening',
      supplierId,
    );
    final signature = jsonEncode([
      'opening',
      supplierId,
      date.toIso8601String(),
      amount,
      normalizedReason,
      normalizedReference,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) return replay['target_id'] as String;
      final supplier = await _supplierRow(tx, supplierId, requireActive: true);
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('supplier_opening'),
        'kind': 'charge',
        'original_id': null,
        'supplier_id': supplierId,
        'supplier_name': supplier['name'],
        'source_type': 'opening',
        'source_id': null,
        'source_number': 'Số dư đầu kỳ',
        'source_date': date.toIso8601String(),
        'amount': amount,
        'reason': normalizedReason,
        'external_reference': normalizedReference,
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('supplier_payable_obligations', row);
      await _event(
        tx,
        requestId,
        signature,
        'opening_create',
        'supplier_payable',
        row['id'] as String,
        actor,
        normalizedReason,
        null,
        row,
        now,
      );
      await _audit(
        tx,
        actor,
        'supplier_payable_opening',
        row['id'] as String,
        '$amount VND; $normalizedReason',
        now,
      );
      return row['id'] as String;
    });
  }

  Future<String> reverseOpeningBalance({
    required String requestId,
    required String obligationId,
    required String reason,
  }) async {
    _validateRequestId(requestId);
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 2000) {
      throw ArgumentError('Nhập lý do đảo số dư đầu kỳ.');
    }
    final actor = await security.authorizeSupplierPayableAction(
      'supplier_payable_opening_reverse',
      obligationId,
    );
    final signature = jsonEncode([
      'opening_reverse',
      obligationId,
      normalizedReason,
    ]);
    final db = await database.database;
    return db.transaction((tx) async {
      final replay = await _replay(tx, requestId, signature);
      if (replay != null) {
        final after = Map<String, Object?>.from(
          jsonDecode(replay['after_json'] as String) as Map,
        );
        return after['id'] as String;
      }
      final original = await _obligationRow(tx, obligationId);
      if (original['source_type'] != 'opening') {
        throw StateError('Chỉ đảo số dư đầu kỳ bằng thao tác này.');
      }
      if (await _isReversed(tx, obligationId)) {
        throw StateError('Số dư đầu kỳ đã được đảo.');
      }
      if (await SupplierPayableLedger.allocatedAmount(tx, obligationId) != 0) {
        throw StateError(
          'Đảo/hoàn hết thanh toán trước khi đảo số dư đầu kỳ.',
        );
      }
      final now = clock();
      final row = <String, Object?>{
        'id': EntityId.create('supplier_opening_reversal'),
        'kind': 'reversal',
        'original_id': obligationId,
        'supplier_id': original['supplier_id'],
        'supplier_name': original['supplier_name'],
        'source_type': 'opening',
        'source_id': null,
        'source_number': original['source_number'],
        'source_date': original['source_date'],
        'amount': -(original['amount'] as int),
        'reason': normalizedReason,
        'external_reference': original['external_reference'],
        'actor': actor,
        'signature': signature,
        'created_at': now.toIso8601String(),
      };
      await tx.insert('supplier_payable_obligations', row);
      await _event(
        tx,
        requestId,
        signature,
        'opening_reverse',
        'supplier_payable',
        obligationId,
        actor,
        normalizedReason,
        original,
        row,
        now,
      );
      await _audit(
        tx,
        actor,
        'supplier_payable_opening_reverse',
        obligationId,
        normalizedReason,
        now,
      );
      return row['id'] as String;
    });
  }

  Future<String> pay({
    required String requestId,
    required String supplierId,
    required List<SupplierPaymentAllocationInput> allocations,
    required String method,
    String reference = '',
    String note = '',
  }) async {
    _validateRequestId(requestId);
    final normalizedAllocations = _normalizeAllocations(allocations);
    final total = _checkedTotal(
      normalizedAllocations.map((allocation) => allocation.amount),
    );
    final normalizedReference = reference.trim();
    final normalizedNote = note.trim();
    if (!['cash', 'transfer'].contains(method) ||
        normalizedReference.length > 200 ||
        normalizedNote.length > 2000) {
      throw ArgumentError('Thông tin thanh toán NCC không hợp lệ.');
    }
    if (method == 'transfer' && normalizedReference.isEmpty) {
      throw ArgumentError('Nhập mã giao dịch chuyển khoản.');
    }
    final signature = jsonEncode([
      'supplier_pay',
      supplierId,
      normalizedAllocations
          .map((allocation) => [allocation.obligationId, allocation.amount])
          .toList(),
      method,
      normalizedReference,
      normalizedNote,
    ]);
    final actor = await security.authorizeSupplierPayableAction(
      'supplier_payable_pay',
      requestId,
    );
    final db = await database.database;

    final committed = await _committedMoneyReplay(
      db,
      requestId,
      signature,
      'payment',
    );
    if (committed) {
      await db.transaction((tx) => _clearPending(tx, requestId));
      return requestId;
    }
    await _ensureExternalRequestIdAvailable(db, requestId);
    await _preparePending(
      db,
      requestId,
      signature,
      'payment',
      {
        'supplierId': supplierId,
        'allocations': normalizedAllocations
            .map(
              (allocation) => {
                'obligationId': allocation.obligationId,
                'amount': allocation.amount,
              },
            )
            .toList(),
        'method': method,
        'reference': normalizedReference,
        'note': normalizedNote,
      },
    );

    try {
      return await db.transaction((tx) async {
        if (await _committedMoneyReplay(
          tx,
          requestId,
          signature,
          'payment',
        )) {
          await _clearPending(tx, requestId);
          return requestId;
        }
        await _requirePending(tx, requestId, signature);
        final supplier = await _supplierRow(
          tx,
          supplierId,
          requireActive: false,
        );

        for (final allocation in normalizedAllocations) {
          final obligation = await _obligationRow(
            tx,
            allocation.obligationId,
          );
          if (obligation['supplier_id'] != supplierId) {
            throw StateError(
              'Khoản phân bổ không thuộc nhà cung cấp đã chọn.',
            );
          }
          if (await _isReversed(tx, allocation.obligationId)) {
            throw StateError('Khoản nợ đã được đảo.');
          }
          final paid = await SupplierPayableLedger.allocatedAmount(
            tx,
            allocation.obligationId,
          );
          final balance = (obligation['amount'] as int) - paid;
          if (allocation.amount > balance) {
            throw StateError(
              'Phân bổ vượt số còn nợ. Tải lại sổ công nợ.',
            );
          }
        }

        if (method == 'transfer') {
          await _ensureTransferReferenceAvailable(tx, normalizedReference);
        }
        final now = clock();
        String? movementId;
        if (method == 'cash') {
          final shift = await tx.query(
            'cashier_shifts',
            where: 'closed_at IS NULL',
            limit: 1,
          );
          if (shift.isEmpty) {
            throw StateError('Mở ca thu ngân trước khi trả NCC bằng tiền mặt.');
          }
          movementId = 'supplier-cash-$requestId';
          await tx.insert('cash_movements', {
            'id': movementId,
            'shift_id': shift.single['id'],
            'movement_type': 'out',
            'amount': total,
            'reason': 'Trả NCC ${supplier['name']} · $requestId',
            'created_at': now.toIso8601String(),
          });
        }

        final proof = <String, Object?>{
          'id': requestId,
          'supplier_id': supplierId,
          'supplier_name': supplier['name'],
          'kind': 'payment',
          'original_payment_id': null,
          'amount': total,
          'method': method,
          'reference': normalizedReference,
          'note': normalizedNote,
          'actor': actor,
          'cash_movement_id': movementId,
          'signature': signature,
          'created_at': now.toIso8601String(),
        };
        await tx.insert('supplier_payments', proof);
        final allocationRows = <Map<String, Object?>>[];
        for (final allocation in normalizedAllocations) {
          final row = <String, Object?>{
            'id': EntityId.create('supplier_allocation'),
            'payment_id': requestId,
            'obligation_id': allocation.obligationId,
            'amount': allocation.amount,
            'created_at': now.toIso8601String(),
          };
          await tx.insert('supplier_payment_allocations', row);
          allocationRows.add(row);
        }
        await _event(
          tx,
          requestId,
          signature,
          'supplier_pay',
          'supplier_payment',
          requestId,
          actor,
          '$total VND; $method',
          null,
          {
            'payment': proof,
            'allocations': allocationRows,
          },
          now,
        );
        await _audit(
          tx,
          actor,
          'supplier_payable_pay',
          requestId,
          '$total VND; $method; $supplierId',
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
      throw ArgumentError('Nhập lý do đảo thanh toán NCC.');
    }
    final signature = jsonEncode([
      'supplier_payment_reverse',
      paymentId,
      normalizedReason,
      normalizedReference,
    ]);
    final actor = await security.authorizeSupplierPayableAction(
      'supplier_payable_payment_reverse',
      requestId,
    );
    final db = await database.database;

    final committed = await _committedMoneyReplay(
      db,
      requestId,
      signature,
      'reversal',
    );
    if (committed) {
      await db.transaction((tx) => _clearPending(tx, requestId));
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
        if (await _committedMoneyReplay(
          tx,
          requestId,
          signature,
          'reversal',
        )) {
          await _clearPending(tx, requestId);
          return requestId;
        }
        await _requirePending(tx, requestId, signature);
        final originalRows = await tx.query(
          'supplier_payments',
          where: "id=? AND kind='payment'",
          whereArgs: [paymentId],
          limit: 1,
        );
        if (originalRows.isEmpty) {
          throw StateError('Không tìm thấy chứng từ thanh toán NCC gốc.');
        }
        final original = originalRows.single;
        final reversalRows = await tx.query(
          'supplier_payments',
          where: "kind='reversal' AND original_payment_id=?",
          whereArgs: [paymentId],
          limit: 1,
        );
        if (reversalRows.isNotEmpty) {
          throw StateError('Chứng từ thanh toán NCC đã được đảo.');
        }

        final method = original['method'] as String;
        if (method == 'transfer' && normalizedReference.isEmpty) {
          throw ArgumentError('Đảo chuyển khoản cần mã giao dịch đối soát.');
        }
        if (method == 'transfer') {
          await _ensureTransferReferenceAvailable(tx, normalizedReference);
        }

        final originalAllocations = await tx.query(
          'supplier_payment_allocations',
          where: 'payment_id=?',
          whereArgs: [paymentId],
          orderBy: 'id',
        );
        if (originalAllocations.isEmpty) {
          throw StateError('Chứng từ thanh toán không có phân bổ để đảo.');
        }

        final now = clock();
        final amount = original['amount'] as int;
        String? movementId;
        if (method == 'cash') {
          final shift = await tx.query(
            'cashier_shifts',
            where: 'closed_at IS NULL',
            limit: 1,
          );
          if (shift.isEmpty) {
            throw StateError(
              'Mở ca thu ngân trước khi ghi hoàn tiền NCC bằng tiền mặt.',
            );
          }
          movementId = 'supplier-cash-$requestId';
          await tx.insert('cash_movements', {
            'id': movementId,
            'shift_id': shift.single['id'],
            'movement_type': 'in',
            'amount': amount,
            'reason': 'Đảo trả NCC · $paymentId',
            'created_at': now.toIso8601String(),
          });
        }

        final proof = <String, Object?>{
          'id': requestId,
          'supplier_id': original['supplier_id'],
          'supplier_name': original['supplier_name'],
          'kind': 'reversal',
          'original_payment_id': paymentId,
          'amount': -amount,
          'method': method,
          'reference': method == 'transfer' ? normalizedReference : '',
          'note': normalizedReason,
          'actor': actor,
          'cash_movement_id': movementId,
          'signature': signature,
          'created_at': now.toIso8601String(),
        };
        await tx.insert('supplier_payments', proof);
        final reversedAllocations = <Map<String, Object?>>[];
        for (final originalAllocation in originalAllocations) {
          final row = <String, Object?>{
            'id': EntityId.create('supplier_allocation_reversal'),
            'payment_id': requestId,
            'obligation_id': originalAllocation['obligation_id'],
            'amount': -(originalAllocation['amount'] as int),
            'created_at': now.toIso8601String(),
          };
          await tx.insert('supplier_payment_allocations', row);
          reversedAllocations.add(row);
        }
        await _event(
          tx,
          requestId,
          signature,
          'supplier_payment_reverse',
          'supplier_payment',
          paymentId,
          actor,
          normalizedReason,
          original,
          {
            'payment': proof,
            'allocations': reversedAllocations,
          },
          now,
        );
        await _audit(
          tx,
          actor,
          'supplier_payable_payment_reverse',
          paymentId,
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

  Future<bool> resolvePendingPayment(String requestId) async {
    _validateRequestId(requestId);
    final actor = await security.authorizeSupplierPayableAction(
      'supplier_payable_resolve',
      requestId,
    );
    final db = await database.database;
    return db.transaction((tx) async {
      final pending = await _pending(tx);
      final proof = await tx.query(
        'supplier_payments',
        where: 'id=?',
        whereArgs: [requestId],
        limit: 1,
      );
      if (pending == null) return proof.isNotEmpty;
      if (pending['requestId'] != requestId) {
        throw StateError('Yêu cầu thanh toán NCC đang chờ đã thay đổi.');
      }
      await _clearPending(tx, requestId);
      await _audit(
        tx,
        actor,
        'supplier_payable_resolve',
        requestId,
        proof.isEmpty
            ? 'Đã kiểm tra: chưa ghi chứng từ; bỏ yêu cầu'
            : 'Đã đối chiếu chứng từ đã ghi',
        clock(),
      );
      return proof.isNotEmpty;
    });
  }

  Future<Map<String, Object?>> _supplierRow(
    DatabaseExecutor db,
    String supplierId, {
    required bool requireActive,
  }) async {
    final rows = await db.query(
      'stock_suppliers',
      where: requireActive ? 'id=? AND is_active=1' : 'id=?',
      whereArgs: [supplierId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        requireActive
            ? 'Nhà cung cấp không còn hoạt động.'
            : 'Không tìm thấy nhà cung cấp.',
      );
    }
    return rows.single;
  }

  Future<Map<String, Object?>> _obligationRow(
    DatabaseExecutor db,
    String obligationId,
  ) async {
    final rows = await db.query(
      'supplier_payable_obligations',
      where: "id=? AND kind='charge'",
      whereArgs: [obligationId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Không tìm thấy khoản nợ NCC.');
    return rows.single;
  }

  Future<SupplierPayableAccount> _account(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final id = row['id'] as String;
    return SupplierPayableAccount(
      obligation: _obligation(row),
      paid: await SupplierPayableLedger.allocatedAmount(db, id),
      reversed: await _isReversed(db, id),
    );
  }

  Future<bool> _isReversed(
    DatabaseExecutor db,
    String obligationId,
  ) async {
    final rows = await db.query(
      'supplier_payable_obligations',
      columns: const ['id'],
      where: "kind='reversal' AND original_id=?",
      whereArgs: [obligationId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<SupplierPayment> _payment(
    DatabaseExecutor db,
    Map<String, Object?> row,
  ) async {
    final allocationRows = await db.query(
      'supplier_payment_allocations',
      where: 'payment_id=?',
      whereArgs: [row['id']],
      orderBy: 'id',
    );
    return SupplierPayment(
      id: row['id'] as String,
      supplierId: row['supplier_id'] as String,
      supplierName: row['supplier_name'] as String,
      kind: row['kind'] as String,
      originalPaymentId: row['original_payment_id'] as String?,
      amount: row['amount'] as int,
      method: row['method'] as String,
      reference: row['reference'] as String,
      note: row['note'] as String,
      actor: row['actor'] as String,
      cashMovementId: row['cash_movement_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      allocations: allocationRows
          .map(
            (allocation) => SupplierPaymentAllocation(
              id: allocation['id'] as String,
              paymentId: allocation['payment_id'] as String,
              obligationId: allocation['obligation_id'] as String,
              amount: allocation['amount'] as int,
            ),
          )
          .toList(growable: false),
    );
  }

  SupplierPayableObligation _obligation(Map<String, Object?> row) {
    return SupplierPayableObligation(
      id: row['id'] as String,
      kind: row['kind'] as String,
      originalId: row['original_id'] as String?,
      supplierId: row['supplier_id'] as String,
      supplierName: row['supplier_name'] as String,
      sourceType: row['source_type'] as String,
      sourceId: row['source_id'] as String?,
      sourceNumber: row['source_number'] as String,
      sourceDate: DateTime.parse(row['source_date'] as String),
      amount: row['amount'] as int,
      reason: row['reason'] as String,
      externalReference: row['external_reference'] as String,
      actor: row['actor'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  List<SupplierPaymentAllocationInput> _normalizeAllocations(
    List<SupplierPaymentAllocationInput> allocations,
  ) {
    if (allocations.isEmpty || allocations.length > 200) {
      throw ArgumentError('Thanh toán NCC phải có ít nhất một phân bổ.');
    }
    final seen = <String>{};
    final normalized = <SupplierPaymentAllocationInput>[];
    for (final allocation in allocations) {
      final obligationId = allocation.obligationId.trim();
      if (obligationId.isEmpty ||
          !seen.add(obligationId) ||
          allocation.amount <= 0 ||
          allocation.amount > supplierPayableMoneyLimit) {
        throw ArgumentError('Phân bổ thanh toán NCC không hợp lệ.');
      }
      normalized.add(
        SupplierPaymentAllocationInput(
          obligationId: obligationId,
          amount: allocation.amount,
        ),
      );
    }
    normalized.sort(
      (left, right) => left.obligationId.compareTo(right.obligationId),
    );
    return normalized;
  }

  int _checkedTotal(Iterable<int> values) {
    final total = values.fold<BigInt>(
      BigInt.zero,
      (sum, value) => sum + BigInt.from(value),
    );
    if (total <= BigInt.zero ||
        total > BigInt.from(supplierPayableMoneyLimit)) {
      throw ArgumentError('Tổng thanh toán NCC vượt giới hạn.');
    }
    return total.toInt();
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
            'Có chứng từ thanh toán NCC đang chờ đối chiếu.',
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
        'Yêu cầu thanh toán NCC đã được đối chiếu hoặc thay đổi.',
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
          'supplier_payments',
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
      // Keep pending if reconciliation itself is uncertain.
    }
  }

  Future<bool> _committedMoneyReplay(
    DatabaseExecutor db,
    String requestId,
    String signature,
    String kind,
  ) async {
    final event = await _replay(db, requestId, signature);
    final proof = await db.query(
      'supplier_payments',
      where: 'id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (event == null && proof.isEmpty) return false;
    if (event == null || proof.isEmpty) {
      throw StateError(
        'Nhật ký và chứng từ thanh toán NCC không khớp. Cần đối chiếu.',
      );
    }
    if (proof.single['signature'] != signature ||
        proof.single['kind'] != kind) {
      throw StateError('Mã yêu cầu đã dùng cho chứng từ tiền khác.');
    }
    return true;
  }

  Future<void> _ensureExternalRequestIdAvailable(
    DatabaseExecutor db,
    String requestId,
  ) async {
    final expense = await db.query(
      'expense_payments',
      columns: const ['id'],
      where: 'id=?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (expense.isNotEmpty) {
      throw StateError(
        'Mã yêu cầu đã được dùng cho chứng từ chi phí khác.',
      );
    }
  }

  Future<void> _ensureTransferReferenceAvailable(
    DatabaseExecutor db,
    String reference,
  ) async {
    for (final table in [
      'supplier_payments',
      'expense_payments',
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
          'Mã chuyển khoản đã dùng cho chứng từ tiền khác. Đối chiếu chứng từ cũ.',
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
      'supplier_payable_events',
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
    DateTime now,
  ) async {
    await db.insert('supplier_payable_events', {
      'request_id': requestId,
      'operation': operation,
      'target_type': targetType,
      'target_id': targetId,
      'signature': signature,
      'actor': actor,
      'detail': detail,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': now.toIso8601String(),
    });
  }

  Future<void> _audit(
    DatabaseExecutor db,
    String actor,
    String action,
    String targetId,
    String detail,
    DateTime now,
  ) async {
    await db.insert('audit_events', {
      'id': EntityId.create('supplier_audit'),
      'actor_name': actor,
      'action': action,
      'target_type': 'supplier_payable',
      'target_id': targetId,
      'result': 'success',
      'detail': detail,
      'created_at': now.toIso8601String(),
    });
  }

  void _validateRequestId(String requestId) {
    if (requestId.trim().isEmpty || requestId.length > 200) {
      throw ArgumentError('Mã yêu cầu không hợp lệ.');
    }
  }
}
