import '../models/inventory_item.dart';
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
          (product) => InventoryProductItem(
            id: product.id,
            name: product.name,
            brand: product.brand,
            volumeLabel: product.volumeLabel,
            productType: product.productType,
            stockOnHand: _stock[product.id] ?? 0,
            isActive: product.isActive,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<InventoryProductItem> receiveStock({
    required String productId,
    required int quantity,
    String note = '',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Phải lớn hơn 0');
    }
    final before = _stock[productId] ?? 0;
    return _mutate(
      productId: productId,
      movementType: 'receive',
      before: before,
      after: before + quantity,
      note: note,
    );
  }

  @override
  Future<InventoryProductItem> adjustStock({
    required String productId,
    required int newQuantity,
    String note = '',
  }) async {
    if (newQuantity < 0) {
      throw ArgumentError.value(newQuantity, 'newQuantity', 'Không được âm');
    }
    final before = _stock[productId] ?? 0;
    if (before == newQuantity) {
      throw StateError('Tồn mới phải khác tồn hiện tại');
    }
    return _mutate(
      productId: productId,
      movementType: 'adjustment',
      before: before,
      after: newQuantity,
      note: note,
    );
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

  Future<InventoryProductItem> _mutate({
    required String productId,
    required String movementType,
    required int before,
    required int after,
    required String note,
  }) async {
    final products = await FakeRetailProductsRepository.shared().fetchProducts();
    final matches = products.where((item) => item.id == productId);
    if (matches.isEmpty) {
      throw StateError('Product $productId not found');
    }
    final product = matches.first;
    final now = DateTime.now();
    _stock[productId] = after;
    _movements.insert(
      0,
      InventoryMovementItem(
        id: 'stock-${now.microsecondsSinceEpoch}',
        productId: productId,
        productName: product.name,
        movementType: movementType,
        quantityDelta: after - before,
        stockBefore: before,
        stockAfter: after,
        note: note.trim(),
        createdAt: now,
      ),
    );

    return InventoryProductItem(
      id: product.id,
      name: product.name,
      brand: product.brand,
      volumeLabel: product.volumeLabel,
      productType: product.productType,
      stockOnHand: after,
      isActive: product.isActive,
    );
  }
}
