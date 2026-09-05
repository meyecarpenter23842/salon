import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/inventory_item.dart';
import 'inventory_repository.dart';

class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository(this._database);

  final SalonDatabase _database;

  @override
  Future<List<InventoryProductItem>> fetchInventoryProducts({
    String? query,
  }) async {
    final database = await _database.database;
    final normalizedQuery = query?.trim().toLowerCase();
    final clauses = <String>[];
    final args = <Object?>[];

    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add(
        '(LOWER(p.name) LIKE ? OR LOWER(p.brand) LIKE ? OR '
        'LOWER(p.product_type) LIKE ? OR LOWER(p.volume_label) LIKE ?)',
      );
      args.addAll(List.filled(4, '%$normalizedQuery%'));
    }

    final rows = await database.rawQuery(
      'SELECT p.id, p.name, p.brand, p.volume_label, p.product_type, '
      'p.is_active, COALESCE(s.stock_on_hand, 0) AS stock_on_hand '
      'FROM retail_products p '
      'LEFT JOIN inventory_stock s ON s.product_id = p.id '
      '${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')} '} '
      'ORDER BY p.is_active DESC, stock_on_hand ASC, p.name COLLATE NOCASE ASC',
      args,
    );

    return rows.map(_productFromRow).toList(growable: false);
  }

  @override
  Future<InventoryProductItem> receiveStock({
    required String productId,
    required int quantity,
    String note = '',
  }) async {
    final results = await receiveStockBatch(
      lines: [InventoryStockBatchLine(productId: productId, quantity: quantity)],
      note: note,
    );
    return results.single;
  }

  @override
  Future<List<InventoryProductItem>> receiveStockBatch({
    required List<InventoryStockBatchLine> lines,
    String note = '',
  }) async {
    _validateBatch(lines, allowZero: false);
    final database = await _database.database;
    return database.transaction((transaction) async {
      final results = <InventoryProductItem>[];
      for (final line in lines) {
        results.add(
          await _mutateStockInTransaction(
            transaction,
            productId: line.productId,
            movementType: 'receive',
            note: note,
            resolveAfter: (before) => before + line.quantity,
          ),
        );
      }
      return results;
    });
  }

  @override
  Future<InventoryProductItem> adjustStock({
    required String productId,
    required int newQuantity,
    String note = '',
  }) async {
    final results = await adjustStockBatch(
      lines: [
        InventoryStockBatchLine(productId: productId, quantity: newQuantity),
      ],
      note: note,
    );
    return results.single;
  }

  @override
  Future<List<InventoryProductItem>> adjustStockBatch({
    required List<InventoryStockBatchLine> lines,
    String note = '',
  }) async {
    _validateBatch(lines, allowZero: true);
    final database = await _database.database;
    return database.transaction((transaction) async {
      final results = <InventoryProductItem>[];
      for (final line in lines) {
        results.add(
          await _mutateStockInTransaction(
            transaction,
            productId: line.productId,
            movementType: 'adjustment',
            note: note,
            resolveAfter: (_) => line.quantity,
          ),
        );
      }
      return results;
    });
  }

  @override
  Future<List<InventoryMovementItem>> fetchInventoryMovements({
    String? productId,
    int limit = 80,
  }) async {
    final database = await _database.database;
    final safeLimit = limit.clamp(1, 500);
    final normalizedProductId = productId?.trim();
    final filter = normalizedProductId == null || normalizedProductId.isEmpty
        ? ''
        : 'WHERE m.product_id = ? ';
    final args = <Object?>[
      if (normalizedProductId != null && normalizedProductId.isNotEmpty)
        normalizedProductId,
      safeLimit,
    ];

    final rows = await database.rawQuery(
      'SELECT m.id, m.product_id, p.name AS product_name, m.movement_type, '
      'm.quantity_delta, m.stock_before, m.stock_after, m.note, m.created_at '
      'FROM inventory_movements m '
      'JOIN retail_products p ON p.id = m.product_id '
      '$filter'
      'ORDER BY m.created_at DESC LIMIT ?',
      args,
    );

    return rows
        .map(
          (row) => InventoryMovementItem(
            id: row['id']?.toString() ?? '',
            productId: row['product_id']?.toString() ?? '',
            productName: row['product_name']?.toString() ?? 'Sản phẩm',
            movementType: row['movement_type']?.toString() ?? 'adjustment',
            quantityDelta: _toInt(row['quantity_delta']),
            stockBefore: _toInt(row['stock_before']),
            stockAfter: _toInt(row['stock_after']),
            note: row['note']?.toString() ?? '',
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
  }

  void _validateBatch(
    List<InventoryStockBatchLine> lines, {
    required bool allowZero,
  }) {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'Không được rỗng');
    }
    final productIds = <String>{};
    for (final line in lines) {
      final productId = line.productId.trim();
      if (productId.isEmpty) {
        throw ArgumentError.value(line.productId, 'productId', 'Không được rỗng');
      }
      if (!productIds.add(productId)) {
        throw StateError('Batch kho chứa trùng sản phẩm $productId');
      }
      if (allowZero ? line.quantity < 0 : line.quantity <= 0) {
        throw ArgumentError.value(
          line.quantity,
          'quantity',
          allowZero ? 'Không được âm' : 'Phải lớn hơn 0',
        );
      }
    }
  }

  Future<InventoryProductItem> _mutateStockInTransaction(
    DatabaseExecutor transaction, {
    required String productId,
    required String movementType,
    required String note,
    required int Function(int before) resolveAfter,
  }) async {
    final productRows = await transaction.rawQuery(
      'SELECT p.id, p.name, p.brand, p.volume_label, p.product_type, '
      'p.is_active, COALESCE(s.stock_on_hand, 0) AS stock_on_hand '
      'FROM retail_products p '
      'LEFT JOIN inventory_stock s ON s.product_id = p.id '
      'WHERE p.id = ? LIMIT 1',
      [productId],
    );
    if (productRows.isEmpty) {
      throw StateError('Product $productId not found');
    }

    final productRow = productRows.first;
    final before = _toInt(productRow['stock_on_hand']);
    final after = resolveAfter(before);
    if (after < 0) {
      throw StateError('Tồn kho sau điều chỉnh không được âm');
    }
    if (movementType == 'adjustment' && after == before) {
      throw StateError('Tồn mới phải khác tồn hiện tại');
    }

    final timestamp = DateTime.now().toIso8601String();
    final stockRow = <String, Object?>{
      'product_id': productId,
      'stock_on_hand': after,
      'updated_at': timestamp,
    };
    final updatedCount = await transaction.update(
      'inventory_stock',
      stockRow,
      where: 'product_id = ?',
      whereArgs: [productId],
    );
    if (updatedCount == 0) {
      await transaction.insert(
        'inventory_stock',
        stockRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else if (updatedCount != 1) {
      throw StateError('Inventory stock $productId updated $updatedCount rows');
    }

    await transaction.insert('inventory_movements', {
      'id': EntityId.create('stock'),
      'product_id': productId,
      'movement_type': movementType,
      'quantity_delta': after - before,
      'stock_before': before,
      'stock_after': after,
      'note': note.trim(),
      'created_at': timestamp,
    });

    return _productFromRow({...productRow, 'stock_on_hand': after});
  }

  InventoryProductItem _productFromRow(Map<String, Object?> row) {
    return InventoryProductItem(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      brand: row['brand']?.toString() ?? '',
      volumeLabel: row['volume_label']?.toString() ?? '',
      productType: row['product_type']?.toString() ?? '',
      stockOnHand: _toInt(row['stock_on_hand']),
      isActive: _toInt(row['is_active']) == 1,
    );
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
