import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/stock_document.dart';
import '../services/sensitive_action_service.dart';

class StockDocumentRepository {
  StockDocumentRepository(this.database, this.security);
  final SalonDatabase database;
  final SensitiveActionService security;

  Future<List<StockSupplier>> suppliers({bool includeInactive = true}) async {
    final db = await database.database;
    final rows = await db.query('stock_suppliers', where: includeInactive ? null : 'is_active = 1',
      orderBy: 'is_active DESC, name COLLATE NOCASE');
    return rows.map((r) => StockSupplier(id: r['id'] as String, name: r['name'] as String,
      phone: r['phone'] as String, email: r['email'] as String, address: r['address'] as String,
      note: r['note'] as String, isActive: r['is_active'] == 1)).toList();
  }

  Future<void> saveSupplier(StockSupplier supplier) async {
    if (supplier.id.trim().isEmpty || supplier.name.trim().isEmpty || supplier.name.length > 200 ||
        [supplier.phone, supplier.email, supplier.address, supplier.note].any((v) => v.length > 2000)) {
      throw ArgumentError('Thông tin nhà cung cấp không hợp lệ.');
    }
    final actor = await security.authorizeInventoryAction('stock_supplier_save', supplier.id);
    final db = await database.database;
    await db.transaction((tx) async {
      final old = await tx.query('stock_suppliers', where: 'id = ?', whereArgs: [supplier.id]);
      final now = DateTime.now().toIso8601String();
      final row = <String, Object?>{'id': supplier.id, 'name': supplier.name.trim(),
        'phone': supplier.phone.trim(), 'email': supplier.email.trim(), 'address': supplier.address.trim(),
        'note': supplier.note.trim(), 'is_active': supplier.isActive ? 1 : 0, 'updated_at': now};
      if (old.isEmpty) { await tx.insert('stock_suppliers', {...row, 'created_at': now}); }
      else { await tx.update('stock_suppliers', row, where: 'id = ?', whereArgs: [supplier.id]); }
      await _audit(tx, actor, 'stock_supplier_save', supplier.id, supplier.isActive ? 'active' : 'inactive');
    });
  }

  Future<List<StockDocument>> documents({String query = '', String? status, StockDocumentKind? kind}) async {
    final db = await database.database;
    return db.transaction((tx) async {
    final rows = await tx.query('stock_documents',
      where: [if (status != null) 'status = ?', if (kind != null) 'kind = ?'].join(' AND ').isEmpty
        ? null : [if (status != null) 'status = ?', if (kind != null) 'kind = ?'].join(' AND '),
      whereArgs: [if (status != null) status, if (kind != null) kind.value],
      orderBy: 'document_date DESC, sequence DESC');
    final q = query.trim().toLowerCase();
    final result = <StockDocument>[];
    for (final row in rows) {
      if (q.isNotEmpty && ![row['number'], row['supplier_name'], row['external_reference'], row['prepared_by']]
          .any((v) => v.toString().toLowerCase().contains(q))) continue;
      result.add(await _read(tx, row));
    }
    return result;
    });
  }

  Future<StockDocument> document(String id) async {
    final db = await database.database;
    return db.transaction((tx) => _find(tx, id));
  }

