import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'commission_ledger.dart';

import '../database/invoice_draft_mapper.dart';
import '../database/invoice_mapper.dart';
import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_benefit.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_draft_line.dart';
import '../models/invoice_payment_allocation.dart';
import 'invoice_adjustment_repository.dart';
import 'invoice_benefit_checkout.dart';
import 'invoice_line_actions_repository.dart';
import 'repository_contracts.dart';
import '../services/sensitive_action_service.dart';

class SqliteInvoicesRepository
    implements
        InvoicesRepository,
        InvoiceLineActionsRepository,
        InvoiceAdjustmentRepository,
        CheckoutBenefitAuthorizationTarget {
  SqliteInvoicesRepository(
    SalonDatabase database, [
    Object? securityContext,
    String draftInvoiceId = legacyDraftInvoiceId,
  ]) : _database = database,
       _security = securityContext is SensitiveActionService
           ? securityContext
           : SensitiveActionService(database),
       _draftInvoiceId = draftInvoiceId.trim().isEmpty
           ? legacyDraftInvoiceId
           : draftInvoiceId.trim();

  static const String legacyDraftInvoiceId = 'invoice-draft-001';
  static const String legacyDraftStateSettingsKey = 'invoice_draft_state_v1';
  static const String sessionDraftStateSettingsPrefix =
      'invoice_draft_state_v2:';

  final SalonDatabase _database;
  final SensitiveActionService _security;
  final String _draftInvoiceId;

  InvoiceBenefitCheckout get _benefitCheckout => InvoiceBenefitCheckout(
    _database,
    _security,
    _draftInvoiceId,
  );

  @override
  Future<bool> checkoutRequiresBenefitIssueAuthorization() =>
      _benefitCheckout.requiresIssueAuthorization();

  // Result metadata for a caller joining checkout to its outer transaction.
  String? _lastArchivedInvoiceId;
  String? get lastArchivedInvoiceId => _lastArchivedInvoiceId;

  Future<InvoiceDraft> _mutate(Future<InvoiceDraft> Function(SqliteInvoicesRepository repo) action) =>
    _database.inTransaction((scope) async {
      final repo = SqliteInvoicesRepository(
        scope,
        _security.forDatabase(scope),
        _draftInvoiceId,
      );
      final result = await action(repo);
      _lastArchivedInvoiceId = repo.lastArchivedInvoiceId;
      return result;
    });

  Future<void> _ensureAppointmentNotPaid(DatabaseExecutor db, String? id) async {
    if (id == null || id.isEmpty) return;
    final paid = await db.rawQuery("SELECT i.id FROM invoices i WHERE i.appointment_id = ? "
      "AND i.paid_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM invoice_adjustments a "
      "WHERE a.invoice_id = i.id AND a.adjustment_type = 'void') LIMIT 1", [id]);
    if (paid.isNotEmpty) throw StateError('Lịch hẹn đã có hóa đơn thanh toán.');
  }

  String get _draftStateSettingsKey =>
      _draftInvoiceId == legacyDraftInvoiceId
      ? legacyDraftStateSettingsKey
      : '$sessionDraftStateSettingsPrefix$_draftInvoiceId';

  @override
  Future<InvoiceDraft> fetchInvoiceDraft() async {
    final database = await _database.database;
    return _loadDraft(database);
  }

  Future<InvoiceDraft> createEmptyDraft() async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.createEmptyDraft());
    final database = await _database.database;
    final current = await _loadDraft(database);
    if (current.lines.isNotEmpty ||
        current.customerId.trim().isNotEmpty ||
        current.appointmentId != null) {
      return current;
    }
    return _saveDraft(
      database,
      current.copyWith(updatedAt: DateTime.now()),
    );
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
  Future<List<InvoiceAdjustment>> fetchInvoiceAdjustments({
    String? invoiceId,
    int? limit,
  }) async {
    final database = await _database.database;
    final normalizedInvoiceId = invoiceId?.trim() ?? '';
    final rows = await database.query(
      'invoice_adjustments',
      where: normalizedInvoiceId.isEmpty ? null : 'invoice_id = ?',
      whereArgs: normalizedInvoiceId.isEmpty ? null : [normalizedInvoiceId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_mapInvoiceAdjustment).toList(growable: false);
  }

  @override
  Future<InvoiceAdjustment> refundInvoice(
    String invoiceId, {
    required String reason,
  }) {
    return _adjustPaidInvoice(
      invoiceId,
      type: InvoiceAdjustmentType.refund,
      reason: reason,
    );
  }

  @override
  Future<InvoiceAdjustment> voidInvoice(
    String invoiceId, {
    required String reason,
  }) {
    return _adjustPaidInvoice(
      invoiceId,
      type: InvoiceAdjustmentType.voided,
      reason: reason,
    );
  }

  @override
  Future<InvoiceDraft> prefillDraftFromAppointment(
    AppointmentEntry appointment,
  ) async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.prefillDraftFromAppointment(appointment));
    final database = await _database.database;
    await _ensureAppointmentNotPaid(database, appointment.id);
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.selectInvoiceCustomer(customerId));
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoicePaymentMethod(paymentMethod));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    return _saveDraft(
      database,
      draft.copyWith(
        paymentMethod: InvoiceDraft.normalizePaymentMethod(paymentMethod),
        clearPaymentAllocations: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoicePaymentAllocations(
    List<InvoicePaymentAllocation> allocations,
  ) async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoicePaymentAllocations(allocations));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final preview = await _benefitCheckout.preview(database, draft);
    final normalized = _normalizePaymentAllocations(
      allocations,
      expectedTotal: preview.cashDue,
    );
    return _saveDraft(
      database,
      draft.copyWith(
        paymentMethod: normalized.first.paymentMethod,
        paymentAllocations: normalized,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceDiscount(int discountAmount) async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoiceDiscount(discountAmount));
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.addInvoiceService(serviceId, employeeId: employeeId));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final service = await _findService(database, serviceId);
    if (service == null) {
      throw StateError('Service $serviceId not found');
    }

    final normalizedEmployeeId = employeeId?.trim();
    final effectiveEmployeeId =
        normalizedEmployeeId == null || normalizedEmployeeId.isEmpty
        ? null
        : normalizedEmployeeId;
    final existingIndex = draft.lines.indexWhere(
      (line) =>
          line.serviceId == serviceId &&
          line.employeeId == effectiveEmployeeId,
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
        employeeId: effectiveEmployeeId ?? existing.employeeId,
      );
    } else {
      updatedLines.add(
        InvoiceDraftLine(
          id: 'line-${now.microsecondsSinceEpoch}',
          invoiceId: draft.id,
          itemType: 'service',
          serviceId: serviceId,
          productId: null,
          employeeId: effectiveEmployeeId,
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.addInvoiceProduct(productId));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final rows = await database.rawQuery(
      'SELECT p.*, COALESCE(s.stock_on_hand, 0) AS stock_on_hand '
      'FROM retail_products p '
      'LEFT JOIN inventory_stock s ON s.product_id = p.id '
      'WHERE p.id = ? AND p.is_active = 1 LIMIT 1',
      [productId],
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

  Future<InvoiceDraft> addBenefitPurchaseLine({
    required String lineId,
    required String itemType,
    required String title,
    required int unitPrice,
  }) async {
    if (!_database.isTransactionScoped) {
      return _mutate(
        (repo) => repo.addBenefitPurchaseLine(
          lineId: lineId,
          itemType: itemType,
          title: title,
          unitPrice: unitPrice,
        ),
      );
    }
    if (itemType != 'membership_purchase' &&
        itemType != 'service_package_purchase') {
      throw ArgumentError('Loại dòng mua quyền lợi không hợp lệ.');
    }
    final normalizedId = lineId.trim();
    final normalizedTitle = title.trim();
    if (normalizedId.isEmpty ||
        normalizedTitle.isEmpty ||
        unitPrice <= 0) {
      throw ArgumentError('Dữ liệu dòng mua quyền lợi không hợp lệ.');
    }
    final database = await _database.database;
    final draft = await _loadDraft(database);
    if (draft.customerId.trim().isEmpty) {
      throw StateError('Chọn khách hàng trước khi mua quyền lợi.');
    }
    if (draft.lines.any((line) => line.id == normalizedId)) {
      throw StateError('Mã dòng mua quyền lợi đã tồn tại.');
    }
    final line = InvoiceDraftLine(
      id: normalizedId,
      invoiceId: draft.id,
      itemType: itemType,
      serviceId: null,
      productId: null,
      employeeId: null,
      title: normalizedTitle,
      quantity: 1,
      unitPrice: unitPrice,
      discountAmount: 0,
      totalPrice: unitPrice,
    );
    final lines = [...draft.lines, line];
    return _saveDraft(
      database,
      draft.copyWith(
        lines: lines,
        discountAmount: _normalizeDiscount(
          draft.discountAmount,
          _subtotal(lines),
        ),
        updatedAt: DateTime.now(),
      ),
      rewriteItems: true,
    );
  }

  @override
  Future<InvoiceDraft> updateInvoiceLineQuantity(
    String lineId,
    int quantity,
  ) async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoiceLineQuantity(lineId, quantity));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final line = updatedLines[index];
    if (_isBenefitPurchaseLine(line) && normalizedQuantity != 1) {
      throw StateError('Dòng mua quyền lợi luôn có số lượng 1.');
    }
    if (line.isProduct) {
      final productId = line.productId?.trim() ?? '';
      if (productId.isEmpty) {
        throw StateError('Dòng sản phẩm không có mã sản phẩm.');
      }
      await _ensureProductExists(database, productId: productId);
    }
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoiceLineDiscount(lineId, discountAmount));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    final line = updatedLines[index];
    if (_isBenefitPurchaseLine(line) && discountAmount != 0) {
      throw StateError('Dòng mua quyền lợi không hỗ trợ giảm giá dòng.');
    }
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
  Future<InvoiceDraft> updateInvoiceLineEmployee(
    String lineId,
    String? employeeId,
  ) async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoiceLineEmployee(lineId, employeeId));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    if (draft.isPaid) {
      throw StateError(
        'Hóa đơn đã thanh toán nên không thể đổi nhân viên thực hiện.',
      );
    }

    final normalizedEmployeeId = employeeId?.trim() ?? '';

    final index = draft.lines.indexWhere((line) => line.id == lineId);
    if (index < 0) {
      throw StateError('Invoice line $lineId not found');
    }

    final line = draft.lines[index];
    if (!line.isService) {
      throw StateError('Chỉ dòng dịch vụ mới gắn nhân viên thực hiện.');
    }

    final updatedLines = List<InvoiceDraftLine>.from(draft.lines);
    updatedLines[index] = normalizedEmployeeId.isEmpty
        ? line.copyWith(clearEmployeeId: true)
        : line.copyWith(employeeId: normalizedEmployeeId);

    return _saveDraft(
      database,
      draft.copyWith(
        lines: updatedLines,
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.updateInvoiceLineUnitPrice(lineId, unitPrice));
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
    if (_isBenefitPurchaseLine(line)) {
      throw StateError('Giá plan quyền lợi phải lấy từ cấu hình hiện hành.');
    }
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.splitInvoiceLine(lineId));
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
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.removeInvoiceLine(lineId));
    final database = await _database.database;
    final draft = await _loadDraft(database);
    final updatedLines = draft.lines
        .where((line) => line.id != lineId)
        .toList(growable: false);

    final saved = await _saveDraft(
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
    final intent = await _benefitCheckout.loadIntent(database);
    await _benefitCheckout.saveIntent(
      database,
      intent.copyWith(
        packageRedemptions: intent.packageRedemptions
            .where((item) => item.lineId != lineId)
            .toList(growable: false),
        purchases: intent.purchases
            .where((item) => item.lineId != lineId)
            .toList(growable: false),
      ),
    );
    return saved;
  }

  @override
  Future<InvoiceDraft> checkoutInvoice() async {
    if (!_database.isTransactionScoped) return _mutate((repo) => repo.checkoutInvoice());
    final database = await _database.database;
    final draft = await _loadDraft(database);
    await _ensureAppointmentNotPaid(database, draft.appointmentId);
    if (draft.customerId.trim().isEmpty) {
      throw StateError('Chọn khách hàng trước khi thanh toán.');
    }
    if (draft.lines.isEmpty) {
      throw StateError('Hóa đơn chưa có dịch vụ hoặc sản phẩm.');
    }
    final preview = await _benefitCheckout.preview(database, draft);
    _ensureCheckoutPaymentAllocations(
      draft,
      expectedTotal: preview.cashDue,
    );
    return _archiveAndResetDraft(database, draft, preview);
  }

  Future<InvoiceAdjustment> _adjustPaidInvoice(
    String invoiceId, {
    required InvoiceAdjustmentType type,
    required String reason,
  }) async {
    if (!_database.isTransactionScoped) {
      return _database.inTransaction(
        (scope) => SqliteInvoicesRepository(
          scope,
          _security.forDatabase(scope),
          _draftInvoiceId,
        )._adjustPaidInvoice(
          invoiceId,
          type: type,
          reason: reason,
        ),
      );
    }
    final normalizedInvoiceId = invoiceId.trim();
    final normalizedReason = reason.trim();
    if (normalizedInvoiceId.isEmpty) {
      throw StateError('Không xác định được hóa đơn cần điều chỉnh.');
    }
    if (normalizedReason.isEmpty) {
      throw StateError('Bắt buộc nhập lý do hoàn tiền hoặc hủy giao dịch.');
    }

    final database = await _database.database;
    return database.transaction((transaction) async {
      final invoiceRows = await transaction.query(
        'invoices',
        where: 'id = ? AND paid_at IS NOT NULL',
        whereArgs: [normalizedInvoiceId],
        limit: 1,
      );
      if (invoiceRows.isEmpty) {
        throw StateError('Chỉ hóa đơn đã thanh toán mới được điều chỉnh.');
      }

      final existingAdjustments = await transaction.query(
        'invoice_adjustments',
        columns: const ['adjustment_type'],
        where: 'invoice_id = ?',
        whereArgs: [normalizedInvoiceId],
        limit: 1,
      );
      if (existingAdjustments.isNotEmpty) {
        final existingType = InvoiceAdjustmentType.fromDatabase(
          existingAdjustments.first['adjustment_type']?.toString() ?? '',
        );
        throw StateError(
          'Hóa đơn này ${existingType.statusLabel.toLowerCase()} nên không thể điều chỉnh lần nữa.',
        );
      }

      final invoice = invoiceRows.first;
      final now = DateTime.now();
      final customerId = invoice['customer_id']?.toString() ?? '';
      final appointmentId = _nullableId(invoice['appointment_id']);
      final totalAmount = _toInt(invoice['total_amount']);
      final paymentSummary = await _paymentSummaryForInvoice(
        transaction,
        normalizedInvoiceId,
        invoice['payment_method']?.toString() ?? '',
      );
      await _benefitCheckout.applyAdjustment(
        transaction,
        invoiceId: normalizedInvoiceId,
        isVoid: type == InvoiceAdjustmentType.voided,
      );

      final adjustment = InvoiceAdjustment(
        id: 'invoice-adjustment-${now.microsecondsSinceEpoch}',
        invoiceId: normalizedInvoiceId,
        type: type,
        reason: normalizedReason,
        amount: totalAmount,
        paymentMethod: paymentSummary,
        customerId: customerId,
        appointmentId: appointmentId,
        createdAt: now,
      );

      await transaction.insert(
        'invoice_adjustments',
        {
          'id': adjustment.id,
          'invoice_id': adjustment.invoiceId,
          'adjustment_type': adjustment.type.databaseValue,
          'reason': adjustment.reason,
          'amount': adjustment.amount,
          'payment_method': adjustment.paymentMethod,
          'customer_id': adjustment.customerId,
          'appointment_id': adjustment.appointmentId,
          'created_at': adjustment.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (type == InvoiceAdjustmentType.voided) {
        await _restoreInventoryForVoidedInvoice(
          transaction,
          normalizedInvoiceId,
          now,
        );
      }

      await CommissionLedger.reverse(transaction, normalizedInvoiceId, now);
      await _reverseCustomerCheckoutMetrics(transaction, adjustment);
      return adjustment;
    });
  }

  Future<void> _reverseCustomerCheckoutMetrics(
    DatabaseExecutor database,
    InvoiceAdjustment adjustment,
  ) async {
    if (adjustment.customerId.trim().isEmpty) {
      return;
    }

    final customerRows = await database.query(
      'customers',
      where: 'id = ?',
      whereArgs: [adjustment.customerId],
      limit: 1,
    );
    if (customerRows.isEmpty) {
      return;
    }

    final existing = customerRows.first;
    final earnedPoints = adjustment.amount ~/ 10000;
    final reducedPoints = _toInt(existing['loyalty_points']) - earnedPoints;
    final reducedSpent = _toInt(existing['total_spent']) - adjustment.amount;
    final values = <String, Object?>{
      'loyalty_points': reducedPoints < 0 ? 0 : reducedPoints,
      'total_spent': reducedSpent < 0 ? 0 : reducedSpent,
      'updated_at': adjustment.createdAt.toIso8601String(),
    };

    if (adjustment.type == InvoiceAdjustmentType.voided) {
      final reducedVisits = _toInt(existing['visit_count']) - 1;
      final lastVisitRows = await database.rawQuery(
        'SELECT MAX(i.paid_at) AS last_paid_at '
        'FROM invoices i '
        'WHERE i.customer_id = ? AND i.paid_at IS NOT NULL '
        'AND NOT EXISTS ('
        "SELECT 1 FROM invoice_adjustments ia "
        "WHERE ia.invoice_id = i.id AND ia.adjustment_type = 'void'"
        ')',
        [adjustment.customerId],
      );
      values['visit_count'] = reducedVisits < 0 ? 0 : reducedVisits;
      values['last_visit_at'] = lastVisitRows.isEmpty
          ? null
          : lastVisitRows.first['last_paid_at']?.toString();
    }

    await database.update(
      'customers',
      values,
      where: 'id = ?',
      whereArgs: [adjustment.customerId],
    );
  }

  InvoiceAdjustment _mapInvoiceAdjustment(Map<String, Object?> row) {
    return InvoiceAdjustment(
      id: row['id']?.toString() ?? '',
      invoiceId: row['invoice_id']?.toString() ?? '',
      type: InvoiceAdjustmentType.fromDatabase(
        row['adjustment_type']?.toString() ?? '',
      ),
      reason: row['reason']?.toString() ?? '',
      amount: _toInt(row['amount']),
      paymentMethod: row['payment_method']?.toString() ?? '',
      customerId: row['customer_id']?.toString() ?? '',
      appointmentId: _nullableId(row['appointment_id']),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<InvoiceDraft> _loadDraft(Database database) async {
    final invoiceRows = await database.query(
      'invoices',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [_draftInvoiceId],
      limit: 1,
    );
    if (invoiceRows.isNotEmpty) {
      return _loadInvoiceById(database, _draftInvoiceId);
    }

    final stateRows = await database.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [_draftStateSettingsKey],
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
    final paymentRows = await database.query(
      'invoice_payments',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    final paymentAllocations = paymentRows
        .map(
          (row) => InvoicePaymentAllocation(
            paymentMethod: InvoiceDraft.normalizePaymentMethod(
              row['payment_method']?.toString() ?? '',
            ),
            amount: _toInt(row['amount']),
          ),
        )
        .toList(growable: false);
    return InvoiceMapper.fromDatabase(
      invoiceRows.first,
      lines: lines,
      paymentAllocations: paymentAllocations,
    );
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

      await _replaceDraftPaymentAllocations(transaction, draft);

      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_draftStateSettingsKey],
      );
    });

    return _loadInvoiceById(database, draft.id);
  }

  Future<InvoiceDraft> _archiveAndResetDraft(
    Database database,
    InvoiceDraft draft,
    InvoiceBenefitPreview benefitPreview,
  ) async {
    final now = DateTime.now();
    _lastArchivedInvoiceId = null;
    final archivedInvoiceId = 'invoice-${now.microsecondsSinceEpoch}';
    final archiveDiscount = draft.subtotal - benefitPreview.cashDue;
    if (archiveDiscount < 0) {
      throw StateError('Tổng tiền quyền lợi không hợp lệ.');
    }
    final archivedDraft = draft.copyWith(
      id: archivedInvoiceId,
      discountAmount: archiveDiscount,
      paidAt: now,
      createdAt: draft.createdAt,
      updatedAt: now,
      lines: draft.lines,
    );

    await database.transaction((transaction) async {
      await _deductInventoryForCheckout(
        transaction,
        draft,
        archivedInvoiceId,
        now,
      );

      await transaction.insert(
        'invoices',
        InvoiceMapper.toDatabase(archivedDraft),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _insertArchivedPaymentAllocations(
        transaction,
        archivedDraft,
        now,
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

      await _benefitCheckout.commit(
        transaction,
        draft: draft,
        invoiceId: archivedInvoiceId,
        preview: benefitPreview,
      );
      await CommissionLedger.capture(transaction, archivedInvoiceId, now);
      await _applyCustomerCheckoutMetrics(transaction, archivedDraft, now);

      await transaction.delete(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [_draftInvoiceId],
      );
      final deletedDrafts = await transaction.delete(
        'invoices',
        where: 'id = ? AND paid_at IS NULL',
        whereArgs: [_draftInvoiceId],
      );
      if (deletedDrafts != 1) {
        throw StateError('Invoice draft disappeared during checkout.');
      }
      await transaction.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_draftStateSettingsKey],
      );
    });

    _lastArchivedInvoiceId = archivedInvoiceId;
    return _loadDraft(database);
  }


  Future<void> _replaceDraftPaymentAllocations(
    DatabaseExecutor database,
    InvoiceDraft draft,
  ) async {
    await database.delete(
      'invoice_payments',
      where: 'invoice_id = ?',
      whereArgs: [draft.id],
    );
    if (draft.paymentAllocations.isEmpty) {
      return;
    }
    await _insertInvoicePaymentAllocations(
      database,
      invoiceId: draft.id,
      allocations: draft.paymentAllocations,
      createdAt: draft.updatedAt,
    );
  }

  Future<void> _insertArchivedPaymentAllocations(
    DatabaseExecutor database,
    InvoiceDraft draft,
    DateTime createdAt,
  ) async {
    if (draft.totalAmount <= 0) {
      return;
    }
    await _insertInvoicePaymentAllocations(
      database,
      invoiceId: draft.id,
      allocations: draft.effectivePaymentAllocations,
      createdAt: createdAt,
    );
  }

  Future<void> _insertInvoicePaymentAllocations(
    DatabaseExecutor database, {
    required String invoiceId,
    required List<InvoicePaymentAllocation> allocations,
    required DateTime createdAt,
  }) async {
    for (var index = 0; index < allocations.length; index++) {
      final allocation = allocations[index];
      await database.insert(
        'invoice_payments',
        {
          'id': 'payment-$invoiceId-$index',
          'invoice_id': invoiceId,
          'payment_method': allocation.paymentMethod,
          'amount': allocation.amount,
          'created_at': createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  List<InvoicePaymentAllocation> _normalizePaymentAllocations(
    List<InvoicePaymentAllocation> allocations, {
    required int expectedTotal,
  }) {
    final normalized = <InvoicePaymentAllocation>[];
    final seen = <String>{};

    for (final allocation in allocations) {
      String? method;
      final rawMethod = allocation.paymentMethod.trim().toLowerCase();
      for (final candidate in InvoiceDraft.paymentMethods) {
        if (candidate.toLowerCase() == rawMethod) {
          method = candidate;
          break;
        }
      }
      if (method == null) {
        throw StateError('Phương thức thanh toán không hợp lệ.');
      }
      if (allocation.amount <= 0) {
        throw StateError('Số tiền của mỗi phương thức phải lớn hơn 0.');
      }
      if (!seen.add(method)) {
        throw StateError('Mỗi phương thức chỉ được xuất hiện một lần.');
      }
      normalized.add(
        InvoicePaymentAllocation(
          paymentMethod: method,
          amount: allocation.amount,
        ),
      );
    }

    if (normalized.length < 2) {
      throw StateError('Chia thanh toán cần ít nhất hai phương thức.');
    }
    final total = normalized.fold(
      0,
      (sum, allocation) => sum + allocation.amount,
    );
    if (total != expectedTotal) {
      throw StateError('Tổng số tiền chia phải bằng tổng hóa đơn.');
    }
    return normalized;
  }

  void _ensureCheckoutPaymentAllocations(
    InvoiceDraft draft, {
    required int expectedTotal,
  }) {
    if (draft.paymentAllocations.isEmpty) {
      return;
    }
    _normalizePaymentAllocations(
      draft.paymentAllocations,
      expectedTotal: expectedTotal,
    );
  }

  Future<String> _paymentSummaryForInvoice(
    DatabaseExecutor database,
    String invoiceId,
    String fallbackMethod,
  ) async {
    final rows = await database.query(
      'invoice_payments',
      columns: const ['payment_method'],
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'id ASC',
    );
    if (rows.isEmpty) {
      return InvoiceDraft.normalizePaymentMethod(fallbackMethod);
    }
    return rows
        .map(
          (row) => InvoiceDraft.normalizePaymentMethod(
            row['payment_method']?.toString() ?? '',
          ),
        )
        .join(' + ');
  }

  Future<void> _deductInventoryForCheckout(
    DatabaseExecutor database,
    InvoiceDraft draft,
    String invoiceId,
    DateTime now,
  ) async {
    final quantities = <String, int>{};
    for (final line in draft.lines) {
      if (!line.isProduct) continue;
      final productId = line.productId?.trim() ?? '';
      if (productId.isEmpty) {
        throw StateError('Dòng sản phẩm không có mã sản phẩm.');
      }
      quantities.update(
        productId,
        (current) => current + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }

    for (final entry in quantities.entries) {
      final rows = await database.rawQuery(
        'SELECT p.name, COALESCE(s.stock_on_hand, 0) AS stock_on_hand '
        'FROM retail_products p '
        'LEFT JOIN inventory_stock s ON s.product_id = p.id '
        'WHERE p.id = ? LIMIT 1',
        [entry.key],
      );
      if (rows.isEmpty) {
        throw StateError('Sản phẩm ${entry.key} không còn trong danh mục.');
      }

      final before = _toInt(rows.first['stock_on_hand']);
      final after = before - entry.value;
      final updated = await database.update(
        'inventory_stock',
        {
          'stock_on_hand': after,
          'updated_at': now.toIso8601String(),
        },
        where: 'product_id = ?',
        whereArgs: [entry.key],
      );
      if (updated == 0) {
        await database.insert('inventory_stock', {
          'product_id': entry.key,
          'stock_on_hand': after,
          'updated_at': now.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      } else if (updated != 1) {
        throw StateError('Không thể cập nhật tồn cho sản phẩm ${entry.key}.');
      }

      await database.insert(
        'inventory_movements',
        {
          'id': _saleMovementId(invoiceId, entry.key),
          'product_id': entry.key,
          'movement_type': 'sale',
          'quantity_delta': -entry.value,
          'stock_before': before,
          'stock_after': after,
          'note': 'Bán theo hóa đơn $invoiceId',
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<void> _restoreInventoryForVoidedInvoice(
    DatabaseExecutor database,
    String invoiceId,
    DateTime now,
  ) async {
    final productRows = await database.rawQuery(
      'SELECT DISTINCT product_id FROM invoice_items '
      "WHERE invoice_id = ? AND item_type = 'product' "
      'AND product_id IS NOT NULL',
      [invoiceId],
    );

    for (final row in productRows) {
      final productId = row['product_id']?.toString().trim() ?? '';
      if (productId.isEmpty) continue;

      final saleRows = await database.query(
        'inventory_movements',
        where: 'id = ? AND product_id = ? AND movement_type = ?',
        whereArgs: [_saleMovementId(invoiceId, productId), productId, 'sale'],
        limit: 1,
      );
      if (saleRows.isEmpty) continue;

      final soldQuantity = -_toInt(saleRows.first['quantity_delta']);
      if (soldQuantity <= 0) continue;

      final stockRows = await database.query(
        'inventory_stock',
        columns: const ['stock_on_hand'],
        where: 'product_id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final before = stockRows.isEmpty
          ? 0
          : _toInt(stockRows.first['stock_on_hand']);
      final after = before + soldQuantity;
      final values = <String, Object?>{
        'product_id': productId,
        'stock_on_hand': after,
        'updated_at': now.toIso8601String(),
      };

      if (stockRows.isEmpty) {
        await database.insert(
          'inventory_stock',
          values,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        final updated = await database.update(
          'inventory_stock',
          values,
          where: 'product_id = ?',
          whereArgs: [productId],
        );
        if (updated != 1) {
          throw StateError('Không thể hoàn tồn cho sản phẩm $productId.');
        }
      }

      await database.insert(
        'inventory_movements',
        {
          'id': _voidMovementId(invoiceId, productId),
          'product_id': productId,
          'movement_type': 'void',
          'quantity_delta': soldQuantity,
          'stock_before': before,
          'stock_after': after,
          'note': 'Hoàn tồn do hủy hóa đơn $invoiceId',
          'created_at': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }
  }

  Future<void> _ensureProductExists(
    DatabaseExecutor database, {
    required String productId,
  }) async {
    final rows = await database.query('retail_products',
        columns: const ['id'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Sản phẩm $productId không còn trong danh mục.');
    }
  }

  String _saleMovementId(String invoiceId, String productId) =>
      'stock-sale-$invoiceId-$productId';

  String _voidMovementId(String invoiceId, String productId) =>
      'stock-void-$invoiceId-$productId';

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
      'paymentAllocations': [
        for (final allocation in draft.paymentAllocations)
          {
            'paymentMethod': allocation.paymentMethod,
            'amount': allocation.amount,
          },
      ],
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

    final paymentAllocations = <InvoicePaymentAllocation>[];
    final rawPaymentAllocations = decoded['paymentAllocations'];
    if (rawPaymentAllocations is List) {
      for (final rawPayment in rawPaymentAllocations) {
        if (rawPayment is! Map) continue;
        final amount = _toInt(rawPayment['amount']);
        if (amount <= 0) continue;
        paymentAllocations.add(
          InvoicePaymentAllocation(
            paymentMethod: InvoiceDraft.normalizePaymentMethod(
              rawPayment['paymentMethod']?.toString() ?? '',
            ),
            amount: amount,
          ),
        );
      }
    }

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
      paymentAllocations: paymentAllocations,
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

  bool _isBenefitPurchaseLine(InvoiceDraftLine line) =>
      line.itemType == 'membership_purchase' ||
      line.itemType == 'service_package_purchase';

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

  String? _nullableId(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
