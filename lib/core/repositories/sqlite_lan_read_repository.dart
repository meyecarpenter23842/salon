import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../database/appointment_mapper.dart';
import '../database/appointment_service_mapper.dart';
import '../database/customer_mapper.dart';
import '../database/invoice_draft_mapper.dart';
import '../database/invoice_mapper.dart';
import '../lan/lan_contract.dart';
import '../lan/lan_pairing.dart';
import '../lan/lan_read_models.dart';
import '../models/invoice_draft.dart';
import '../models/invoice_payment_allocation.dart';

/// Reads the same desktop database and domain mappers without seeding, draft
/// creation, employee synchronization or any business write.
class SqliteLanReadRepository implements SalonReadRepository {
  SqliteLanReadRepository(this.openDatabase, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final Future<Database> Function() openDatabase;
  final DateTime Function() clock;
  static final _money = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0);
  static String text(Object? value) {
    final result = value?.toString() ?? '';
    // Long notes are explicitly shortened in this mobile projection.
    return result.length > 1000 ? '${result.substring(0, 1000)}…' : result;
  }
  static String money(num value) => _money.format(value);
  static String date(DateTime? value) =>
      value == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(value);

  @override
  Future<SalonReadPage> read(SalonReadQuery query) async {
    final database = await openDatabase();
    final today = salonDay(clock());
    // A consistent snapshot across parent rows, invoice items and adjustments.
    return database.transaction((db) async {
      final table = query.kind.name;
      final clauses = <String>[];
      final args = <Object?>[];
      if (query.id != null) { clauses.add('id = ?'); args.add(query.id); }
      if (query.kind == SalonReadKind.invoices) {
        clauses.add('paid_at IS NOT NULL');
      }
      if (query.query.isNotEmpty) {
        // SQLite LIKE folds ASCII only. Preserve accents and include normal
        // Vietnamese title/upper-case spellings without changing the schema.
        final lower = query.query.toLowerCase();
        final variants = {query.query, lower, query.query.toUpperCase(),
          lower.split(' ').map((part) => part.isEmpty ? part
              : '${part[0].toUpperCase()}${part.substring(1)}').join(' ')};
        String pattern(String value) => '%${value.replaceAll(r'\', r'\\')
            .replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
        final columns = query.kind == SalonReadKind.invoices
            ? ['invoices.id', '(SELECT full_name FROM customers WHERE customers.id = invoices.customer_id)',
              '(SELECT phone FROM customers WHERE customers.id = invoices.customer_id)']
            : ['full_name', 'phone'];
        final search = <String>[];
        for (final column in columns) {
          for (final variant in variants) {
            search.add("$column LIKE ? ESCAPE '\\'");
            args.add(pattern(variant));
          }
        }
        clauses.add('(${search.join(' OR ')})');
      }
      if (query.id == null && (query.kind == SalonReadKind.appointments ||
          query.kind == SalonReadKind.invoices && query.day != null)) {
        final day = DateTime.parse(query.day ?? today);
        final timeColumn = query.kind == SalonReadKind.invoices ? 'paid_at' : 'starts_at';
        clauses.add('$timeColumn >= ? AND $timeColumn < ?');
        args.addAll([day.toIso8601String(),
          DateTime(day.year, day.month, day.day + 1).toIso8601String()]);
      }
      final order = switch (query.kind) {
        SalonReadKind.customers => 'full_name COLLATE NOCASE ASC, id ASC',
        SalonReadKind.invoices => 'paid_at DESC, id DESC',
        SalonReadKind.appointments => 'starts_at ASC, id ASC',
      };
      final rows = await db.query(table, where: clauses.isEmpty ? null : clauses.join(' AND '),
        whereArgs: args, orderBy: order, offset: query.offset,
        limit: query.id == null ? query.limit + 1 : 1);
      if (query.id != null && rows.isEmpty) {
        throw const PairingFailure(LanErrorCode.notFound);
      }
      final records = <SalonReadRecord>[];
      for (final row in rows.take(query.limit)) {
        records.add(await _record(db, query.kind, row, query.id != null));
      }
      return SalonReadPage(records: records, salonDate: today,
        nextOffset: query.id == null && rows.length > query.limit
            ? query.offset + query.limit : null);
    }, exclusive: false);
  }

