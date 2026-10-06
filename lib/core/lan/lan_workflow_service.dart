import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../data/fake/fake_salon_data_source.dart';
import '../database/appointment_mapper.dart';
import '../database/appointment_service_mapper.dart';
import '../database/customer_mapper.dart';
import '../database/salon_database.dart';
import '../models/appointment_entry.dart';
import '../models/appointment_upsert_input.dart';
import '../models/customer_upsert_input.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_payment_allocation.dart';
import '../models/audit_event.dart';
import '../repositories/guarded_salon_repositories.dart';
import '../repositories/sqlite_appointments_repository.dart';
import '../repositories/sqlite_billing_sessions_repository.dart';
import '../repositories/sqlite_customers_repository.dart';
import '../repositories/sqlite_invoices_repository.dart';
import '../services/sensitive_action_service.dart';
import 'lan_contract.dart';
import 'lan_pairing.dart';
import 'lan_write_contract.dart';
import 'lan_write_engine.dart';
import 'lan_workflow_models.dart';

abstract interface class LanWorkflowBackend {
  Future<LanEditorSnapshot> editor(String kind, String? id);
  Future<LanCatalogPage> catalog(String kind, String query, int offset);
  Future<LanWriteResult> execute(PairedPhone phone, LanWriteCommand command);
  Future<LanWriteResult?> result(String deviceId, String commandId);
}

const appointmentStatuses = ['Chờ xác nhận', 'Đã đặt', 'Đã đến', 'Đang làm', 'Hoàn thành', 'Đã hủy', 'Đã xác nhận'];

class LanWorkflowService implements LanWorkflowBackend {
  LanWorkflowService(this.database) : engine = LanWriteEngine(database);
  final SalonDatabase database;
  final LanWriteEngine engine;

  @override
  Future<LanWriteResult?> result(String deviceId, String commandId) => engine.result(deviceId, commandId);

