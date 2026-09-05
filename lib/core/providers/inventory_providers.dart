import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/inventory_item.dart';
import '../database/salon_database.dart';
import '../repositories/fake_inventory_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/sqlite_inventory_repository.dart';
import 'data_backend_provider.dart';

final inventoryRefreshNonceProvider = StateProvider<int>((ref) => 0);

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final backend = ref.watch(appDataBackendProvider);
  return switch (backend) {
    AppDataBackend.sqlite => SqliteInventoryRepository(SalonDatabase.instance),
    AppDataBackend.fake => FakeInventoryRepository(),
  };
});

final inventoryProductsViewProvider =
    FutureProvider<List<InventoryProductItem>>((ref) {
      ref.watch(inventoryRefreshNonceProvider);
      return ref.watch(inventoryRepositoryProvider).fetchInventoryProducts();
    });

final inventoryMovementsViewProvider =
    FutureProvider<List<InventoryMovementItem>>((ref) {
      ref.watch(inventoryRefreshNonceProvider);
      return ref
          .watch(inventoryRepositoryProvider)
          .fetchInventoryMovements(limit: 100);
    });