  Future<SalonReadRecord> _record(DatabaseExecutor db, SalonReadKind kind,
      Map<String, Object?> row, bool detail) async {
    if (kind == SalonReadKind.customers) {
      final c = CustomerMapper.fromDatabase(row);
      return SalonReadRecord(id: c.id, title: text(c.fullName),
        subtitle: '${text(c.phone)} · ${text(c.tier)}',
        fields: detail ? {
          'Điện thoại': text(c.phone), 'Email': text(c.email),
          'Hạng khách': text(c.tier), 'Dịch vụ yêu thích': text(c.favoriteService),
          'Lần đến gần nhất': date(c.lastVisitAt), 'Số lần đến': '${c.visitCount}',
          'Tổng chi tiêu': money(c.totalSpent), 'Điểm tích lũy': '${c.loyaltyPoints}',
          'Hồ sơ tóc': text(c.hairProfile), 'Ghi chú': text(c.note),
        } : const {});
    }
    if (kind == SalonReadKind.appointments) {
      final a = AppointmentMapper.fromDatabase(row);
      final services = await db.query('appointment_services',
        where: 'appointment_id = ?', whereArgs: [a.id], orderBy: 'id ASC', limit: 201);
      if (services.length > 200) throw const PairingFailure(LanErrorCode.unavailable);
      final names = services.map(AppointmentServiceMapper.fromDatabase)
          .map((s) => s.title).join(' + ');
      final paid = await db.query('invoices', columns: ['id'],
        where: 'appointment_id = ? AND paid_at IS NOT NULL AND NOT EXISTS ('
            "SELECT 1 FROM invoice_adjustments ia WHERE ia.invoice_id = invoices.id AND ia.adjustment_type = 'void')",
        whereArgs: [a.id], limit: 1);
      return SalonReadRecord(id: a.id, title: '${a.timeLabel} · ${text(a.customerName)}',
        subtitle: '${text(names.isEmpty ? a.serviceName : names)} · ${text(a.status)}',
        fields: detail ? {
          'Khách hàng': text(a.customerName), 'Điện thoại': text(a.customerPhone),
          'Bắt đầu (giờ máy salon)': date(a.startsAt), 'Kết thúc': date(a.endsAt),
          'Dịch vụ': text(names.isEmpty ? a.serviceName : names),
          'Nhân viên': text(a.staffName), 'Trạng thái': text(a.status),
          'Thanh toán': paid.isEmpty ? 'Chưa thanh toán' : 'Đã có hóa đơn thanh toán',
          'Ghi chú': text(a.note),
        } : const {});
    }
    final id = row['id'].toString();
    final items = await db.query('invoice_items', where: 'invoice_id = ?',
      whereArgs: [id], orderBy: 'id ASC', limit: 201);
    if (items.length > 200) throw const PairingFailure(LanErrorCode.unavailable);
    final payments = await db.query('invoice_payments', where: 'invoice_id = ?',
      whereArgs: [id], orderBy: 'id ASC', limit: 21);
    if (payments.length > 20) throw const PairingFailure(LanErrorCode.unavailable);
    final invoice = InvoiceMapper.fromDatabase(row,
      lines: items.map(InvoiceDraftMapper.fromDatabase).toList(),
      paymentAllocations: payments.map((p) => InvoicePaymentAllocation(
        paymentMethod: InvoiceDraft.normalizePaymentMethod(p['payment_method']?.toString() ?? ''),
        amount: (p['amount'] as num).toInt())).toList());
    final customers = await db.query('customers', columns: ['full_name'],
      where: 'id = ?', whereArgs: [invoice.customerId], limit: 1);
    final customer = customers.isEmpty ? 'Khách không còn trong danh sách'
        : text(customers.first['full_name']);
    final adjustments = await db.query('invoice_adjustments', columns: ['adjustment_type', 'amount'],
      where: 'invoice_id = ?', whereArgs: [id], orderBy: 'created_at DESC', limit: 1);
    final state = adjustments.isEmpty ? 'Đã thanh toán'
        : adjustments.first['adjustment_type'] == 'refund' ? 'Đã hoàn tiền' : 'Đã hủy hóa đơn';
    return SalonReadRecord(id: id, title: customer,
      subtitle: '${money(invoice.totalAmount)} · ${date(invoice.paidAt)} · $state',
      fields: detail ? {
        'Mã hóa đơn': id, 'Khách hàng': customer, 'Thanh toán lúc': date(invoice.paidAt),
        'Trạng thái': state, 'Tạm tính': money(invoice.subtotal),
        'Giảm giá hóa đơn': money(invoice.discountAmount),
        'Tổng hóa đơn': money(invoice.totalAmount), 'Phương thức': invoice.paymentSummary,
        for (final allocation in invoice.effectivePaymentAllocations)
          'Thanh toán ${allocation.paymentMethod}': money(allocation.amount),
        if (adjustments.isNotEmpty) 'Số tiền điều chỉnh': money((adjustments.first['amount'] as num).toInt()),
        for (final (index, line) in invoice.lines.indexed)
          '${index + 1}. ${text(line.title)}':
            '${line.quantity} × ${money(line.unitPrice)}; giảm ${money(line.discountAmount)}; thành tiền ${money(line.totalPrice)}',
      } : const {});
  }
}