  @override
  Future<LanEditorSnapshot> editor(String kind, String? id) async {
    if (!['customer', 'appointment', 'session'].contains(kind)) throw const FormatException('Invalid editor');
    if (id != null) { LanContract.validateIdentity(id, 'id'); }
    if (kind == 'session' && id == null) throw const FormatException('Missing session');
    final db = await database.database;
    return db.transaction((tx) async {
      final scope = SalonDatabase.forTransaction(tx, database.runtimeEpoch);
      Map<String, dynamic> values;
      if (kind == 'customer') {
        values = {'fullName': '', 'phone': '', 'email': '', 'tier': 'Standard',
          'favoriteService': '', 'hairProfile': '', 'note': ''};
        if (id != null) {
          final c = CustomerMapper.fromDatabase(await _row(tx, 'customers', id));
          values = {'fullName': c.fullName, 'phone': c.phone, 'email': c.email ?? '',
            'tier': c.tier, 'favoriteService': c.favoriteService, 'hairProfile': c.hairProfile, 'note': c.note};
        }
      } else if (kind == 'appointment') {
        values = {'customerId': '', 'serviceIds': <String>[], 'employeeId': '',
          'day': AppointmentMapper.dateKey(DateTime.now()), 'time': '09:00',
          'status': 'Đã đặt', 'durationMinutes': 90, 'slotLabel': '', 'note': '',
          'customerLabel': '', 'employeeLabel': '', 'serviceLabels': <String, String>{}};
        if (id != null) {
          final a = await _appointment(tx, id);
          values = {'customerId': a.customerId, 'serviceIds': a.services.isEmpty
              ? [if (a.serviceId != null) a.serviceId!] : a.services.map((s) => s.serviceId).toList(),
            'employeeId': a.employeeId ?? '', 'day': a.dateKey, 'time': a.timeLabel,
            'status': a.status, 'durationMinutes': a.durationMinutes, 'slotLabel': a.slotLabel, 'note': a.note,
            'customerLabel': a.customerName, 'employeeLabel': a.staffName,
            'serviceLabels': {for (final s in a.services) s.serviceId: s.title}};
        }
      } else {
        await _sessionExists(tx, id!);
        final bill = await SqliteBillingSessionsRepository(scope).fetchSession(id);
        final customer = bill.customerId.isEmpty ? <Map<String, Object?>>[] :
          await tx.query('customers', columns: ['full_name'], where: 'id = ?', whereArgs: [bill.customerId], limit: 1);
        if (bill.lines.length > 200) throw const PairingFailure(LanErrorCode.unavailable);
        final employeeIds = bill.lines.map((l) => l.employeeId).whereType<String>().toSet().toList();
        final employees = employeeIds.isEmpty ? <Map<String, Object?>>[] : await tx.query('employees',
          columns: ['id', 'full_name'], where: 'id IN (${List.filled(employeeIds.length, '?').join(',')})',
          whereArgs: employeeIds);
        final employeeNames = {for (final e in employees) e['id']: e['full_name']};
        final productIds = bill.lines.map((l) => l.productId).whereType<String>().toSet().toList();
        final stocks = productIds.isEmpty ? <Map<String, Object?>>[] : await tx.rawQuery(
          'SELECT p.id, p.low_stock_threshold, COALESCE(s.stock_on_hand, 0) AS stock_on_hand '
          'FROM retail_products p LEFT JOIN inventory_stock s ON s.product_id = p.id '
          'WHERE p.id IN (${List.filled(productIds.length, '?').join(',')})', productIds);
        final productStocks = {for (final stock in stocks) stock['id']: stock};
        values = {'customerId': bill.customerId, 'customerLabel': customer.isEmpty ? 'Chưa chọn khách' : customer.single['full_name'],
          'appointmentId': bill.appointmentId, 'updatedAt': bill.updatedAt.toIso8601String(), 'subtotal': bill.subtotal, 'discountAmount': bill.discountAmount,
          'totalAmount': bill.totalAmount, 'paymentMethod': bill.paymentMethod,
          'payments': bill.effectivePaymentAllocations.map((a) => {'method': a.paymentMethod, 'amount': a.amount}).toList(),
          'lines': bill.lines.map((l) => {'id': l.id, 'title': l.title, 'quantity': l.quantity,
            'unitPrice': l.unitPrice, 'discountAmount': l.discountAmount, 'totalPrice': l.totalPrice,
            'employeeId': l.employeeId, 'employeeLabel': employeeNames[l.employeeId] ?? '', 'isService': l.isService,
            if (l.isProduct) 'stockOnHand': productStocks[l.productId]?['stock_on_hand'],
            if (l.isProduct) 'lowStockThreshold': productStocks[l.productId]?['low_stock_threshold']}).toList()};
      }
      final snapshot = LanEditorSnapshot(kind: kind, epoch: database.runtimeEpoch, id: id,
        revision: id == null ? 0 : await engine.revision(tx, kind, id), values: values);
      if (utf8.encode(jsonEncode(snapshot.toJson())).length > 262144) {
        throw const PairingFailure(LanErrorCode.unavailable);
      }
      return snapshot;
    });
  }