  Future<StockDocument> saveDraft(StockDocumentInput input) async {
    if (input.id.trim().isEmpty || input.preparedBy.trim().isEmpty || input.preparedBy.length > 200 ||
        input.externalReference.length > 200 || input.note.length > 2000 ||
        input.lines.isEmpty || input.lines.length > 200) throw ArgumentError('Phiếu thiếu thông tin hoặc quá nhiều dòng.');
    final ids = <String>{};
    for (final line in input.lines) {
      if (!ids.add(line.productId) || line.quantity < 0 || line.quantity > 1000000 ||
          (input.kind != StockDocumentKind.adjustment && line.quantity == 0) ||
          line.unitCost < 0 || line.unitCost > 1000000000 ||
          (input.kind != StockDocumentKind.receipt && line.unitCost != 0)) {
        throw ArgumentError('Dòng phiếu không hợp lệ; kiểm kê không âm, nhập/xuất phải dương.');
      }
    }
    if (input.kind != StockDocumentKind.receipt && input.note.trim().isEmpty) {
      throw ArgumentError('Xuất/kiểm kê cần ghi lý do.');
    }
    final actor = await security.authorizeInventoryAction('stock_draft_save', input.id);
    final db = await database.database;
    return db.transaction((tx) async {
      final signature = jsonEncode([input.kind.value, input.date.toIso8601String(), input.preparedBy.trim(),
        input.supplierId, input.externalReference.trim(), input.note.trim(),
        input.lines.map((l) => [l.productId, l.quantity, l.unitCost]).toList()]);
      final old = await tx.query('stock_documents', where: 'id = ?', whereArgs: [input.id]);
      if (old.isNotEmpty && input.expectedRevision == null && old.single['request_signature'] == signature) {
        return _read(tx, old.single);
      }
      if (old.isNotEmpty && (old.single['status'] != 'draft' || input.expectedRevision != old.single['revision'])) {
        throw StateError('Phiếu đã ghi kho hoặc thay đổi. Tải lại trước khi sửa.');
      }
      if (old.isEmpty && input.expectedRevision != null) throw StateError('Phiếu không còn tồn tại.');
      String supplierName = '';
      if (input.supplierId != null) {
        final suppliers = await tx.query('stock_suppliers', where: 'id = ? AND is_active = 1', whereArgs: [input.supplierId]);
        if (suppliers.isEmpty) throw StateError('Nhà cung cấp không còn hoạt động.');
        supplierName = suppliers.single['name'] as String;
      }
      if (input.kind != StockDocumentKind.receipt && input.supplierId != null) throw ArgumentError('Chỉ phiếu nhập chọn nhà cung cấp.');
      final lines = <Map<String, Object?>>[];
      var total = 0;
      for (var i = 0; i < input.lines.length; i++) {
        final line = input.lines[i];
        final products = await tx.query('retail_products', where: 'id = ? AND is_active = 1', whereArgs: [line.productId]);
        if (products.isEmpty) throw StateError('Sản phẩm không còn hoạt động.');
        final product = products.single;
        final amount = line.quantity * line.unitCost;
        total += amount;
        lines.add({'id': '${input.id}-line-$i', 'document_id': input.id, 'product_id': line.productId,
          'product_name': product['name'], 'unit_name': product['unit_name'] ?? '',
          'quantity': line.quantity, 'unit_cost': line.unitCost, 'amount': amount});
      }
      final now = DateTime.now().toIso8601String();
      final values = <String, Object?>{'kind': input.kind.value, 'document_date': input.date.toIso8601String(),
        'supplier_id': input.supplierId, 'supplier_name': supplierName, 'prepared_by': input.preparedBy.trim(),
        'external_reference': input.externalReference.trim(), 'note': input.note.trim(), 'total': total,
        'request_signature': signature, 'revision': old.isEmpty ? 1 : (old.single['revision'] as int) + 1, 'updated_at': now};
      if (old.isEmpty) {
        final sequence = await tx.insert('stock_documents', {...values, 'id': input.id, 'created_at': now});
        await tx.update('stock_documents', {'number': '${input.kind.prefix}-${sequence.toString().padLeft(6, '0')}'},
          where: 'id = ?', whereArgs: [input.id]);
      } else {
        if (old.single['kind'] != input.kind.value) throw StateError('Không được đổi loại phiếu.');
        await tx.update('stock_documents', values, where: 'id = ?', whereArgs: [input.id]);
        await tx.delete('stock_document_lines', where: 'document_id = ?', whereArgs: [input.id]);
      }
      for (final line in lines) { await tx.insert('stock_document_lines', line); }
      await _audit(tx, actor, 'stock_draft_save', input.id, 'total=$total;lines=${lines.length}');
      return _find(tx, input.id);
    });
  }

  Future<StockDocument> post(String id, {required int expectedRevision}) async {
    final actor = await security.authorizeInventoryAction('stock_document_post', id);
    final db = await database.database;
    return db.transaction((tx) async {
      final doc = await _find(tx, id);
      if (doc.isPosted) return doc; // Retry never applies movements again.
      if (!doc.isDraft || doc.revision != expectedRevision) throw StateError('Phiếu đã thay đổi hoặc bị hủy.');
      if (doc.supplierId != null) {
        final supplier = await tx.query('stock_suppliers', where: 'id = ? AND is_active = 1', whereArgs: [doc.supplierId]);
        if (supplier.isEmpty) throw StateError('Nhà cung cấp đã ngừng sử dụng; sửa nháp trước khi nhập.');
      }
      for (final line in doc.lines) {
        final product = await tx.query('retail_products', where: 'id = ? AND is_active = 1', whereArgs: [line.productId]);
        if (product.isEmpty) throw StateError('Sản phẩm đã ngừng sử dụng; sửa nháp trước khi nhập.');
        if ((product.single['unit_name'] ?? '') != line.unitName) {
          throw StateError('Đơn vị đã đổi; sửa nháp để xác nhận lại số lượng.');
        }
        final before = await _stock(tx, line.productId);
        final after = switch(doc.kind) {
          StockDocumentKind.receipt => before + line.quantity,
          StockDocumentKind.issue => before - line.quantity,
          StockDocumentKind.adjustment => line.quantity,
        };
        await _movement(tx, doc, line, 'post', before, after, doc.note);
      }
      await tx.update('stock_documents', {'status': 'posted', 'posted_by': actor,
        'posted_at': DateTime.now().toIso8601String(), 'updated_at': DateTime.now().toIso8601String(),
        'revision': doc.revision + 1}, where: 'id = ?', whereArgs: [id]);
      await _audit(tx, actor, 'stock_document_post', id, 'total=${doc.total};number=${doc.number}');
      return _find(tx, id);
    });
  }

