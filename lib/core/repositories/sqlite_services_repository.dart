import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../data/fake/fake_salon_data_source.dart';
import '../database/salon_database.dart';
import '../database/salon_database_seed.dart';
import '../database/service_mapper.dart';
import '../models/entity_id.dart';
import '../models/service_catalog_item.dart';
import '../models/service_upsert_input.dart';
import 'catalog_detail_repository.dart';
import 'repository_contracts.dart';

class SqliteServicesRepository
    implements ServicesRepository, ServiceDetailRepository {
  SqliteServicesRepository(this._database, FakeSalonDataSource dataSource)
      : _seed = SalonDatabaseSeed(dataSource);

  final SalonDatabase _database;
  final SalonDatabaseSeed _seed;

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: 'đ',
    decimalDigits: 0,
  );
  static final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  @override
  Future<List<ServiceCatalogItem>> fetchServicesView() async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final rows = await database.query(
      'services',
      orderBy: 'category COLLATE NOCASE ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(ServiceMapper.fromDatabase).toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> fetchServiceDetail(String serviceId) async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final service = await _findById(database, serviceId);
    if (service == null) {
      throw StateError('Service $serviceId not found');
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
      "WHERE ii.item_type = 'service' AND ii.service_id = ? "
      'AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ?',
      [serviceId, monthStart.toIso8601String(), nextMonth.toIso8601String()],
    );
    final metrics = metricRows.isEmpty
        ? const <String, Object?>{}
        : metricRows.first;

    final topStaffRows = await database.rawQuery(
      'SELECT ii.employee_id, e.full_name, '
      'COALESCE(SUM(ii.quantity), 0) AS quantity, '
      'COALESCE(SUM(ii.total_price), 0) AS revenue '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'LEFT JOIN employees e ON e.id = ii.employee_id '
      "WHERE ii.item_type = 'service' AND ii.service_id = ? "
      'AND i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ? '
      'GROUP BY ii.employee_id, e.full_name '
      'ORDER BY revenue DESC, quantity DESC '
      'LIMIT 5',
      [serviceId, monthStart.toIso8601String(), nextMonth.toIso8601String()],
    );

    final historyRows = await database.rawQuery(
      'SELECT i.id AS invoice_id, i.customer_id, i.paid_at, '
      'c.full_name AS customer_name, ii.employee_id, e.full_name AS employee_name, '
      'ii.quantity, ii.unit_price, ii.discount_amount, ii.total_price '
      'FROM invoice_items ii '
      'JOIN invoices i ON i.id = ii.invoice_id '
      'LEFT JOIN customers c ON c.id = i.customer_id '
      'LEFT JOIN employees e ON e.id = ii.employee_id '
      "WHERE ii.item_type = 'service' AND ii.service_id = ? "
      'AND i.paid_at IS NOT NULL '
      'ORDER BY i.paid_at DESC '
      'LIMIT 20',
      [serviceId],
    );

    final revenue = _toInt(metrics['revenue']);
    final quantity = _toInt(metrics['quantity']);
    final customerCount = _toInt(metrics['customer_count']);
    final lineDiscount = _toInt(metrics['line_discount']);

    return {
      'serviceId': service.id,
      'monthRevenueValue': revenue,
      'monthRevenue': _currency(revenue),
      'monthQuantity': quantity,
      'monthCustomerCount': customerCount,
      'monthLineDiscountValue': lineDiscount,
      'monthLineDiscount': _currency(lineDiscount),
      'topStaff': topStaffRows
          .map(
            (row) => <String, Object?>{
              'employeeId': row['employee_id']?.toString() ?? '',
              'employeeName': row['full_name']?.toString().trim().isNotEmpty == true
                  ? row['full_name'].toString()
                  : 'Chưa gán nhân viên',
              'quantity': _toInt(row['quantity']),
              'revenueValue': _toInt(row['revenue']),
              'revenue': _currency(_toInt(row['revenue'])),
            },
          )
          .toList(growable: false),
      'history': historyRows
          .map((row) {
            final paidAt = DateTime.tryParse(row['paid_at']?.toString() ?? '');
            return <String, Object?>{
              'invoiceId': row['invoice_id']?.toString() ?? '',
              'customerId': row['customer_id']?.toString() ?? '',
              'customerName': row['customer_name']?.toString().trim().isNotEmpty == true
                  ? row['customer_name'].toString()
                  : 'Khách',
              'employeeId': row['employee_id']?.toString() ?? '',
              'employeeName': row['employee_name']?.toString().trim().isNotEmpty == true
                  ? row['employee_name'].toString()
                  : 'Chưa gán nhân viên',
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
          'Doanh thu dùng tổng tiền của dòng dịch vụ đã thanh toán; chiết khấu toàn bill không phân bổ ngược về từng dịch vụ.',
    };
  }

  @override
  Future<ServiceCatalogItem> saveService(
    ServiceUpsertInput input, {
    String? existingId,
  }) async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final existing = existingId == null
        ? null
        : await _findById(database, existingId);
    if (existingId != null && existing == null) {
      throw StateError('Service $existingId not found');
    }

    final now = DateTime.now();
    final service = ServiceCatalogItem.fromUpsertInput(
      id: existing?.id ?? EntityId.create('service'),
      input: input,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    final row = ServiceMapper.toDatabase(service);

    if (existing == null) {
      await database.insert(
        'services',
        row,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final updatedCount = await database.update(
        'services',
        row,
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      if (updatedCount != 1) {
        throw StateError('Service ${existing.id} disappeared during edit');
      }
    }

    return service;
  }

  @override
  Future<ServiceCatalogItem> updateServiceActive(
    String serviceId,
    bool isActive,
  ) async {
    final database = await _database.database;
    await _seed.seedServicesIfNeeded(database);

    final existing = await _findById(database, serviceId);
    if (existing == null) {
      throw StateError('Service $serviceId not found');
    }

    final updated = existing.copyWith(
      isActive: isActive,
      updatedAt: DateTime.now(),
    );

    await database.update(
      'services',
      ServiceMapper.toDatabase(updated),
      where: 'id = ?',
      whereArgs: [serviceId],
    );

    return updated;
  }

  Future<ServiceCatalogItem?> _findById(Database database, String id) async {
    final rows = await database.query(
      'services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ServiceMapper.fromDatabase(rows.first);
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
