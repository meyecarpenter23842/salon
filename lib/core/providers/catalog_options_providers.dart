import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/salon_database.dart';
import '../models/catalog_option.dart';
import '../repositories/catalog_options_repository.dart';
import 'data_backend_provider.dart';

final catalogOptionsRefreshNonceProvider = StateProvider<int>((ref) => 0);

final catalogOptionsRepositoryProvider = Provider<CatalogOptionsRepository>((
  ref,
) {
  final backend = ref.watch(appDataBackendProvider);
  return switch (backend) {
    AppDataBackend.sqlite => SqliteCatalogOptionsRepository(
      SalonDatabase.instance,
    ),
    AppDataBackend.fake => FakeCatalogOptionsRepository(),
  };
});

final catalogOptionNamesProvider =
    FutureProvider.family<List<String>, CatalogOptionKind>((ref, kind) {
      ref.watch(catalogOptionsRefreshNonceProvider);
      return ref.watch(catalogOptionsRepositoryProvider).fetchOptionNames(kind);
    });
