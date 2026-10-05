import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/repositories/sqlite_lan_read_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async { await SalonDatabase.instance.close(); });
  tearDown(() async { await SalonDatabase.instance.close(); });

  test('empty desktop reads never seed customers, appointments, invoices or drafts', () async {
    final db = await SalonDatabase.instance.database;
    final reader = SqliteLanReadRepository(() async => db);
    final before = (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    for (final kind in SalonReadKind.values) {
      expect((await reader.read(SalonReadQuery(kind))).records, isEmpty);
    }
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'], before);
  });

  test('desktop projection: literal customer search, bounded pages, invoice totals and salon days', () async {
    final db = await SalonDatabase.instance.database;
    final now = DateTime(2026, 10, 5, 12);
    final stamp = now.toIso8601String();
    for (var i = 0; i < 27; i++) {
      await db.insert('customers', {
        'id': 'customer-$i', 'full_name': i == 0 ? 'An 100%' : 'Khách ${i.toString().padLeft(2, '0')}',
        'phone': '090${i.toString().padLeft(7, '0')}', 'tier': 'VIP', 'notes': 'Ghi chú thật',
        'created_at': stamp, 'updated_at': stamp,
      });
    }
    for (final day in [5, 6]) {
      await db.insert('appointments', {
        'id': 'appointment-$day', 'customer_id': 'customer-0',
        'starts_at': DateTime(2026, 10, day, 9, 30).toIso8601String(),
        'status': 'Đã xác nhận', 'customer_name': 'An 100%',
        'customer_phone': '0900000000', 'service_name': 'Cắt tóc',
        'staff_name': 'Lan', 'duration_minutes': 60,
        'created_at': stamp, 'updated_at': stamp,
      });
    }
    await db.insert('invoices', {
      'id': 'invoice-paid', 'customer_id': 'customer-0', 'appointment_id': 'appointment-5',
      'subtotal': 280000, 'discount_amount': 30000, 'total_amount': 250000,
      'payment_method': 'Tiền mặt', 'paid_at': stamp, 'created_at': stamp, 'updated_at': stamp,
    });
    await db.insert('invoices', {
      'id': 'invoice-draft-private', 'customer_id': 'customer-0',
      'subtotal': 0, 'discount_amount': 0, 'total_amount': 0,
      'payment_method': 'Tiền mặt', 'created_at': stamp, 'updated_at': stamp,
    });
    await db.insert('invoice_items', {
      'id': 'item-1', 'invoice_id': 'invoice-paid', 'title': 'Cắt tóc',
      'item_type': 'service', 'quantity': 2, 'unit_price': 150000,
      'discount_amount': 20000, 'total_price': 280000,
    });
    for (final (method, amount) in [('Tiền mặt', 100000), ('Chuyển khoản', 150000)]) {
      await db.insert('invoice_payments', {
        'id': 'payment-$amount', 'invoice_id': 'invoice-paid',
        'payment_method': method, 'amount': amount, 'created_at': stamp,
      });
    }
    await db.insert('invoice_adjustments', {
      'id': 'adjustment-1', 'invoice_id': 'invoice-paid', 'adjustment_type': 'refund',
      'reason': 'Đã hoàn tiền', 'amount': 250000, 'payment_method': 'Tiền mặt',
      'customer_id': 'customer-0', 'appointment_id': 'appointment-5', 'created_at': stamp,
    });
    final reader = SqliteLanReadRepository(() async => db, clock: () => now);
    final before = (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
    final first = await reader.read(SalonReadQuery(SalonReadKind.customers));
    expect(first.records, hasLength(25));
    expect(first.nextOffset, 25);
    final last = await reader.read(SalonReadQuery(SalonReadKind.customers, offset: 25));
    expect(last.records, hasLength(2));
    expect(last.nextOffset, isNull);
    expect({...first.records.map((r) => r.id), ...last.records.map((r) => r.id)}, hasLength(27));
    expect((await reader.read(SalonReadQuery(SalonReadKind.customers, query: '%'))).records.single.id,
      'customer-0');
    expect((await reader.read(SalonReadQuery(SalonReadKind.customers, query: '0900000000'))).records.single.id,
      'customer-0');
    final customer = (await reader.read(SalonReadQuery(SalonReadKind.customers, id: 'customer-0'))).records.single;
    expect(customer.fields['Ghi chú'], 'Ghi chú thật');
    final today = await reader.read(SalonReadQuery(SalonReadKind.appointments));
    expect(today.salonDate, '2026-10-05');
    expect(today.records.single.id, 'appointment-5');
    expect((await reader.read(SalonReadQuery(SalonReadKind.appointments, day: '2026-10-06'))).records.single.id,
      'appointment-6');
    final invoices = await reader.read(SalonReadQuery(SalonReadKind.invoices));
    expect(invoices.records.single.id, 'invoice-paid');
    final invoice = (await reader.read(SalonReadQuery(SalonReadKind.invoices, id: 'invoice-paid'))).records.single;
    expect(invoice.fields['Trạng thái'], 'Đã hoàn tiền');
    expect(invoice.fields['Tổng hóa đơn'], contains('250'));
    expect(invoice.fields['Phương thức'], allOf(contains('Tiền mặt'), contains('Chuyển khoản')));
    expect(invoice.fields['1. Cắt tóc'], allOf(contains('280'), contains('20')));
    await expectLater(reader.read(SalonReadQuery(SalonReadKind.invoices, id: 'invoice-draft-private')),
      throwsA(isA<PairingFailure>()));
    expect((await db.rawQuery('SELECT total_changes() AS n')).single['n'], before);
    expect(jsonEncode(invoice.toJson()), isNot(contains('schema_version')));
  });

  test('read contract rejects unknown/repeated params, impossible dates and oversized pages', () {
    for (final suffix in ['?limit=26', '?offset=-1', '?offset=100001', '?token=secret',
        '?role=owner', '?q=a&q=b', '?id=../x', '?day=2026-02-30', '?day=2026-10-05T00:00:00']) {
      expect(() => SalonReadQuery.fromUri(SalonReadKind.appointments, Uri.parse('https://salon/appointments$suffix')),
        throwsFormatException);
    }
    expect(() => SalonReadQuery(SalonReadKind.customers, query: 'x' * 81), throwsFormatException);
  });
}
