import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/salon_database.dart';
import '../models/stock_document.dart';
import '../repositories/stock_document_repository.dart';
import 'repository_providers.dart';

final stockDocumentRepositoryProvider = Provider<StockDocumentRepository>((ref) =>
  StockDocumentRepository(SalonDatabase.instance, ref.watch(sensitiveActionServiceProvider)));
final stockDocumentsNonceProvider = StateProvider<int>((ref) => 0);
final stockDocumentsProvider = FutureProvider<List<StockDocument>>((ref) {
  ref.watch(stockDocumentsNonceProvider);
  return ref.watch(stockDocumentRepositoryProvider).documents();
});
final stockSuppliersProvider = FutureProvider<List<StockSupplier>>((ref) {
  ref.watch(stockDocumentsNonceProvider);
  return ref.watch(stockDocumentRepositoryProvider).suppliers();
});

typedef StockDocumentQuery = ({String query, String status, bool receipts, int offset});
final stockDocumentPageProvider = FutureProvider.autoDispose.family<List<StockDocument>, StockDocumentQuery>((ref, filter) {
  ref.watch(stockDocumentsNonceProvider);
  return ref.watch(stockDocumentRepositoryProvider).documents(query: filter.query,
    status: filter.status == 'all' ? null : filter.status, kind: filter.receipts ? StockDocumentKind.receipt : null,
    excludeReceipts: !filter.receipts, offset: filter.offset);
});
