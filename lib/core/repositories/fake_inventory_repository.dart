import '../models/inventory_item.dart';
import '../models/retail_product_item.dart';
import 'fake_repositories.dart';
import 'inventory_repository.dart';

class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository();

  static final Map<String, int> _stock = <String, int>{};
  static final List<InventoryMovementItem> _movements =
      <InventoryMovementItem>[];

  @override
  Future<List<InventoryProductItem>> fetchInventoryProducts({
    String? query,
  }) async {
    final products = await FakeRetailProductsRepository.shared().fetchProducts(
      query: query,
    );
    return products
        .map(
          (product) => _inventoryProduct(product, _stock[product.id] ?? 0),
        )
        .toList(growable: false);
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
    final products = await _validateBatch(lines, allowZero: false);
    final results = <InventoryProductItem>[];
    for (final line in lines) {
      final product = products[line.productId]!;
      final before = _stock[line.productId] ?? 0;
      results.add(
        _applyMutation(
          product: product,
          movementType: 'receive',
          before: before,
          after: before + line.quantity,
          note: note,
        ),
      );
    }
    return results;
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
    final products = await _validateBatch(lines, allowZero: true);
    for (final line in lines) {
      final before = _stock[line.productId] ?? 0;
      if (before == line.quantity) {
        throw StateError('Tồn mới phải khác tồn hiện tại');
      }
    }

    final results = <InventoryProductItem>[];
    for (final line in lines) {
      final product = products[line.productId]!;
      final before = _stock[line.productId] ?? 0;
      results.add(
        _applyMutation(
          product: product,
          movementType: 'adjustment',
          before: before,
          after: line.quantity,
          note: note,
        ),
      );
    }
    return results;
  }

  @override
  Future<List<InventoryMovementItem>> fetchInventoryMovements({
    String? productId,
    int limit = 80,
  }) async {
    final normalizedProductId = productId?.trim();
    final filtered = normalizedProductId == null || normalizedProductId.isEmpty
        ? _movements
        : _movements
              .where((item) => item.productId == normalizedProductId)
              .toList(growable: false);
    return filtered.take(limit.clamp(1, 500)).toList(growable: false);
  }

  Future<Map<String, RetailProductItem>> _validateBatch(
    List<InventoryStockBatchLine> lines, {
    required bool allowZero,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'Không được rỗng');
    }
    final ids = <String>{};
    for (final line in lines) {
      if (line.productId.trim().isEmpty) {
        throw ArgumentError.value(line.productId, 'productId', 'Không được rỗng');
      }
      if (!ids.add(line.productId)) {
        throw StateError('Batch kho chứa trùng sản phẩm ${line.productId}');
      }
      if (allowZero ? line.quantity < 0 : line.quantity <= 0) {
        throw ArgumentError.value(
          line.quantity,
          'quantity',
          allowZero ? 'Không được âm' : 'Phải lớn hơn 0',
        );
      }
    }

    final products = await FakeRetailProductsRepository.shared().fetchProducts();
    final productMap = {for (final product in products) product.id: product};
    for (final id in ids) {
      if (!productMap.containsKey(id)) {
        throw StateError('Product $id not found');
      }
    }
    return productMap;
  }

  InventoryProductItem _applyMutation({
    required RetailProductItem product,
    required String movementType,
    required int before,
    required int after,
    required String note,
  }) {
    final now = DateTime.now();
    _stock[product.id] = after;
    _movements.insert(
      0,
      InventoryMovementItem(
        id: 'stock-${now.microsecondsSinceEpoch}',
        productId: product.id,
        productName: product.name,
        movementType: movementType,
        quantityDelta: after - before,
        stockBefore: before,
        stockAfter: after,
        note: note.trim(),
        createdAt: now,
      ),
    );
    return _inventoryProduct(product, after);
  }

  InventoryProductItem _inventoryProduct(
    RetailProductItem product,
    int stockOnHand,
  ) {
    return InventoryProductItem(
      id: product.id,
      name: product.name,
      brand: product.brand,
      volumeLabel: product.volumeLabel,
      productType: product.productType,
      stockOnHand: stockOnHand,
      isActive: product.isActive,
    );
  }
}