  @override
  Future<LanCatalogPage> catalog(String kind, String query, int offset) async {
    if (!['customers', 'services', 'products', 'employees', 'sessions'].contains(kind) ||
        query.length > 80 || offset < 0 || offset > 100000 ||
        RegExp(r'[\x00-\x1f]').hasMatch(query)) { throw const FormatException('Invalid catalog query'); }
    final db = await database.database;
    return db.transaction((tx) async {
      final items = <LanCatalogItem>[];
      List<Map<String, Object?>> rows;
      if (kind == 'sessions') {
        // Search before pagination, including empty drafts held in settings.
        final sessionSearch = <String>[];
        final sessionArgs = <Object?>[];
        if (query.trim().isNotEmpty) {
          final q = query.trim();
          final variants = {q, q.toLowerCase(), q.toUpperCase(), q.toLowerCase().split(' ').map((part) =>
            part.isEmpty ? part : part[0].toUpperCase() + part.substring(1)).join(' ')};
          for (final column in ['d.id', 'c.full_name', 'c.phone']) {
            for (final variant in variants) {
              sessionSearch.add("$column LIKE ? ESCAPE '\\'");
              sessionArgs.add('%${variant.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%');
            }
          }
        }
        rows = await tx.rawQuery(
          "SELECT d.id, MAX(d.updated_at) AS touched FROM ("
          "SELECT id, updated_at, customer_id FROM invoices WHERE paid_at IS NULL UNION ALL "
          "SELECT CASE WHEN key = 'invoice_draft_state_v1' THEN 'invoice-draft-001' "
          "ELSE substr(key, 24) END AS id, updated_at, "
          "CASE WHEN json_valid(value) THEN json_extract(value, '\$.customerId') END AS customer_id "
          "FROM app_settings WHERE key = 'invoice_draft_state_v1' OR key LIKE 'invoice_draft_state_v2:%') d "
          "LEFT JOIN customers c ON c.id = d.customer_id "
          "${sessionSearch.isEmpty ? '' : 'WHERE (${sessionSearch.join(' OR ')}) '}"
          "GROUP BY d.id ORDER BY touched DESC, d.id ASC LIMIT 26 OFFSET ?",
          [...sessionArgs, offset]);
        final scope = SalonDatabase.forTransaction(tx, database.runtimeEpoch);
        for (final row in rows.take(25)) {
          final id = row['id'] as String;
          final bill = await SqliteBillingSessionsRepository(scope).fetchSession(id);
          final customers = await tx.query('customers', columns: ['full_name'], where: 'id = ?',
            whereArgs: [bill.customerId], limit: 1);
          items.add(LanCatalogItem(id, customers.isEmpty ? 'Bill chưa chọn khách' :
            customers.single['full_name'] as String, '${bill.totalAmount} đ · ${bill.lines.length} dòng',
            totalAmount: bill.totalAmount, lineCount: bill.lines.length, updatedAt: bill.updatedAt.toIso8601String()));
        }
      } else {
        final table = kind == 'products' ? 'retail_products' : kind;
        final name = ['customers', 'employees'].contains(kind) ? 'full_name' : 'name';
        final subtitle = kind == 'customers' ? 'phone' : kind == 'employees' ? 'status' : kind == 'products' ? 'sale_price' : 'price';
        final where = <String>[];
        final args = <Object?>[];
        if (kind == 'services' || kind == 'products') { where.add('is_active = 1'); }
        if (kind == 'products') where.add('is_hidden_from_staff = 0');
        if (kind == 'employees') { where.add('status IN (?, ?)'); args.addAll(['Đang làm việc', 'Sắp có lịch']); }
        if (query.trim().isNotEmpty) {
          final q = query.trim();
          final variants = {q, q.toLowerCase(), q.toUpperCase(), q.split(' ').map((s) =>
            s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase()).join(' ')};
          final columns = kind == 'customers' ? [name, 'phone'] : [name];
          final clauses = <String>[];
          for (final column in columns) {
            for (final variant in variants) {
              clauses.add("$column LIKE ? ESCAPE '\\'");
              args.add('%${variant.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%');
            }
          }
          where.add('(${clauses.join(' OR ')})');
        }
        rows = await tx.query(table, columns: ['id', name, subtitle, if (kind == 'products') ...['unit_name', 'low_stock_threshold']],
          where: where.isEmpty ? null : where.join(' AND '), whereArgs: args,
          orderBy: '$name COLLATE NOCASE, id', limit: 26, offset: offset);
        for (final row in rows.take(25)) {
          final stock = kind == 'products' ? await tx.query('inventory_stock',
            columns: ['stock_on_hand'], where: 'product_id = ?', whereArgs: [row['id']], limit: 1) : null;
          items.add(LanCatalogItem(row['id'] as String, row[name]?.toString() ?? '',
            '${row[subtitle] ?? ''}${['price', 'sale_price'].contains(subtitle) ? ' đ' : ''}'
            '${kind == 'products' && (row['unit_name'] as String? ?? '').isNotEmpty ? ' / ${row['unit_name']}' : ''}',
            stockOnHand: stock == null ? null : stock.isEmpty ? 0 : stock.single['stock_on_hand'] as int,
            lowStockThreshold: row['low_stock_threshold'] as int? ?? 5,
            unitPrice: ['price', 'sale_price'].contains(subtitle) ? (row[subtitle] as num).toInt() : null));
        }
      }
      return LanCatalogPage(items, database.runtimeEpoch, rows.length > 25 ? offset + 25 : null);
    });
  }

  @override
  Future<LanWriteResult> execute(PairedPhone phone, LanWriteCommand command) =>
    engine.execute(phone, command, (scope) => _mutate(scope, phone, command));

