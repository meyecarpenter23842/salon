import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/retail_product_mapper.dart';
import '../database/salon_database.dart';
import '../models/entity_id.dart';
import '../models/retail_product_item.dart';
import '../models/retail_product_upsert_input.dart';
import 'catalog_detail_repository.dart';
import 'repository_contracts.dart';

class SqliteRetailProductsRepository
    implements RetailProductsRepository, ProductDetailRepository {
  SqliteRetailProductsRepository(this._database);

  final SalonDatabase _database;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  @override
  Future<List<RetailProductItem>> fetchProducts({
    String? query,
    String? type,
  }) async {
    final database = await _database.database;
    final normalizedQuery = query?.trim().toLowerCase();
    final normalizedType = type?.trim();

    final clauses = <String>[];
    final args = <Object?>[];

    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      clauses.add(
        '(LOWER(name) LIKE ? OR LOWER(brand) LIKE ? OR LOWER(product_type) LIKE ? OR LOWER(volume_label) LIKE ?)',
      );
      args.addAll(List.filled(4, '%$normalizedQuery%'));
    }

    if (normalizedType != null &&
        normalizedType.isNotEmpty &&
        normalizedType != 'Tất cả') {
      clauses.add('product_type = ?');
      args.add(normalizedType);
    }

    final rows = await database.query(
      'retail_products',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: clauses.isEmpty ? null : args,
      orderBy:
          'is_active DESC, product_type COLLATE NOCASE ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(RetailProductMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> fetchProductDetail(String productId) async {
    final database = await _database.database;
    final product = await _findById(database, productId);
    if (product == null) {
      throw StateError('Product $productId not found');
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final metricRows = await database.rawQuery(
      'SELECT COALESCE(SUM(ii.total_price), 0) AS revenue, '
      'COALESCE(SUM(ii.quantity), 0) AS quantity, '
      'COUNT(DISTINCT i.customer_id) AS customer_count, '
      'COALESCE(SUM(ii.discount_amount), 0) AS line_discount '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      "WHERE ii.item_type = 'product' AND ii.product_id = ? "
      'AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ?',
      [productId, monthStart.toIso8601String(), nextMonth.toIso8601String()],
    );
    final metrics = metricRows.isEmpty
        ? const <String, Object?>{}
        : metricRows.first;

    final historyRows = await database.rawQuery(
      'SELECT i.id AS invoice_id, i.customer_id, i.paid_at, '
      'c.full_name AS customer_name, ii.quantity, ii.unit_price, '
      'ii.discount_amount, ii.total_price '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'LEFT JOIN customers c ON c.id = i.customer_id '
      "WHERE ii.item_type = 'product' AND ii.product_id = ? "
      'AND i.paid_at IS NOT NULL '
      'ORDER BY i.paid_at DESC '
      'LIMIT 20',
      [productId],
    );

    final revenue = _toInt(metrics['revenue']);
    final quantity = _toInt(metrics['quantity']);
    final customerCount = _toInt(metrics['customer_count']);
    final lineDiscount = _toInt(metrics['line_discount']);

    return {
      'productId': product.id,
      'monthRevenueValue': revenue,
      'monthRevenue': _currency(revenue),
      'monthQuantity': quantity,
      'monthCustomerCount': customerCount,
      'monthLineDiscountValue': lineDiscount,
      'monthLineDiscount': _currency(lineDiscount),
      'history': historyRows
          .map((row) {
            final paidAt = DateTime.tryParse(row['paid_at']?.toString() ?? '');
            return <String, Object?>{
              'invoiceId': row['invoice_id']?.toString() ?? '',
              'customerId': row['customer_id']?.toString() ?? '',
              'customerName': row['customer_name']?.toString().trim().isNotEmpty == true
                  ? row['customer_name'].toString()
                  : 'Khách',
              'paidAt': paidAt?.toIso8601String() ?? '',
              'dateLabel': paidAt == null ? '' : _dateFormatter.format(paidAt),
              'timeLabel': paidAt == null ? '' : _timeFormatter.format(paidAt),
              'quantity': _toInt(row['quantity']),
              'unitPriceValue': _toInt(row['unit_price']),
              'unitPrice': _currency(_toInt(row['unit_price'])),
              'discountValue': _toInt(row['discount_amount']),
              'discount': _currency(_toInt(row['discount_amount'])),
              'totalValue': _toInt(row['total_price']),
              'total': _currency(_toInt(row['total_price'])),
            };
          })
          .toList(growable: false),
      'dataNote':
          'Doanh thu dùng tổng tiền của dòng sản phẩm đã thanh toán; chiết khấu toàn bill không phân bổ ngược về từng sản phẩm.',
    };
  }

  @override
  Future<RetailProductItem> saveProduct(
    RetailProductUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    final now = DateTime.now();
    final item = RetailProductMapper.fromUpsertInput(
      id: existing?.id ?? EntityId.create('product'),
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await database.insert(
      'retail_products',
      RetailProductMapper.toDatabase(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return item;
  }

  @override
  Future<RetailProductItem> updateProductActive(
    String productId,
    bool isActive,
  ) async {
    final database = await _database.database;
    final existing = await _findById(database, productId);
    if (existing == null) {
      throw StateError('Product $productId not found');
    }

    final updated = existing.copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );
    await database.update(
      'retail_products',
      RetailProductMapper.toDatabase(updated),
      where: 'id = ?',
      whereArgs: [productId],
    );

    return updated;
  }

  Future<RetailProductItem?> _findById(Database database, String id) async {
    final rows = await database.query(
      'retail_products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return RetailProductMapper.fromDatabase(rows.first);
  }

  String _currency(int value) {
    return _currencyFormatter.format(value).replaceAll(',', '.');
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
