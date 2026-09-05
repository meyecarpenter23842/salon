import '../models/inventory_item.dart';

class InventoryStockBatchLine {
  const InventoryStockBatchLine({
    required this.productId,
    required this.quantity,
  });

  final String productId;
  final int quantity;
}

abstract interface class InventoryRepository {
  Future<List<InventoryProductItem>> fetchInventoryProducts({String? query});

  Future<InventoryProductItem> receiveStock({
    required String productId,
    required int quantity,
    String note = '',
  });

  Future<List<InventoryProductItem>> receiveStockBatch({
    required List<InventoryStockBatchLine> lines,
    String note = '',
  });

  Future<InventoryProductItem> adjustStock({
    required String productId,
    required int newQuantity,
    String note = '',
  });

  Future<List<InventoryProductItem>> adjustStockBatch({
    required List<InventoryStockBatchLine> lines,
    String note = '',
  });

  Future<List<InventoryMovementItem>> fetchInventoryMovements({
    String? productId,
    int limit = 80,
  });
}