  Future<LanMutationTarget> _mutate(SalonDatabase scope, PairedPhone phone, LanWriteCommand command) async {
    final db = await scope.database;
    final p = _Payload(command.payload);
    final op = command.operation;
    final id = command.targetId;
    if (op == LanWriteOperation.customerCreate || op == LanWriteOperation.customerUpdate) {
      p.keys(['fullName', 'phone', 'email', 'tier', 'favoriteService', 'hairProfile', 'note']);
      final phoneNumber = p.text('phone', 24, required: true);
      if (!RegExp(r'^[+0-9 ()-]+$').hasMatch(phoneNumber) ||
          phoneNumber.replaceAll(RegExp(r'\D'), '').length < 6) { throw const FormatException('Invalid phone'); }
      final email = p.text('email', 120);
      if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) throw const FormatException('Invalid email');
      final saved = await SqliteCustomersRepository(scope).saveCustomer(CustomerUpsertInput(
        fullName: p.text('fullName', 120, required: true), phone: phoneNumber, email: email,
        tier: p.text('tier', 40, required: true), favoriteService: p.text('favoriteService', 200),
        hairProfile: p.text('hairProfile', 2000), note: p.text('note', 2000)), existingId: id);
      return LanMutationTarget(saved.id, 'customer');
    }
    final appointments = GuardedAppointmentsRepository(scope,
      SqliteAppointmentsRepository(scope, const FakeSalonDataSource()));
    if (op == LanWriteOperation.appointmentCreate || op == LanWriteOperation.appointmentUpdate) {
      p.keys(['customerId', 'serviceIds', 'employeeId', 'day', 'time', 'status', 'durationMinutes', 'slotLabel', 'note']);
      final customerId = p.identity('customerId');
      final employeeId = p.identity('employeeId');
      final serviceIds = p.identities('serviceIds', 20);
      final day = p.text('day', 10, required: true);
      final time = p.text('time', 5, required: true);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) throw const FormatException('Absolute date required');
      AppointmentMapper.buildStartsAt(dateLabel: day, timeLabel: time);
      final status = p.status();
      final customer = await _row(db, 'customers', customerId);
      final employee = await _row(db, 'employees', employeeId);
      final services = <Map<String, Object?>>[];
      for (final serviceId in serviceIds) {
        final service = await _row(db, 'services', serviceId);
        if (service['is_active'] != 1 && status != 'Đã hủy') { throw const PairingFailure(LanErrorCode.businessRule); }
        services.add(service);
      }
      final saved = await appointments.saveAppointment(AppointmentUpsertInput(
        customerId: customerId, serviceIds: serviceIds, employeeId: employeeId,
        customerName: customer['full_name'] as String, customerPhone: customer['phone'] as String,
        serviceName: services.map((s) => s['name']).join(' + '), staffName: employee['full_name'] as String,
        status: status, durationMinutes: p.integer('durationMinutes', 5, 1440),
        slotLabel: p.text('slotLabel', 40), note: p.text('note', 2000), dayLabel: day, timeLabel: time), existingId: id);
      return LanMutationTarget(saved.id, 'appointment');
    }
    if (op == LanWriteOperation.appointmentStatus) {
      p.keys(['status']);
      final saved = await appointments.updateAppointmentStatus(id!, p.status());
      return LanMutationTarget(saved.id, 'appointment');
    }
    final security = _DeviceSecurity(scope, phone.writeRole);
    final sessions = SqliteBillingSessionsRepository(scope, security);
    if ([LanWriteOperation.sessionQuantity, LanWriteOperation.sessionRemoveLine,
        LanWriteOperation.sessionAssignEmployee, LanWriteOperation.sessionPrice, LanWriteOperation.sessionUpdateLine].contains(op)) {
      final lineId = p.identity('lineId');
      final bill = await sessions.fetchSession(id!);
      if (!bill.lines.any((line) => line.id == lineId)) {
        throw const PairingFailure(LanErrorCode.businessRule);
      }
    }
    InvoiceDraft saved;
    switch (op) {
      case LanWriteOperation.sessionCreate:
        p.keys([]);
        saved = await sessions.createWalkInSession();
      case LanWriteOperation.sessionOpenAppointment:
        p.keys([]);
        final appointment = await _appointment(db, id!);
        if (appointment.status == 'Đã hủy') throw const PairingFailure(LanErrorCode.businessRule);
        saved = await sessions.openAppointmentSession(appointment);
      case LanWriteOperation.sessionSelectCustomer:
        p.keys(['customerId']);
        await _row(db, 'customers', p.identity('customerId'));
        saved = await sessions.selectCustomer(id!, p.identity('customerId'));
      case LanWriteOperation.sessionAddService:
        p.keys(['serviceId', 'employeeId']);
        final serviceId = p.identity('serviceId');
        if ((await _row(db, 'services', serviceId))['is_active'] != 1) throw const PairingFailure(LanErrorCode.businessRule);
        saved = await sessions.addService(id!, serviceId, employeeId: p.optionalIdentity('employeeId'));
      case LanWriteOperation.sessionAddProduct:
        p.keys(['productId']);
        final productId = p.identity('productId');
        final product = await _row(db, 'retail_products', productId);
        if (product['is_active'] != 1 || product['is_hidden_from_staff'] == 1) throw const PairingFailure(LanErrorCode.businessRule);
        saved = await sessions.addProduct(id!, productId);
      case LanWriteOperation.sessionQuantity:
        p.keys(['lineId', 'quantity']);
        saved = await sessions.updateLineQuantity(id!, p.identity('lineId'), p.integer('quantity', 1, 1000));
      case LanWriteOperation.sessionRemoveLine:
        p.keys(['lineId']);
        saved = await sessions.removeLine(id!, p.identity('lineId'));
      case LanWriteOperation.sessionAssignEmployee:
        p.keys(['lineId', 'employeeId']);
        saved = await sessions.updateLineEmployee(id!, p.identity('lineId'), p.optionalIdentity('employeeId'));
      case LanWriteOperation.sessionUpdateLine:
        p.keys(['lineId', 'quantity', 'employeeId', if (command.payload.containsKey('unitPrice')) 'unitPrice']);
        // All changes join the command transaction; a failed owner price guard
        // or employee validation rolls back quantity as well.
        final lineId = p.identity('lineId');
        saved = await sessions.updateLineQuantity(id!, lineId, p.integer('quantity', 1, 1000));
        final line = saved.lines.singleWhere((line) => line.id == lineId);
        final employee = p.optionalIdentity('employeeId');
        if (!line.isService && employee != null) throw const PairingFailure(LanErrorCode.businessRule);
        if (line.isService) { saved = await sessions.updateLineEmployee(id, lineId, employee); }
        if (command.payload.containsKey('unitPrice')) {
          saved = await sessions.updateLineUnitPrice(id, lineId, p.integer('unitPrice', 1, 1000000000000));
        }
      case LanWriteOperation.sessionDiscount:
        p.keys(['amount']);
        saved = await sessions.updateDiscount(id!, p.integer('amount', 0, 1000000000000));
      case LanWriteOperation.sessionPrice:
        p.keys(['lineId', 'amount']);
        saved = await sessions.updateLineUnitPrice(id!, p.identity('lineId'), p.integer('amount', 1, 1000000000000));
      case LanWriteOperation.sessionPayment:
        p.keys(['payments']);
        final raw = command.payload['payments'];
        if (raw is! List || raw.isEmpty || raw.length > 3) throw const FormatException('Invalid payments');
        final allocations = <InvoicePaymentAllocation>[];
        for (final item in raw) {
          if (item is! Map<String, dynamic>) throw const FormatException('Invalid allocation');
          final allocation = _Payload(item)..keys(['method', 'amount']);
          final method = allocation.text('method', 30, required: true);
          if (!InvoiceDraft.paymentMethods.contains(method)) throw const FormatException('Invalid method');
          allocations.add(InvoicePaymentAllocation(paymentMethod: method,
            amount: allocation.integer('amount', 0, 1000000000000)));
        }
        if (allocations.map((a) => a.paymentMethod).toSet().length != allocations.length) throw const FormatException('Duplicate method');
        if (allocations.length == 1) {
          final bill = await sessions.fetchSession(id!);
          if (allocations.single.amount != bill.totalAmount) throw const PairingFailure(LanErrorCode.businessRule);
          saved = await sessions.updatePaymentMethod(id, allocations.single.paymentMethod);
        } else {
          saved = await sessions.updatePaymentAllocations(id!, allocations);
        }
      case LanWriteOperation.sessionCheckout:
        p.keys([]);
        final raw = SqliteInvoicesRepository(scope, null, id!);
        await GuardedInvoicesRepository(scope, raw, security).checkoutInvoice();
        final receipt = raw.lastArchivedInvoiceId;
        if (receipt == null) throw StateError('No committed receipt');
        return LanMutationTarget(receipt, 'invoice');
      default:
        throw const FormatException('Unsupported command');
    }
    return LanMutationTarget(saved.id, 'session');
  }

  Future<Map<String, Object?>> _row(DatabaseExecutor db, String table, String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw const PairingFailure(LanErrorCode.notFound);
    return rows.single;
  }

  Future<AppointmentEntry> _appointment(DatabaseExecutor db, String id) async {
    final a = AppointmentMapper.fromDatabase(await _row(db, 'appointments', id));
    final lines = await db.query('appointment_services', where: 'appointment_id = ?', whereArgs: [id], orderBy: 'id');
    if (lines.length > 20) throw const PairingFailure(LanErrorCode.unavailable);
    return a.copyWith(services: lines.map(AppointmentServiceMapper.fromDatabase).toList());
  }

  Future<void> _sessionExists(DatabaseExecutor db, String id) async {
    final invoices = await db.query('invoices', columns: ['paid_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (invoices.isNotEmpty) {
      if (invoices.single['paid_at'] != null) throw const PairingFailure(LanErrorCode.alreadyPaid);
      return;
    }
    final rows = await db.query('app_settings', columns: ['key'], where: 'key = ?', whereArgs: [
      id == SqliteInvoicesRepository.legacyDraftInvoiceId ? SqliteInvoicesRepository.legacyDraftStateSettingsKey :
        '${SqliteInvoicesRepository.sessionDraftStateSettingsPrefix}$id'], limit: 1);
    if (rows.isEmpty) throw const PairingFailure(LanErrorCode.notFound);
  }
}