  Future<StockDocument> cancel(String id, {required int expectedRevision, required String reason}) async {
    if (reason.trim().isEmpty || reason.length > 2000) throw ArgumentError('Bắt buộc nhập lý do hủy.');
    final actor = await security.authorizeInventoryAction('stock_document_cancel', id);
    final db = await database.database;
    return db.transaction((tx) async {
      final doc = await _find(tx, id);
      if (doc.status == 'cancelled') {
        if (doc.cancellationReason != reason.trim()) throw StateError('Phiếu đã hủy với lý do khác.');
        return doc;
      }
      if (doc.revision != expectedRevision) throw StateError('Phiếu đã thay đổi. Tải lại trước khi hủy.');
      if (doc.isPosted) {
        for (final line in doc.lines) {
          final movements = await tx.query('inventory_movements', where: 'id = ?', whereArgs: ['stock-doc-$id-${line.id}-post']);
          if (movements.length != 1) throw StateError('Không đối chiếu được bút toán gốc.');
          final before = await _stock(tx, line.productId);
          final after = before - (movements.single['quantity_delta'] as int);
          await _movement(tx, doc, line, 'reverse', before, after, reason.trim());
        }
      }
      await tx.update('stock_documents', {'status': 'cancelled', 'cancelled_at': DateTime.now().toIso8601String(),
        'cancellation_reason': reason.trim(), 'updated_at': DateTime.now().toIso8601String(),
        'revision': doc.revision + 1}, where: 'id = ?', whereArgs: [id]);
      await _audit(tx, actor, 'stock_document_cancel', id, reason.trim());
      return _find(tx, id);
    });
  }

  Future<int> _stock(DatabaseExecutor tx, String productId) async {
    final rows = await tx.query('inventory_stock', columns: ['stock_on_hand'], where: 'product_id = ?', whereArgs: [productId]);
    return rows.isEmpty ? 0 : rows.single['stock_on_hand'] as int;
  }
  Future<void> _movement(DatabaseExecutor tx, StockDocument doc, StockDocumentLine line, String phase,
      int before, int after, String note) async {
    final now = DateTime.now().toIso8601String();
    final values = {'product_id': line.productId, 'stock_on_hand': after, 'updated_at': now};
    if (await tx.update('inventory_stock', values, where: 'product_id = ?', whereArgs: [line.productId]) == 0) {
      await tx.insert('inventory_stock', values);
    }
    await tx.insert('inventory_movements', {'id': 'stock-doc-${doc.id}-${line.id}-$phase',
      'product_id': line.productId, 'movement_type': phase == 'reverse' ? 'reverse' : doc.kind.value == 'receipt' ? 'receive' : doc.kind.value,
      'quantity_delta': after - before, 'stock_before': before, 'stock_after': after,
      'note': note, 'created_at': now, 'document_id': doc.id, 'document_line_id': line.id, 'source': 'document'});
  }
  Future<void> _audit(DatabaseExecutor tx, String actor, String action, String id, String detail) => tx.insert('audit_events',
    {'id': EntityId.create('stock-audit'), 'actor_name': actor, 'action': action,
      'target_type': 'stock_document', 'target_id': id, 'result': 'success', 'detail': detail,
      'created_at': DateTime.now().toIso8601String()}).then((_) {});
  Future<StockDocument> _find(DatabaseExecutor tx, String id) async {
    final rows = await tx.query('stock_documents', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Không tìm thấy phiếu.');
    return _read(tx, rows.single);
  }
  Future<StockDocument> _read(DatabaseExecutor tx, Map<String, Object?> r) async {
    final lines = await tx.query('stock_document_lines', where: 'document_id = ?', whereArgs: [r['id']], orderBy: 'rowid');
    return StockDocument(id: r['id'] as String, number: r['number'] as String, kind: StockDocumentKind.parse(r['kind'] as String),
      date: DateTime.parse(r['document_date'] as String), preparedBy: r['prepared_by'] as String,
      status: r['status'] as String, revision: r['revision'] as int, supplierId: r['supplier_id'] as String?,
      supplierName: r['supplier_name'] as String, externalReference: r['external_reference'] as String,
      note: r['note'] as String, postedBy: r['posted_by'] as String, cancellationReason: r['cancellation_reason'] as String,
      lines: lines.map((l) => StockDocumentLine(id: l['id'] as String, productId: l['product_id'] as String,
        productName: l['product_name'] as String, unitName: l['unit_name'] as String,
        quantity: l['quantity'] as int, unitCost: l['unit_cost'] as int)).toList());
  }
}
