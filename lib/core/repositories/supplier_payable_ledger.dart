import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/entity_id.dart';
import '../models/stock_document.dart';

/// Stock/AP bridge. Called only from the stock document transaction.
class SupplierPayableLedger {
  const SupplierPayableLedger._();

  static Future<void> captureReceipt(
    DatabaseExecutor tx,
    StockDocument document,
    String actor,
    DateTime now,
  ) async {
    if (document.kind != StockDocumentKind.receipt ||
        document.supplierId == null ||
        document.total <= 0) {
      return;
    }

    final existing = await tx.query(
      'supplier_payable_obligations',
      where: "kind='charge' AND source_type='stock_receipt' AND source_id=?",
      whereArgs: [document.id],
      limit: 1,
    );
    final signature = jsonEncode([
      'stock_receipt',
      document.id,
      document.number,
      document.supplierId,
      document.supplierName,
      document.date.toIso8601String(),
      document.total,
      document.externalReference,
    ]);
    if (existing.isNotEmpty) {
      final row = existing.single;
      if (row['signature'] != signature ||
          row['amount'] != document.total ||
          row['supplier_id'] != document.supplierId) {
        throw StateError(
          'Công nợ của phiếu nhập không khớp snapshot. Tải lại và đối chiếu.',
        );
      }
      return;
    }

    final row = <String, Object?>{
      'id': 'supplier-stock-${document.id}',
      'kind': 'charge',
      'original_id': null,
      'supplier_id': document.supplierId,
      'supplier_name': document.supplierName,
      'source_type': 'stock_receipt',
      'source_id': document.id,
      'source_number': document.number,
      'source_date': document.date.toIso8601String(),
      'amount': document.total,
      'reason': 'Phiếu nhập ${document.number}',
      'external_reference': document.externalReference,
      'actor': actor,
      'signature': signature,
      'created_at': now.toIso8601String(),
    };
    await tx.insert('supplier_payable_obligations', row);
    await _event(
      tx,
      'supplier-stock-post-${document.id}',
      signature,
      'stock_receipt_charge',
      row['id'] as String,
      actor,
      'Sinh công nợ từ phiếu nhập ${document.number}',
      null,
      row,
      now,
    );
    await _audit(
      tx,
      actor,
      'supplier_payable_stock_post',
      row['id'] as String,
      '${document.total} VND; ${document.number}',
      now,
    );
  }

  static Future<void> reverseReceipt(
    DatabaseExecutor tx,
    StockDocument document,
    String actor,
    String reason,
    DateTime now,
  ) async {
    if (document.kind != StockDocumentKind.receipt) return;

    final rows = await tx.query(
      'supplier_payable_obligations',
      where: "kind='charge' AND source_type='stock_receipt' AND source_id=?",
      whereArgs: [document.id],
      limit: 1,
    );
    if (rows.isEmpty) {
      // Legacy posted receipts are deliberately not backfilled.
      return;
    }
    final original = rows.single;
    final reversed = await tx.query(
      'supplier_payable_obligations',
      where: "kind='reversal' AND original_id=?",
      whereArgs: [original['id']],
      limit: 1,
    );
    if (reversed.isNotEmpty) return;

    final allocated = await allocatedAmount(tx, original['id'] as String);
    if (allocated != 0) {
      throw StateError(
        'Phiếu nhập đã có thanh toán NCC. Đảo/hoàn hết chứng từ tiền trước khi hủy.',
      );
    }

    final signature = jsonEncode([
      'stock_receipt_reversal',
      document.id,
      original['id'],
      reason,
    ]);
    final row = <String, Object?>{
      'id': 'supplier-stock-reversal-${document.id}',
      'kind': 'reversal',
      'original_id': original['id'],
      'supplier_id': original['supplier_id'],
      'supplier_name': original['supplier_name'],
      'source_type': original['source_type'],
      'source_id': original['source_id'],
      'source_number': original['source_number'],
      'source_date': original['source_date'],
      'amount': -(original['amount'] as int),
      'reason': reason,
      'external_reference': original['external_reference'],
      'actor': actor,
      'signature': signature,
      'created_at': now.toIso8601String(),
    };
    await tx.insert('supplier_payable_obligations', row);
    await _event(
      tx,
      'supplier-stock-cancel-${document.id}',
      signature,
      'stock_receipt_reversal',
      original['id'] as String,
      actor,
      reason,
      original,
      row,
      now,
    );
    await _audit(
      tx,
      actor,
      'supplier_payable_stock_cancel',
      original['id'] as String,
      reason,
      now,
    );
  }

  static Future<int> allocatedAmount(
    DatabaseExecutor tx,
    String obligationId,
  ) async {
    final rows = await tx.rawQuery(
      'SELECT COALESCE(SUM(amount),0) total '
      'FROM supplier_payment_allocations WHERE obligation_id=?',
      [obligationId],
    );
    final value = rows.single['total'];
    return value is int ? value : int.tryParse(value.toString()) ?? 0;
  }

  static Future<void> _event(
    DatabaseExecutor tx,
    String requestId,
    String signature,
    String operation,
    String targetId,
    String actor,
    String detail,
    Map<String, Object?>? before,
    Map<String, Object?> after,
    DateTime now,
  ) async {
    await tx.insert('supplier_payable_events', {
      'request_id': requestId,
      'operation': operation,
      'target_type': 'supplier_payable',
      'target_id': targetId,
      'signature': signature,
      'actor': actor,
      'detail': detail,
      'before_json': before == null ? null : jsonEncode(before),
      'after_json': jsonEncode(after),
      'created_at': now.toIso8601String(),
    });
  }

  static Future<void> _audit(
    DatabaseExecutor tx,
    String actor,
    String action,
    String targetId,
    String detail,
    DateTime now,
  ) async {
    await tx.insert('audit_events', {
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
}