// An explicit desktop grant authorizes only these remote owner operations.
class _DeviceSecurity extends SensitiveActionService {
  _DeviceSecurity(super.database, this.role);
  final PhoneWriteRole role;
  @override
  Future<T> runSensitive<T>({required SensitiveAction action, required String targetType,
    required String targetId, required Future<T> Function() operation}) {
    if (role != PhoneWriteRole.owner ||
        ![SensitiveAction.billDiscount, SensitiveAction.billPriceEdit].contains(action)) {
      throw const PairingFailure(LanErrorCode.forbidden);
    }
    return operation();
  }
}

class _Payload {
  _Payload(this.value);
  final Map<String, dynamic> value;
  void keys(List<String> keys) {
    if (value.length != keys.length || value.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('Unexpected fields');
    }
  }
  String text(String key, int max, {bool required = false}) {
    final raw = value[key];
    if (raw is! String || raw.length > max || RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(raw)) {
      throw const FormatException('Invalid text');
    }
    final text = raw.trim();
    if (required && text.isEmpty) throw const FormatException('Required field');
    return text;
  }
  int integer(String key, int min, int max) {
    final v = value[key];
    if (v is! int || v < min || v > max) throw const FormatException('Invalid number');
    return v;
  }
  String identity(String key) {
    final v = text(key, 128, required: true);
    LanContract.validateIdentity(v, key);
    return v;
  }
  String? optionalIdentity(String key) => value[key] == null ? null : identity(key);
  List<String> identities(String key, int max) {
    final v = value[key];
    if (v is! List || v.isEmpty || v.length > max || v.any((s) => s is! String)) throw const FormatException('Invalid selection');
    final ids = v.cast<String>();
    for (final id in ids) { LanContract.validateIdentity(id, key); }
    if (ids.toSet().length != ids.length) throw const FormatException('Duplicate selection');
    return ids;
  }
  String status() {
    final s = text('status', 40, required: true);
    if (!appointmentStatuses.contains(s)) throw const FormatException('Invalid status');
    return s;
  }
}
