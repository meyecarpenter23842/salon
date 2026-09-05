import '../models/inventory_item.dart';

abstract interface class InventoryRepository {
  Future<List<InventoryProductItem>> fetchInventoryProducts({String? query});

  Future<InventoryProductItem> receiveStock({
    required String productId,
    required int quantity,
    String note = '',
  });

  Future<InventoryProductItem> adjustStock({
    required String productId,
    required int newQuantity,
    String note = '',
  });

  Future<List<InventoryMovementItem>> fetchInventoryMovements({
    String? productId,
    int limit = 80,
  });
}
