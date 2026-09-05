import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/invoice_draft_mapper.dart';
import '../database/invoice_mapper.dart';
import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_draft_line.dart';
import 'invoice_line_actions_repository.dart';
import 'repository_contracts.dart';

class SqliteInvoicesRepository
    implements InvoicesRepository, InvoiceLineActionsRepository {
  SqliteInvoicesRepository(this._database, [Object? _]);

  final SalonDatabase _database;
  static const String _draftInvoiceId = 'invoice-draft-001';
  static const String _draftStateSettingsKey = 'invoice_draft_state_v1';

  @override
  Future<InvoiceDraft> fetchInvoiceDraft() async {
    final database = await _database.database;
    return _loadDraft(database);
  }

  @override
  Future<List<InvoiceDraft>> fetchRecentInvoices({
    int? limit,
    String? customerId,
    String? appointmentId,
  }) async {
    final database = await _database.database;
    final whereClauses = <String>['id != ?', 'paid_at IS NOT NULL'];
    final whereArgs = <Object?>[_draftInvoiceId];

    if (customerId != null && customerId.isNotEmpty) {
      whereClauses.add('customer_id = ?');
      whereArgs.add(customerId);
    }

    if (appointmentId != null && appointmentId.isNotEmpty) {
      whereClauses.add('appointment_id = ?');
      whereArgs.add(appointmentId);
    }

    final invoiceRows = await database.query(
      'invoices',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'paid_at DESC, updated_at DESC',
      limit: limit,
    );

    final results = <InvoiceDraft>[];
    for (final row in invoiceRows) {
      results.add(await _loadInvoiceById(database, row['id'].toString()));
    }
    return results;
  }

  @override
  Future<InvoiceDraft> prefillDraftFromAppointment(
    AppointmentEntry appointment,
  ) async {
    final database = await _database.database;
    final currentDraft = await _loadDraft(database);
    if (currentDraft.lines.isNotEmpty) {
      throw StateError(
        'Bill đang làm đã có dữ liệu. Hãy hoàn tất hoặc xóa bill hiện tại trước khi chuyển lịch sang Tính tiền.',
      );
    }

    final now = DateTime.now();
    final lines = await _buildLinesFromAppointment(database, appointment, now);
    final draft = InvoiceDraft(
      id: _draftInvoiceId,
      appointmentId: appointment.id,
      customerId: appointment.customerId,
      discountAmount: 0,
      paymentMethod: InvoiceDraft.paymentMethods.first,
      paidAt: null,
      createdAt: now,
      updatedAt: now,
      lines: lines,
    );
    return _saveDraft(database, draft, rewriteItems: true);
  }

  Future<List<InvoiceDraftLine>> _buildLinesFromAppointment(
    Database database,
    AppointmentEntry appointment,
    DateTime now,
  ) async {
    if (appointment.services.isNotEmpty) {
      return [
        for (var index = 0; index < appointment.services.length; index++)
          InvoiceDraftLine(
            id: 'line-${now.microsecondsSinceEpoch}-$index',
            invoiceId: _draftInvoiceId,
            itemType: 'service',
            serviceId: appointment.services[index].serviceId,
            productId: null,
            employeeId: appointment.employeeId,
            title: appointment.services[index].title,
            quantity: appointment.services[index].quantity,
            unitPrice: appointment.services[index].unitPrice,
            totalPrice: appointment.services[index].totalPrice,
            discountAmount: 0,
          ),
      ];
    }

    final service = appointment.serviceId == null
        ? await _findServiceByName(database, appointment.serviceName)
        : await _findService(database, appointment.serviceId!);

    return [
      InvoiceDraftLine(
        id: 'line-${now.microsecondsSinceEpoch}',
        invoiceId: _draftInvoiceId,
        itemType: 'service',
        serviceId: service?['id']?.toString(),
        productId: null,
        employeeId: appointment.employeeId,
        title: service?['name']?.toString() ?? appointment.serviceName,
        quantity: 1,
        unitPrice: _toInt(service?['price']),
        totalPrice: _toInt(service?['price']),
        discountAmount: 0,
      ),
    ];
  }

  @override
  Future<InvoiceDraft> selectInvoiceCustomer(String customerId) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final currentCustomerId = draft.customerId.trim();
    final customerChanged =
        currentCustomerId.isNotEmpty && currentCustomerId != customerId;
    if (draft.appointmentId != null && customerChanged) {
      throw StateError(
        'Bill đang gắn với khách của lịch hẹn nên không thể đổi sang khách khác.',
      );
    }
    if (draft.lines.isNotEmpty && customerChanged) {
      throw StateError(
        'Bill đang làm đã có dữ liệu của khách khác. Hãy hoàn tất hoặc xóa bill trước khi đổi khách.',
      );
    }
    return _saveDraft(
      database,
      draft.copyWith(customerId: customerId, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoicePaymentMethod(String paymentMethod) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    return _saveDraft(
      database,
      draft.copyWith(
        paymentMethod: InvoiceDraft.normalizePaymentMethod(paymentMethod),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceDiscount(int discountAmount) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final normalizedDiscount = _normalizeDiscount(
      discountAmount,
      draft.subtotal,
    );
    return _saveDraft(
      database,
      draft.copyWith(
        discountAmount: normalizedDiscount,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> addInvoiceService(
    String serviceId, {
    String? employeeId,
  }) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final service = await _findService(database, serviceId);
    if (service == null) {
      throw StateError('Service $serviceId not found');
    }

    final existingIndex = draft.lines.indexWhere(
      (line) =>
          line.serviceId == serviceId && line.employeeId == employeeId,
    );
    final now = DateTime.now();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);

    if (existingIndex >= 0) {
      final existing = updatedLines[existingIndex];
      final quantity = existing.quantity + 1;
      updatedLines[existingIndex] = existing.copyWith(
        quantity: quantity,
        totalPrice: _lineTotal(
          existing.unitPrice * quantity,
          existing.discountAmount,
        ),
        employeeId: employeeId ?? existing.employeeId,
      );
    } else {
      updatedLines.add(
        InvoiceDraftLine(
          id: 'line-${now.microsecondsSinceEpoch}',
          invoiceId: draft.id,
          itemType: 'service',
          serviceId: serviceId,
          productId: null,
          employeeId: employeeId,
          title: service['name'].toString(),
          quantity: 1,
          unitPrice: _toInt(service['price']),
          totalPrice: _toInt(service['price']),
          discountAmount: 0,
        ),
      );
    }

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: now,
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> addInvoiceProduct(String productId) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final rows = await database.query(
      'retail_products',
      where: 'id = ? AND is_active = 1',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Product $productId not found or inactive');
    }
    final product = rows.first;

    final existingIndex = draft.lines.indexWhere(
      (line) => line.isProduct && line.productId == productId,
    );
    final now = DateTime.now();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);

    if (existingIndex >= 0) {
      final existing = updatedLines[existingIndex];
      final quantity = existing.quantity + 1;
      updatedLines[existingIndex] = existing.copyWith(
        quantity: quantity,
        totalPrice: _lineTotal(
          existing.unitPrice * quantity,
          existing.discountAmount,
        ),
      );
    } else {
      final unitPrice = _toInt(product['sale_price']);
      updatedLines.add(
        InvoiceDraftLine(
          id: 'line-${now.microsecondsSinceEpoch}',
          invoiceId: draft.id,
          itemType: 'product',
          serviceId: null,
          productId: productId,
          title: product['name'].toString(),
          quantity: 1,
          unitPrice: unitPrice,
          totalPrice: unitPrice,
          discountAmount: 0,
        ),
      );
    }

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: now,
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineQuantity(
    String lineId,
    int quantity,
  ) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final line = updatedLines[index];
    updatedLines[index] = line.copyWith(
      quantity: normalizedQuantity,
      totalPrice: _lineTotal(
        line.unitPrice * normalizedQuantity,
        line.discountAmount,
      ),
    );

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineDiscount(
    String lineId,
    int discountAmount,
  ) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final line = updatedLines[index];
    final subtotal = line.unitPrice * line.quantity;
    final normalizedDiscount = _normalizeDiscount(discountAmount, subtotal);
    updatedLines[index] = line.copyWith(
      discountAmount: normalizedDiscount,
      totalPrice: _lineTotal(subtotal, normalizedDiscount),
    );

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineUnitPrice(
    String lineId,
    int unitPrice,
  ) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    if (draft.isPaid) {
      throw StateError('Hóa đơn đã thanh toán nên không thể sửa giá bán.');
    }
    if (unitPrice <= 0) {
      throw StateError('Giá bán phải lớn hơn 0.');
    }

    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final line = updatedLines[index];
    final subtotal = unitPrice * line.quantity;
    final normalizedLineDiscount = _normalizeDiscount(
      line.discountAmount,
      subtotal,
    );
    updatedLines[index] = line.copyWith(
      unitPrice: unitPrice,
      discountAmount: normalizedLineDiscount,
      totalPrice: _lineTotal(subtotal, normalizedLineDiscount),
    );

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> splitInvoiceLine(String lineId) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    if (draft.isPaid) {
      throw StateError('Hóa đơn đã thanh toán nên không thể tách dòng.');
    }

    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final line = draft.lines[index];
    if (line.quantity < 2) {
      throw StateError('Dòng cần có số lượng từ 2 để tách.');
    }

    final splitDiscount = line.discountAmount ~/ line.quantity;
    final remainingDiscount = line.discountAmount - splitDiscount;
    final remainingQuantity = line.quantity - 1;
    final now = DateTime.now();
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);

    updatedLines[index] = line.copyWith(
      quantity: remainingQuantity,
      discountAmount: remainingDiscount,
      totalPrice: _lineTotal(
        line.unitPrice * remainingQuantity,
        remainingDiscount,
      ),
    );
    updatedLines.insert(
      index + 1,
      line.copyWith(
        id: '$lineId-split-${now.microsecondsSinceEpoch}',
        quantity: 1,
        discountAmount: splitDiscount,
        totalPrice: _lineTotal(line.unitPrice, splitDiscount),
      ),
    );

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: now,
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> removeInvoiceLine(String lineId) async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final updatedLines = draft.lines
        .where((line) => line.id != lineId)
        .toList(growable: false);

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(updatedLines),
        ),
        updatedAt: DateTime.now(),
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> checkoutInvoice() async {
    final database = await _database.database;
    final draft = await _loadDraft(database);
    if (draft.customerId.trim().isEmpty) {
      throw StateError('Chọn khách hàng trước khi thanh toán.');
    }
    if (draft.lines.isEmpty) {
      throw StateError('Hóa đơn chưa có dịch vụ hoặc sản phẩm.');
    }
    return _archiveAndResetDraft(database, draft);
  }

  Future<InvoiceDraft> _loadDraft(Database database) async {
    final invoiceRows = await database.query(
      'invoices',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: const [_draftInvoiceId],
      limit: 1,
    );
    if (invoiceRows.isNotEmpty) {
      return _loadInvoiceById(database, _draftInvoiceId);
    }

    final stateRows = await database.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_draftStateSettingsKey],
      limit: 1,
    );
    if (stateRows.isNotEmpty) {
      final raw = stateRows.first['value']?.toString() ?? '';
      if (raw.isNotEmpty) {
        return _decodeDraftState(raw);
      }
    }

    return _newEmptyDraft();
  }

  InvoiceDraft _newEmptyDraft() {
    final now = DateTime.now();
    return InvoiceDraft(
      id: _draftInvoiceId,
      appointmentId: null,
      customerId: '',
      discountAmount: 0,
      paymentMethod: InvoiceDraft.paymentMethods.first,
      paidAt: null,
      createdAt: now,
      updatedAt: now,
      lines: const [],
    );
  }

  Future<InvoiceDraft> _loadInvoiceById(
    Database database,
    String invoiceId,
  ) async {
    final invoiceRows = await database.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (invoiceRows.isEmpty) {
      throw StateError('Invoice $invoiceId not found');
    }

    final rows = await database.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    final lines = rows
        .map(InvoiceDraftMapper.fromDatabase)
        .toList(growable: false);
    return InvoiceMapper.fromDatabase(invoiceRows.first, lines: lines);
  }

  Future<InvoiceDraft> _saveDraft(
    Database database,
    InvoiceDraft draft, {
    bool rewriteItems = false,
  }) async {
    if (draft.customerId.trim().isEmpty) {
      await database.transaction((transaction) async {
        await transaction.delete(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [draft.id],
        );
        await transaction.delete(
          'invoices',
          where: 'id = ? AND paid_at IS NULL',
          whereArgs: [draft.id],
        );
        await transaction.insert(
          'app_settings',
          {
            'key': _draftStateSettingsKey,
            'value': _encodeDraftState(draft),
            'updated_at': draft.updatedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      return draft;
    }

    await database.transaction((transaction) async {
      final existingRows = await transaction.query(
        'invoices',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [draft.id],
        limit: 1,
      );
      final isNewDraft = existingRows.isEmpty;

      if (isNewDraft) {
        await transaction.insert(
          'invoices',
          InvoiceMapper.toDatabase(draft),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        await transaction.update(
          'invoices',
          InvoiceMapper.toDatabase(draft),
          where: 'id = ?',
          whereArgs: [draft.id],
        );
      }

      if (rewriteItems || isNewDraft) {
        await transaction.delete(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [draft.id],
        );
        for (final line in draft.lines) {
          await transaction.insert(
            'invoice_items',
            InvoiceDraftMapper.toDatabase(line),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const [_draftStateSettingsKey],
      );
    });

    return _loadInvoiceById(database, draft.id);
  }

  Future<InvoiceDraft> _archiveAndResetDraft(
    Database database,
    InvoiceDraft draft,
  ) async {
    final now = DateTime.now();
    final archivedInvoiceId = 'invoice-${now.microsecondsSinceEpoch}';
    final archivedDraft = draft.copyWith(
      id: archivedInvoiceId,
      paidAt: now,
      createdAt: draft.createdAt,
      updatedAt: now,
      lines: draft.lines,
    );

    await database.transaction((transaction) async {
      await transaction.insert(
        'invoices',
        InvoiceMapper.toDatabase(archivedDraft),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final line in draft.lines) {
        final archivedLine = line.copyWith(
          id: 'line-$archivedInvoiceId-${line.id}',
          invoiceId: archivedInvoiceId,
        );
        await transaction.insert(
          'invoice_items',
          InvoiceDraftMapper.toDatabase(archivedLine),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (draft.appointmentId != null) {
        await transaction.update(
          'appointments',
          {'status': 'Hoàn thành', 'updated_at': now.toIso8601String()},
          where: 'id = ?',
          whereArgs: [draft.appointmentId],
        );
      }

      await _applyCustomerCheckoutMetrics(transaction, draft, now);

      await transaction.delete(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: const [_draftInvoiceId],
      );
      final deletedDrafts = await transaction.delete(
        'invoices',
        where: 'id = ? AND paid_at IS NULL',
        whereArgs: const [_draftInvoiceId],
      );
      if (deletedDrafts != 1) {
        throw StateError('Invoice draft disappeared during checkout.');
      }
      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: const [_draftStateSettingsKey],
      );
    });

    return _loadDraft(database);
  }

  Future<void> _applyCustomerCheckoutMetrics(
    DatabaseExecutor database,
    InvoiceDraft draft,
    DateTime paidAt,
  ) async {
    final earnedPoints = draft.totalAmount ~/ 10000;
    final customerRows = await database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [draft.customerId],
      limit: 1,
    );

    if (customerRows.isNotEmpty) {
      final existing = customerRows.first;
      await database.update(
        'customers',
        {
          'loyalty_points': _toInt(existing['loyalty_points']) + earnedPoints,
          'last_visit_at': paidAt.toIso8601String(),
          'visit_count': _toInt(existing['visit_count']) + 1,
          'total_spent': _toInt(existing['total_spent']) + draft.totalAmount,
          'updated_at': paidAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [draft.customerId],
      );
      return;
    }

    final appointmentRow = draft.appointmentId == null
        ? null
        : await _findAppointment(database, draft.appointmentId!);
    if (appointmentRow == null) {
      return;
    }

    await database.insert(
      'customers',
      {
        'id': draft.customerId,
        'full_name': appointmentRow['customer_name']?.toString() ?? 'Khách mới',
        'phone': appointmentRow['customer_phone']?.toString() ?? '',
        'email': null,
        'tier': 'Member',
        'loyalty_points': earnedPoints,
        'favorite_service': appointmentRow['service_name']?.toString() ?? '',
        'last_visit_at': paidAt.toIso8601String(),
        'hair_profile': '',
        'visit_count': 1,
        'total_spent': draft.totalAmount,
        'notes': appointmentRow['note']?.toString() ?? '',
        'created_at': paidAt.toIso8601String(),
        'updated_at': paidAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _encodeDraftState(InvoiceDraft draft) {
    return jsonEncode({
      'id': draft.id,
      'appointmentId': draft.appointmentId,
      'customerId': draft.customerId,
      'discountAmount': draft.discountAmount,
      'paymentMethod': draft.paymentMethod,
      'paidAt': draft.paidAt?.toIso8601String(),
      'createdAt': draft.createdAt.toIso8601String(),
      'updatedAt': draft.updatedAt.toIso8601String(),
      'lines': [
        for (final line in draft.lines)
          {
            'id': line.id,
            'invoiceId': line.invoiceId,
            'itemType': line.itemType,
            'serviceId': line.serviceId,
            'productId': line.productId,
            'employeeId': line.employeeId,
            'title': line.title,
            'quantity': line.quantity,
            'unitPrice': line.unitPrice,
            'discountAmount': line.discountAmount,
            'totalPrice': line.totalPrice,
          },
      ],
    });
  }

  InvoiceDraft _decodeDraftState(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invoice draft state is invalid.');
    }
    final rawLines = decoded['lines'];
    if (rawLines is! List) {
      throw StateError('Invoice draft lines are invalid.');
    }

    final createdAt =
        DateTime.tryParse(decoded['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final updatedAt =
        DateTime.tryParse(decoded['updatedAt']?.toString() ?? '') ?? createdAt;
    final paidAtRaw = decoded['paidAt']?.toString();
    final paidAt = paidAtRaw == null || paidAtRaw.isEmpty
        ? null
        : DateTime.tryParse(paidAtRaw);

    final lines = <InvoiceDraftLine>[];
    for (final rawLine in rawLines) {
      if (rawLine is! Map) {
        throw StateError('Invoice draft line state is invalid.');
      }
      lines.add(
        InvoiceDraftLine(
          id: rawLine['id']?.toString() ?? '',
          invoiceId: rawLine['invoiceId']?.toString() ?? _draftInvoiceId,
          itemType: rawLine['itemType']?.toString() ?? 'service',
          serviceId: rawLine['serviceId']?.toString(),
          productId: rawLine['productId']?.toString(),
          employeeId: rawLine['employeeId']?.toString(),
          title: rawLine['title']?.toString() ?? '',
          quantity: _toInt(rawLine['quantity']),
          unitPrice: _toInt(rawLine['unitPrice']),
          discountAmount: _toInt(rawLine['discountAmount']),
          totalPrice: _toInt(rawLine['totalPrice']),
        ),
      );
    }

    return InvoiceDraft(
      id: decoded['id']?.toString() ?? _draftInvoiceId,
      appointmentId: decoded['appointmentId']?.toString(),
      customerId: decoded['customerId']?.toString() ?? '',
      discountAmount: _toInt(decoded['discountAmount']),
      paymentMethod: InvoiceDraft.normalizePaymentMethod(
        decoded['paymentMethod']?.toString() ?? '',
      ),
      paidAt: paidAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lines: lines,
    );
  }

  Future<Map<String, Object?>?> _findService(
    Database database,
    String serviceId,
  ) async {
    final rows = await database.query(
      'services',
      where: 'id = ?',
      whereArgs: [serviceId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findServiceByName(
    Database database,
    String serviceName,
  ) async {
    final rows = await database.query(
      'services',
      where: 'LOWER(name) = ?',
      whereArgs: [serviceName.toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findAppointment(
    DatabaseExecutor database,
    String appointmentId,
  ) async {
    final rows = await database.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [appointmentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  int _normalizeDiscount(int discountAmount, int subtotal) {
    if (discountAmount < 0) return 0;
    if (discountAmount > subtotal) return subtotal;
    return discountAmount;
  }

  int _subtotal(List<InvoiceDraftLine> lines) {
    return lines.fold(0, (sum, line) => sum + line.totalPrice);
  }

  int _lineTotal(int subtotal, int discountAmount) {
    final value = subtotal - discountAmount;
    return value < 0 ? 0 : value;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
